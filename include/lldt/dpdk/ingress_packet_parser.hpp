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

    enum class IngressPacketParseStatus
    {
        Ok,
        Rejected,
        InvalidChecksum
    };

    struct IngressPacketParseResult
    {
        IngressPacketParseStatus status = IngressPacketParseStatus::Rejected;
        const std::byte* udp_payload{nullptr};
        std::size_t udp_payload_size{};
    };

    IngressPacketParseResult parse_ingress_packet(rte_mbuf* mbuf, const EndpointConfig& config) noexcept;

    std::optional<CanonicalDataPacketView> try_parse_canonical_data_packet(const std::byte* data, std::size_t packet_size) noexcept;
}
