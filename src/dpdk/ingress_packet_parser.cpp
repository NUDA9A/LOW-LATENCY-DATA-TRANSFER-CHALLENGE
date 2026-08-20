#include <lldt/dpdk/ingress_packet_parser.hpp>


#include <rte_mbuf_core.h>

#include <cstring>
#include <cstdint>


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

    std::optional<CanonicalDataPacketView> try_parse_canonical_data_packet(const std::byte* data, const std::size_t packet_size) noexcept
    {
        if (packet_size < 40)
        {
            return std::nullopt;
        }

        constexpr std::uint8_t DATA_PREFIX[] = {
            0x4c, 0x4c, 0x44, 0x54, // LLDT
            0x01,                   // version
            0x01,                   // Data
            0x00, 0x28              // header size = 40
        };

        if (std::memcmp(data, DATA_PREFIX, sizeof(DATA_PREFIX)) != 0)
        {
            return std::nullopt;
        }

        rte_be64_t session_id{};
        std::memcpy(&session_id, data + 8, sizeof(session_id));

        rte_be64_t data_seq{};
        std::memcpy(&data_seq, data + 16, sizeof(data_seq));

        rte_be64_t first_src_seq{};
        std::memcpy(&first_src_seq, data + 24, sizeof(first_src_seq));

        rte_be16_t record_count{};
        std::memcpy(&record_count, data + 36, sizeof(record_count));

        return CanonicalDataPacketView{
            data,
            packet_size,
            rte_be_to_cpu_64(session_id),
            rte_be_to_cpu_64(data_seq),
            rte_be_to_cpu_64(first_src_seq),
            rte_be_to_cpu_16(record_count)
        };
    }
}
