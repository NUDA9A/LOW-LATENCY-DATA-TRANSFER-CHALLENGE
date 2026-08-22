#pragma once


#include <lldt/config.hpp>
#include <lldt/canonical_data_packet_view.hpp>

#include <cstddef>
#include <optional>

#include <rte_mbuf.h>
#include <rte_ether.h>
#include <rte_ip4.h>
#include <rte_udp.h>


namespace transport
{
    inline constexpr std::size_t OUTER_HEADER_SIZE = // 42 bytes
        sizeof(rte_ether_hdr) + // 14
        sizeof(rte_ipv4_hdr) + // 20
        sizeof(rte_udp_hdr); // 8

    std::optional<CanonicalDataPacketView> try_parse_canonical_data_packet(rte_mbuf* mbuf) noexcept;
}
