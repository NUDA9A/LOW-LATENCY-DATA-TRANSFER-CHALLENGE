#include <lldt/dpdk/ingress_packet_parser.hpp>


#include <rte_mbuf_core.h>

#include <cstring>


namespace transport
{
    IngressPacketParseResult parse_ingress_packet(rte_mbuf* mbuf, const EndpointConfig& config) noexcept
    {
        if (mbuf->data_len < OUTER_HEADER_SIZE)
        {
            return {};
        }

        std::size_t offset{};

        rte_ether_hdr ether_hdr{};
        std::memcpy(&ether_hdr, rte_pktmbuf_mtod_offset(mbuf, const rte_ether_hdr*, offset), sizeof(ether_hdr));
        offset += sizeof(ether_hdr); // Ethernet header size == 14

        rte_ipv4_hdr ipv4_hdr{};
        std::memcpy(&ipv4_hdr, rte_pktmbuf_mtod_offset(mbuf, const rte_ipv4_hdr*, offset), sizeof(ipv4_hdr));
        offset += sizeof(ipv4_hdr); // IPv4 header size == 20

        rte_udp_hdr udp_hdr{};
        std::memcpy(&udp_hdr, rte_pktmbuf_mtod_offset(mbuf, const rte_udp_hdr*, offset), sizeof(udp_hdr));
        offset += sizeof(udp_hdr); // UDP header size == 8

        if (ether_hdr.ether_type != rte_cpu_to_be_16(RTE_ETHER_TYPE_IPV4) || ipv4_hdr.version_ihl != RTE_IPV4_VHL_DEF || ipv4_hdr.next_proto_id != IPPROTO_UDP)
        {
            return {};
        }

        if (ipv4_hdr.src_addr != config.peer_ipv4_be || ipv4_hdr.dst_addr != config.local_ipv4_be || udp_hdr.dst_port != rte_cpu_to_be_16(config.data_port))
        {
            return {};
        }

        if ((mbuf->ol_flags & RTE_MBUF_F_RX_IP_CKSUM_MASK) != RTE_MBUF_F_RX_IP_CKSUM_GOOD ||
            (mbuf->ol_flags & RTE_MBUF_F_RX_L4_CKSUM_MASK) != RTE_MBUF_F_RX_L4_CKSUM_GOOD)
        {
            return IngressPacketParseResult{IngressPacketParseStatus::InvalidChecksum};
        }

        return {
            IngressPacketParseStatus::Ok,
            rte_pktmbuf_mtod_offset(mbuf, const std::byte*, offset),
            mbuf->data_len - OUTER_HEADER_SIZE
        };
    }
}