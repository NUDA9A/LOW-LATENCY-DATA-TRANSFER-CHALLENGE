#pragma once


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

    inline constexpr std::size_t DATA_PACKET_CANONICAL_CAPACITY = 1472;

    inline constexpr std::size_t MAX_DATA_PACKET_SIZE = PreparedDestination::HEADER_SIZE + DATA_PACKET_CANONICAL_CAPACITY; // 1514

    std::byte* try_reserve_data_packet(rte_mbuf* mbuf) noexcept;

    void finalize_data_packet(
        rte_mbuf* mbuf,
        const PreparedDestination& dst,
        std::size_t canonical_size
        ) noexcept;

    PreparedDestination prepare_destination(
        const rte_ether_addr& local_mac,
        const rte_ether_addr& next_hop_mac,
        rte_be32_t local_ipv4,
        rte_be32_t receiver_ipv4,
        std::uint16_t data_port
        ) noexcept;
}