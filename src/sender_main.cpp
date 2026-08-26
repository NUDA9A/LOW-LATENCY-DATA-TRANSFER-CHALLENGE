#include <lldt/config.hpp>
#include <lldt/dpdk/dpdk_port_info.hpp>
#include <lldt/dpdk/dpdk_tx_port.hpp>
#include <lldt/sender_shm_reader.hpp>
#include <lldt/dpdk/data_packet_materializer.hpp>
#include <lldt/raw_data_packet_builder.hpp>

#include <rte_eal.h>
#include <rte_errno.h>
#include <rte_ether.h>
#include <rte_mbuf.h>
#include <rte_ethdev.h>

#include <cstdio>
#include <cstring>
#include <cstdint>
#include <optional>
#include <csignal>
#include <cerrno>
#include <vector>
#include <array>


namespace
{
    constexpr std::uint16_t TX_BURST_CAPACITY = 4;

    volatile std::sig_atomic_t stop_requested{};

    void handle_signal(int)
    {
        stop_requested = 1;
    }

    struct alignas(64) SenderDataCounters {
        std::uint64_t frames_offered_to_packetization{};
        std::uint64_t mbuf_alloc_failures{};
        std::uint64_t frames_packetized{};
        std::uint64_t data_packets_built{};
        std::uint64_t data_payload_bytes{};
        std::uint64_t data_sequences_consumed{};
        std::uint64_t tx_packets_enqueued{};
        std::uint64_t tx_packets_unsent{};
    };

    void printInputCounters(const transport::SenderInputCounters& counters)
    {
        std::fprintf(stdout, "SenderInputCounters:\n");
        std::fprintf(stdout, "Frames read:\t%lu\n", counters.frames_read);
        std::fprintf(stdout, "Bytes read:\t%lu\n", counters.bytes_read);
        std::fprintf(stdout, "Empty polls:\t%lu\n", counters.empty_polls);
        std::fprintf(stdout, "Lapped events:\t%lu\n", counters.lapped_events);
        std::fprintf(stdout, "Lapped frames skipped:\t%lu\n", counters.lapped_frames_skipped);
        std::fprintf(stdout, "Invalid frames:\t%lu\n", counters.invalid_frames);
        std::fprintf(stdout, "Source gap events:\t%lu\n", counters.source_gap_events);
        std::fprintf(stdout, "Source frames missing:\t%lu\n\n", counters.source_frames_missing);
    }

    void printDataCounters(const SenderDataCounters& counters, const std::uint64_t tx_burst_calls)
    {
        std::fprintf(stdout, "SenderDataCounters:\n");
        std::fprintf(stdout, "Frames offered to packetization:\t%lu\n", counters.frames_offered_to_packetization);
        std::fprintf(stdout, "Mbuf alloc failures:\t%lu\n", counters.mbuf_alloc_failures);
        std::fprintf(stdout, "Frames packetized:\t%lu\n", counters.frames_packetized);
        std::fprintf(stdout, "Data packets built:\t%lu\n", counters.data_packets_built);
        std::fprintf(stdout, "Data payload bytes:\t%lu\n", counters.data_payload_bytes);
        std::fprintf(stdout, "Data sequences consumed:\t%lu\n", counters.data_sequences_consumed);
        std::fprintf(stdout, "Tx packets enqueued:\t%lu\n", counters.tx_packets_enqueued);
        std::fprintf(stdout, "Tx packets unsent:\t%lu\n", counters.tx_packets_unsent);
        std::fprintf(stdout, "Tx burst calls:\t%lu\n\n", tx_burst_calls);
    }

    void printRteStats(const rte_eth_stats& counters)
    {
        std::fprintf(stdout, "RteStats:\n");
        std::fprintf(stdout, "Successfully transmitted packets:\t%lu\n", counters.opackets);
        std::fprintf(stdout, "Successfully transmitted bytes:\t%lu\n", counters.obytes);
        std::fprintf(stdout, "Failed transmitted packets:\t%lu\n\n", counters.oerrors);
    }

