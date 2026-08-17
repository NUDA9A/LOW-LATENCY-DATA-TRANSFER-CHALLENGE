#include <lldt/dpdk/data_packet_materializer.hpp>

#include <cstring>

namespace dpdk
{
    std::byte* try_reserve_data_packet(rte_mbuf* mbuf) noexcept
    {
        auto* packet = reinterpret_cast<std::byte*>(rte_pktmbuf_append(mbuf, static_cast<std::uint16_t>(MAX_DATA_PACKET_SIZE)));
        if (!packet)
        {
            return nullptr;
        }

        return packet + PreparedDestination::HEADER_SIZE;
    }

    void finalize_data_packet(
        rte_mbuf* mbuf,
        const PreparedDestination& dst,
        const std::size_t canonical_size
        ) noexcept
    {
        const auto unused = DATA_PACKET_CANONICAL_CAPACITY - canonical_size;
        (void)rte_pktmbuf_trim(mbuf, static_cast<std::uint16_t>(unused));

        const auto udp_size = sizeof(rte_udp_hdr) + canonical_size;
        const auto ipv4_size = sizeof(rte_ipv4_hdr) + udp_size;

        auto ipv4 = dst.ipv4;
        auto udp = dst.udp;

        ipv4.total_length = rte_cpu_to_be_16(static_cast<std::uint16_t>(ipv4_size));

        udp.dgram_len = rte_cpu_to_be_16(static_cast<std::uint16_t>(udp_size));

        mbuf->l2_len = sizeof(rte_ether_hdr);
        mbuf->l3_len = sizeof(rte_ipv4_hdr);

        mbuf->packet_type =
        RTE_PTYPE_L2_ETHER |
        RTE_PTYPE_L3_IPV4 |
        RTE_PTYPE_L4_UDP;

        mbuf->ol_flags =
            RTE_MBUF_F_TX_IPV4 |
            RTE_MBUF_F_TX_IP_CKSUM |
            RTE_MBUF_F_TX_UDP_CKSUM;

        udp.dgram_cksum = rte_ipv4_phdr_cksum(&ipv4, mbuf->ol_flags);

        auto* output = rte_pktmbuf_mtod(mbuf, std::byte*);

        std::memcpy(output, &dst.ethernet, sizeof(rte_ether_hdr));
        output += sizeof(rte_ether_hdr);

        std::memcpy(output, &ipv4, sizeof(rte_ipv4_hdr));
        output += sizeof(rte_ipv4_hdr);

        std::memcpy(output, &udp, sizeof(rte_udp_hdr));
    }

    PreparedDestination prepare_destination(
        const rte_ether_addr& local_mac,
        const rte_ether_addr& next_hop_mac,
        rte_be32_t local_ipv4,
        rte_be32_t receiver_ipv4,
        std::uint16_t data_port
        ) noexcept
    {
        PreparedDestination destination{};

        destination.ethernet.dst_addr  = next_hop_mac;
        destination.ethernet.src_addr  = local_mac;
        destination.ethernet.ether_type = rte_cpu_to_be_16(RTE_ETHER_TYPE_IPV4);


        destination.ipv4.version_ihl     = RTE_IPV4_VHL_DEF; // IPv4, IHL = 5
        destination.ipv4.type_of_service = 0;                // DSCP = 0, ECN = 0
        destination.ipv4.total_length    = 0;                // заполняется в finalize_data_packet()
        destination.ipv4.packet_id       = 0;
        destination.ipv4.fragment_offset = rte_cpu_to_be_16(RTE_IPV4_HDR_DF_FLAG);
        destination.ipv4.time_to_live    = 64;
        destination.ipv4.next_proto_id   = IPPROTO_UDP;
        destination.ipv4.hdr_checksum    = 0;                // IPv4 checksum offload
        destination.ipv4.src_addr        = local_ipv4;
        destination.ipv4.dst_addr        = receiver_ipv4;


        destination.udp.src_port    = rte_cpu_to_be_16(data_port);
        destination.udp.dst_port    = rte_cpu_to_be_16(data_port);
        destination.udp.dgram_len   = 0; // заполняется в finalize_data_packet()
        destination.udp.dgram_cksum = 0; // в finalize_data_packet() заменяется pseudo-header checksum

        return destination;
    }
}