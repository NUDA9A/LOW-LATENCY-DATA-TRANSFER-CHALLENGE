#include <lldt/config.hpp>
#include <lldt/dpdk/ena_port_info.hpp>
#include <lldt/dpdk/ena_tx_port.hpp>
#include <lldt/sender_shm_reader.hpp>
#include <lldt/dpdk/data_packet_materializer.hpp>
#include <lldt/raw_data_packet_builder.hpp>


#include <rte_eal.h>
#include <rte_errno.h>
#include <rte_ether.h>
#include <rte_mbuf.h>
#include <rte_ethdev.h>

#include <sys/random.h>

#include <cstdio>
#include <cstring>
#include <cstdint>
#include <optional>
#include <csignal>
#include <cerrno>


namespace
{
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

    int run_sender(const int argc, char* argv[])
    {
        const auto configOpt = transport::try_parse_endpoint_config(argc, argv);
        if (!configOpt)
        {
            return 1;
        }

        const auto ena_port_info = dpdk::try_get_ena_port_info();
        if (!ena_port_info)
        {
            return 1;
        }

        dpdk::EnaTxPort port{ena_port_info->port_id};
        if (!port.try_initialize(ena_port_info->socket_id))
        {
            return 1;
        }

        transport::SenderShmReader reader{configOpt->shm_name, configOpt->slots};

        rte_ether_addr next_hop_mac{};
        std::memcpy(next_hop_mac.addr_bytes, configOpt->next_hop_mac.data(), configOpt->next_hop_mac.size());

        const auto dst = dpdk::prepare_destination(
            ena_port_info->eth_addr,
            next_hop_mac,
            configOpt->local_ipv4_be,
            configOpt->peer_ipv4_be,
            configOpt->data_port
        );

        std::uint64_t session_id{};
        while (!session_id)
        {
            if (getrandom(&session_id, sizeof(session_id), 0) != static_cast<ssize_t>(sizeof(session_id)))
            {
                std::fprintf(stderr, "ERROR: Can not generate valid session_id.\n");
                return 1;
            }
        }

        std::uint64_t next_data_seq{};

        SenderDataCounters data_counters{};

        const bool batching_enabled = configOpt->batching_enabled;

        std::optional<transport::ValidatedSourceFrameView> carry_frame;

        bool stopping = false;

        while (true)
        {
            if (stop_requested)
            {
                stopping = true;
            }

            if (stopping && !carry_frame.has_value())
            {
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
                continue;
            }

            auto* canonical_output = dpdk::try_reserve_data_packet(mbuf);
            if (!canonical_output)
            {
                rte_pktmbuf_free(mbuf);
                std::fprintf(stderr, "ERROR: Could not reserve data packet.\n");
                return 1;
            }

            transport::RawDataPacketBuilder builder{
                canonical_output,
                dpdk::DATA_PACKET_CANONICAL_CAPACITY,
                session_id,
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

            if (rte_eth_tx_burst(ena_port_info->port_id, dpdk::EnaTxPort::TX_QUEUE_ID, &mbuf, 1) == 0)
            {
                data_counters.tx_packets_unsent++;
                rte_pktmbuf_free(mbuf);
                continue;
            }
            data_counters.tx_packets_enqueued++;
        }

        return 0;
    }
}

int main(int argc, char* argv[])
{
    int eal_argc{};
    if (eal_argc = rte_eal_init(argc, argv); eal_argc < 0)
    {
        std::fprintf(stderr, "ERROR: EAL init failed: %s.\n", rte_strerror(rte_errno));
        return 1;
    }

    argc -= eal_argc;
    argv += eal_argc;

    struct sigaction sa{};
    sa.sa_handler = handle_signal;

    sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0;

    if (sigaction(SIGTERM, &sa, nullptr) < 0)
    {
        std::fprintf(stderr, "ERROR: sigaction failed: %s.\n", strerror(errno));
        return 1;
    }

    if (sigaction(SIGINT, &sa, nullptr) < 0)
    {
        std::fprintf(stderr, "ERROR: sigaction failed: %s.\n", strerror(errno));
        return 1;
    }

    const int sender_result = run_sender(argc, argv);
    const int cleanup_result = rte_eal_cleanup();

    if (sender_result)
    {
        std::fprintf(stderr, "ERROR: Sender initialization failed.\n");
        return 1;
    }

    if (cleanup_result)
    {
        std::fprintf(stderr, "ERROR: Could not cleanup EAL.\n");
        return 1;
    }

    return 0;
}