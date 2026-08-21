#include <lldt/config.hpp>
#include <lldt/dpdk/ena_port_info.hpp>
#include <lldt/dpdk/ena_rx_port.hpp>
#include <lldt/receiver_shm_writer.hpp>
#include <lldt/dpdk/ingress_packet_parser.hpp>

#include <rte_eal.h>
#include <rte_errno.h>
#include <rte_ethdev.h>
#include <rte_mbuf.h>

#include <csignal>
#include <cstdint>
#include <array>
#include <vector>
#include <cerrno>
#include <cstdio>


namespace
{
    constexpr std::uint16_t RX_BURST_SIZE = 32;

    volatile std::sig_atomic_t stop_requested{};

    struct ReceiverCounters
    {
        std::uint64_t rx_bursts{};
        std::uint64_t empty_rx_bursts{};
        std::uint64_t rx_packets{};
        std::uint64_t rx_bytes{};

        std::uint64_t ingress_rejected{};
        std::uint64_t invalid_checksums{};
        std::uint64_t invalid_lldt_packets{};

        std::uint64_t foreign_session_packets{};
        std::uint64_t stale_data_packets{};
        std::uint64_t data_gap_events{};
        std::uint64_t data_packets_missing{};

        std::uint64_t data_packets_accepted{};
        std::uint64_t frames_published{};
        std::uint64_t frame_bytes_published{};
    };

    void handle_signal(int)
    {
        stop_requested = 1;
    }

    void printReceiverCounters(const ReceiverCounters& counters)
    {
        std::fprintf(stdout, "ReceiverCounters:\n");
        std::fprintf(stdout, "Total RxBursts:\t%lu\n", counters.rx_bursts);
        std::fprintf(stdout, "Empty RxBursts:\t%lu\n", counters.empty_rx_bursts);
        std::fprintf(stdout, "Total received packets:\t%lu\n", counters.rx_packets);
        std::fprintf(stdout, "Total received bytes:\t%lu\n", counters.rx_bytes);
        std::fprintf(stdout, "Total rejected packets:\t%lu\n", counters.ingress_rejected);
        std::fprintf(stdout, "Total packets with invalid checksums:\t%lu\n", counters.invalid_checksums);
        std::fprintf(stdout, "Total invalid lldt packets:\t%lu\n", counters.invalid_lldt_packets);
        std::fprintf(stdout, "Total foreign session packets:\t%lu\n", counters.foreign_session_packets);
        std::fprintf(stdout, "Total stale packets:\t%lu\n", counters.stale_data_packets);
        std::fprintf(stdout, "Total gaps:\t%lu\n", counters.data_gap_events);
        std::fprintf(stdout, "Total missing packets:\t%lu\n", counters.data_packets_missing);
        std::fprintf(stdout, "Total accepted packets:\t%lu\n", counters.data_packets_accepted);
        std::fprintf(stdout, "Total frames published:\t%lu\n", counters.frames_published);
        std::fprintf(stdout, "Total bytes published:\t%lu\n\n", counters.frame_bytes_published);
    }

    void printRteStats(const rte_eth_stats& counters)
    {
        std::fprintf(stdout, "RteStats:\n");
        std::fprintf(stdout, "Successfully received packets:\t%lu\n", counters.ipackets);
        std::fprintf(stdout, "Successfully received bytes:\t%lu\n", counters.ibytes);
        std::fprintf(stdout, "Total packets missed by ha:\t%lu\n", counters.imissed);
        std::fprintf(stdout, "Total erroneous received packets:\t%lu\n", counters.ierrors);
        std::fprintf(stdout, "Total Rx mbuf allocation failures:\t%lu\n\n", counters.rx_nombuf);
    }

    void printRteXstats(const rte_eth_xstat_name xstats_names[], const rte_eth_xstat xstats[], const int xstats_count)
    {
        std::fprintf(stdout, "RteXstats:\n");

        for (int i = 0; i < xstats_count; ++i)
        {
            std::fprintf(stdout, "%s:\t%lu\n", xstats_names[i].name, xstats[i].value);
        }
    }

