#pragma once

#include <lldt/raw_data_packet_builder.hpp>

#include <rte_mbuf.h>
#include <rte_ether.h>
#include <rte_ip4.h>
#include <rte_udp.h>

#include <cstddef>
#include <cstdint>

namespace dpdk
{
    struct PreparedDestination
    {
        static constexpr std::size_t HEADER_SIZE =
            sizeof(rte_ether_hdr) +
            sizeof(rte_ipv4_hdr) +
            sizeof(rte_udp_hdr);

        rte_ether_hdr ethernet{};
        rte_ipv4_hdr ipv4{};
        rte_udp_hdr udp{};
    };

    transport::RawDataPacketBuildResult build(
            rte_mbuf* mbuf,
            const PreparedDestination& destination,
            std::uint64_t session_id,
            std::uint64_t data_seq,
            const transport::ValidatedSourceFrameView& frame_view
            ) noexcept;

    PreparedDestination prepare_destination(
        const rte_ether_addr& local_mac,
        const rte_ether_addr& next_hop_mac,
        rte_be32_t local_ipv4,
        rte_be32_t receiver_ipv4,
        std::uint16_t data_port
        ) noexcept;
}