    void printRteXstats(const rte_eth_xstat_name xstats_names[], const rte_eth_xstat xstats[], const int xstats_count)
    {
        std::fprintf(stdout, "RteXstats:\n");

        for (int i = 0; i < xstats_count; ++i)
        {
            std::fprintf(stdout, "%s:\t%lu\n", xstats_names[i].name, xstats[i].value);
        }
    }

    int run_sender(const int argc, char* argv[])
    {
        int err = 0;

        const auto configOpt = transport::try_parse_endpoint_config(argc, argv);
        if (!configOpt)
        {
            std::fprintf(stderr, "[ERROR]: Could not parse EndpointConfig.\n");
            return 1;
        }

        const auto dpdk_port_info = dpdk::try_get_dpdk_port_info();
        if (!dpdk_port_info)
        {
            std::fprintf(stderr, "[ERROR]: Could not get dpdk_port_info.\n");
            return 1;
        }

        dpdk::DpdkTxPort port{dpdk_port_info->port_id};
        if (!port.try_initialize(dpdk_port_info->socket_id))
        {
            std::fprintf(stderr, "[ERROR]: Could not initialize DpdkTxPort.\n");
            return 1;
        }

        transport::SenderShmReader reader{configOpt->shm_name, configOpt->slots};

        rte_ether_addr next_hop_mac{};
        std::memcpy(next_hop_mac.addr_bytes, configOpt->next_hop_mac.data(), configOpt->next_hop_mac.size());

        const auto dst = dpdk::prepare_destination(
            dpdk_port_info->eth_addr,
            next_hop_mac,
            configOpt->local_ipv4_be,
            configOpt->peer_ipv4_be,
            configOpt->data_port
        );

        std::uint64_t next_data_seq{};

        SenderDataCounters data_counters{};

        const bool batching_enabled = configOpt->batching_enabled;

        std::optional<transport::ValidatedSourceFrameView> carry_frame;

        bool stopping = false;

        std::array<rte_mbuf*, TX_BURST_CAPACITY> burst_buf{};
        std::uint16_t tx_burst_size{};
        std::uint64_t tx_burst_calls{};

        const auto flush = [&]()
        {
            if (tx_burst_size > 0)
            {
                std::uint16_t sent = rte_eth_tx_burst(dpdk_port_info->port_id, dpdk::DpdkTxPort::TX_QUEUE_ID, burst_buf.data(), tx_burst_size);
                for (std::size_t i = sent; i < tx_burst_size; ++i)
                {
                    rte_pktmbuf_free(burst_buf[i]);
                }
                data_counters.tx_packets_enqueued += sent;
                data_counters.tx_packets_unsent += tx_burst_size - sent;
                tx_burst_size = 0;
                ++tx_burst_calls;
            }
        };

        while (true)
        {
            if (stop_requested)
            {
                stopping = true;
            }

            if (stopping && !carry_frame.has_value())
            {
                flush();
                break;
            }

            transport::ValidatedSourceFrameView first_frame{};
            if (carry_frame)
            {
                first_frame = *carry_frame;
                carry_frame.reset();
            } else
            {
                const auto reader_res = reader.try_read();
                if (reader_res.status != transport::SenderShmReaderStatus::Ok)
                {
                    continue;
                }
                data_counters.frames_offered_to_packetization++;
                first_frame = reader_res.frame_view.value();
            }

            auto* mbuf = rte_pktmbuf_alloc(port.get_tx_mbuf_pool());
            if (!mbuf)
            {
                data_counters.mbuf_alloc_failures++;
                flush();
                continue;
            }

            auto* canonical_output = dpdk::try_reserve_data_packet(mbuf);
            if (!canonical_output)
            {
                rte_pktmbuf_free(mbuf);
                flush();
                std::fprintf(stderr, "[ERROR]: Could not reserve data packet.\n");
                err = 1;
                break;
            }

            transport::RawDataPacketBuilder builder{
                canonical_output,
                dpdk::DATA_PACKET_CANONICAL_CAPACITY,
                next_data_seq,
                first_frame
            };

            if (batching_enabled)
            {
                while (true)
                {
                    if (stop_requested)
                    {
                        stopping = true;

                        break;
                    }

                    const auto next = reader.try_read();
                    if (next.status != transport::SenderShmReaderStatus::Ok)
                    {
                        break;
                    }
                    data_counters.frames_offered_to_packetization++;

                    const auto& frame = *next.frame_view;
                    if (frame.begins_after_source_gap)
                    {
                        carry_frame = frame;
                        break;
                    }

                    if (builder.try_append(frame) != transport::RawDataPacketBuildStatus::Ok)
                    {
                        carry_frame = frame;
                        break;
                    }
                }
            }

            const auto canonical_data = builder.finalize();
            dpdk::finalize_data_packet(mbuf, dst, canonical_data.packet_size);

            data_counters.frames_packetized += canonical_data.record_count;
            data_counters.data_packets_built++;
            data_counters.data_payload_bytes += canonical_data.packet_size - transport::RawDataPacketBuilder::DATA_HEADER_SIZE;
            data_counters.data_sequences_consumed++;
            next_data_seq++;

            burst_buf[tx_burst_size++] = mbuf;

            if (tx_burst_size == TX_BURST_CAPACITY)
            {
                flush();
                continue;
            }

            if (carry_frame)
            {
                continue;
            }

            if (batching_enabled)
            {
                flush();
                continue;
            }

            if (stop_requested)
            {
                stopping = true;
                flush();
                continue;
            }

            const auto next = reader.try_read();
            if (next.status != transport::SenderShmReaderStatus::Ok)
            {
                flush();
                continue;
            }

            carry_frame = next.frame_view;
            data_counters.frames_offered_to_packetization++;
        }

        rte_eth_stats rte_stats{};

        printInputCounters(reader.get_counters());
        printDataCounters(data_counters, tx_burst_calls);

        if (rte_eth_stats_get(dpdk_port_info->port_id, &rte_stats) == 0)
        {
            printRteStats(rte_stats);
        } else
        {
            std::fprintf(stderr, "[WARNING]: Could not retrieve rte_eth_stats\n");
        }

        const int xstats_count = rte_eth_xstats_get_names(dpdk_port_info->port_id, nullptr, 0);
        if (xstats_count > 0)
        {
            std::vector<rte_eth_xstat_name> xstats_names(xstats_count);
            std::vector<rte_eth_xstat> xstats(xstats_count);

            if (const int res = rte_eth_xstats_get_names(dpdk_port_info->port_id, xstats_names.data(), xstats_count); res < 0 || res != xstats_count)
            {
                std::fprintf(stderr, "[WARNING]: Could not retrieve xstats_names\n");
                return err;
            }

            if (const int res = rte_eth_xstats_get(dpdk_port_info->port_id, xstats.data(), xstats_count); res < 0 || res != xstats_count)
            {
                std::fprintf(stderr, "[WARNING]: Could not retrieve xstats values\n");
                return err;
            }

            printRteXstats(xstats_names.data(), xstats.data(), xstats_count);
        } else
        {
            std::fprintf(stderr, "[WARNING]: Could not retrieve xstats_count\n");
        }

        return err;
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

    const int sender_result = run_sender(argc, argv);
    const int cleanup_result = rte_eal_cleanup();

    if (sender_result)
    {
        std::fprintf(stderr, "[ERROR]: Sender initialization failed.\n");
        return 1;
    }

    if (cleanup_result)
    {
        std::fprintf(stderr, "[ERROR]: Could not cleanup EAL.\n");
        return 1;
    }

    return 0;
}