    int run_receiver(const int argc, char* argv[])
    {
        const auto configOpt = transport::try_parse_endpoint_config(argc, argv);
        if (!configOpt)
        {
            std::fprintf(stderr, "[ERROR]: Could not parse EndpointConfig.\n");
            return 1;
        }

        const auto ena_port_info = dpdk::try_get_ena_port_info();
        if (!ena_port_info)
        {
            std::fprintf(stderr, "[ERROR]: Could not get ena_port_info.\n");
            return 1;
        }

        transport::ReceiverShmWriter writer{configOpt->shm_name, configOpt->slots};

        dpdk::EnaRxPort port{ena_port_info->port_id};
        if (!port.try_initialize(ena_port_info->socket_id))
        {
            std::fprintf(stderr, "[ERROR]: Could not initialize EnaRxPort.\n");
            return 1;
        }

        std::array<rte_mbuf*, RX_BURST_SIZE> rx_mbufs{};
        ReceiverCounters counters{};

        bool session_established{false};
        std::uint64_t active_session_id{};
        std::uint64_t next_data_seq{};

        while (!stop_requested)
        {
            const auto received = rte_eth_rx_burst(ena_port_info->port_id, dpdk::EnaRxPort::RX_QUEUE_ID, rx_mbufs.data(), RX_BURST_SIZE);
            ++counters.rx_bursts;

            if (received == 0)
            {
                ++counters.empty_rx_bursts;
                continue;
            }

            for (std::size_t i = 0; i < received; ++i)
            {
                auto* mbuf = rx_mbufs[i];
                ++counters.rx_packets;
                counters.rx_bytes += mbuf->data_len;

                const auto ingress = transport::parse_ingress_packet(mbuf, *configOpt);
                switch (ingress.status)
                {
                case transport::IngressPacketParseStatus::Rejected:
                    ++counters.ingress_rejected;
                    continue;
                case transport::IngressPacketParseStatus::InvalidChecksum:
                    ++counters.invalid_checksums;
                    continue;
                default:
                    break;
                }

                const auto packet = transport::try_parse_canonical_data_packet(ingress.udp_payload, ingress.udp_payload_size);
                if (!packet)
                {
                    ++counters.invalid_lldt_packets;
                    continue;
                }

                if (!session_established)
                {
                    active_session_id = packet->session_id;
                    next_data_seq = packet->data_seq;
                    session_established = true;
                }

                if (packet->session_id != active_session_id)
                {
                    ++counters.foreign_session_packets;
                    continue;
                }

                if (packet->data_seq < next_data_seq)
                {
                    ++counters.stale_data_packets;
                    continue;
                }

                if (packet->data_seq > next_data_seq)
                {
                    ++counters.data_gap_events;
                    counters.data_packets_missing += packet->data_seq - next_data_seq;
                }

                writer.write(*packet);

                next_data_seq = packet->data_seq + 1;

                ++counters.data_packets_accepted;
                counters.frames_published += packet->record_count;
                counters.frame_bytes_published += packet->packet_size - 40;
            }

            rte_pktmbuf_free_bulk(rx_mbufs.data(), received);
        }

        rte_eth_stats rte_stats{};

        printReceiverCounters(counters);

        if (rte_eth_stats_get(ena_port_info->port_id, &rte_stats) == 0)
        {
            printRteStats(rte_stats);
        } else
        {
            std::fprintf(stderr, "[WARNING]: Could not retrieve rte_eth_stats\n");
        }

        const int xstats_count = rte_eth_xstats_get_names(ena_port_info->port_id, nullptr, 0);
        if (xstats_count > 0)
        {
            std::vector<rte_eth_xstat_name> xstats_names(xstats_count);
            std::vector<rte_eth_xstat> xstats(xstats_count);

            if (const int res = rte_eth_xstats_get_names(ena_port_info->port_id, xstats_names.data(), xstats_count); res < 0 || res != xstats_count)
            {
                std::fprintf(stderr, "[WARNING]: Could not retrieve xstats_names\n");
                return 0;
            }

            if (const int res = rte_eth_xstats_get(ena_port_info->port_id, xstats.data(), xstats_count); res < 0 || res != xstats_count)
            {
                std::fprintf(stderr, "[WARNING]: Could not retrieve xstats values\n");
                return 0;
            }

            printRteXstats(xstats_names.data(), xstats.data(), xstats_count);
        } else
        {
            std::fprintf(stderr, "[WARNING]: Could not retrieve xstats_count\n");
        }

        return 0;
    }
}


int main(int argc, char* argv[])
{
    int eal_argc{};
    if (eal_argc = rte_eal_init(argc, argv); eal_argc < 0)
    {
        std::fprintf(stderr, "[ERROR]: EAL init failed: %s.\n", rte_strerror(rte_errno));
        return 1;
    }

    argc -= eal_argc;
    argv += eal_argc;

    struct sigaction sa{};
    sa.sa_handler = handle_signal;

    sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0;

    if (sigaction(SIGTERM, &sa, nullptr) < 0 || sigaction(SIGINT, &sa, nullptr) < 0)
    {
        std::fprintf(stderr, "[ERROR]: sigaction failed: %s.\n", strerror(errno));
        if (rte_eal_cleanup())
        {
            std::fprintf(stderr, "[ERROR]: Could not cleanup EAL.\n");
        }

        return 1;
    }

    const int receiver_result = run_receiver(argc, argv);
    const int cleanup_result = rte_eal_cleanup();

    if (receiver_result)
    {
        std::fprintf(stderr, "[ERROR]: Receiver initialization failed.\n");
        return 1;
    }

    if (cleanup_result)
    {
        std::fprintf(stderr, "[ERROR]: Could not cleanup EAL.\n");
        return 1;
    }

    return 0;
}