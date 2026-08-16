#include <lldt/raw_data_packet_builder.hpp>


#include <cstring>

namespace transport
{
    static constexpr std::uint16_t DATA_HEADER_SIZE = 40;
    static constexpr std::uint32_t MAGIC_LLDT = 0x4c'4c'44'54; // LLDT
    static constexpr std::uint8_t RAW_CODEC_ID = 1;

    RawDataPacketBuildResult RawDataPacketBuilder::build_canonical(
        std::byte* output,
        const std::size_t capacity,
        const std::uint64_t session_id,
        const std::uint64_t data_seq,
        const ValidatedSourceFrameView& frame_view) noexcept
    {
        if (capacity < DATA_HEADER_SIZE + frame_view.frame_size)
        {
            return {RawDataPacketBuildStatus::OutputTooSmall, std::nullopt};
        }

        auto offset = writeSizeofTBE(output, MAGIC_LLDT);

        constexpr std::uint8_t protocol_version = 1;
        offset += writeSizeofTBE(output + offset, protocol_version);

        constexpr std::uint8_t packet_type = 1; // Data
        offset += writeSizeofTBE(output + offset, packet_type);

        offset += writeSizeofTBE(output + offset, DATA_HEADER_SIZE);

        offset += writeSizeofTBE(output + offset, session_id);

        offset += writeSizeofTBE(output + offset, data_seq);

        offset += writeSizeofTBE(output + offset, frame_view.source_seq_id); // first_source_seq

        offset += writeSizeofTBE(output + offset, frame_view.frame_size); // payload_length

        constexpr std::uint16_t record_count = 1;
        offset += writeSizeofTBE(output + offset, record_count); // amount of source frames into payload of 1 Data-packet

        offset += writeSizeofTBE(output + offset, RAW_CODEC_ID);

        constexpr std::uint8_t flags = 0;
        offset += writeSizeofTBE(output + offset, flags);

        std::memcpy(output + offset, frame_view.data, frame_view.frame_size);

        return {
            RawDataPacketBuildStatus::Ok,
            CanonicalDataPacketView{
                output,
                DATA_HEADER_SIZE + frame_view.frame_size,
                session_id,
                data_seq,
                frame_view.source_seq_id,
                record_count
            }
        };
    }

    PreparedDestination RawDataPacketBuilder::prepare_destination(
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
        destination.ipv4.total_length    = 0;                // заполняется в build()
        destination.ipv4.packet_id       = 0;
        destination.ipv4.fragment_offset = rte_cpu_to_be_16(RTE_IPV4_HDR_DF_FLAG);
        destination.ipv4.time_to_live    = 64;
        destination.ipv4.next_proto_id   = IPPROTO_UDP;
        destination.ipv4.hdr_checksum    = 0;                // IPv4 checksum offload
        destination.ipv4.src_addr        = local_ipv4;
        destination.ipv4.dst_addr        = receiver_ipv4;


        destination.udp.src_port    = rte_cpu_to_be_16(data_port);
        destination.udp.dst_port    = rte_cpu_to_be_16(data_port);
        destination.udp.dgram_len   = 0; // заполняется в build()
        destination.udp.dgram_cksum = 0; // в build() заменяется pseudo-header checksum

        return destination;
    }

    RawDataPacketBuildResult RawDataPacketBuilder::build(
        rte_mbuf* mbuf,
        const PreparedDestination& destination,
        std::uint64_t session_id,
        std::uint64_t data_seq,
        const ValidatedSourceFrameView& frame_view
        ) noexcept
    {
        const auto canonical_size = DATA_HEADER_SIZE + frame_view.frame_size;
        const auto udp_size = sizeof(rte_udp_hdr) + canonical_size;
        const auto ipv4_size = sizeof(rte_ipv4_hdr) + udp_size;
        const auto packet_size = sizeof(rte_ether_hdr) + ipv4_size;

        auto ipv4 = destination.ipv4;
        auto udp = destination.udp;

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

        auto* output = reinterpret_cast<std::byte*>(rte_pktmbuf_append(mbuf, static_cast<std::uint16_t>(packet_size)));

        if (!output)
        {
            return {RawDataPacketBuildStatus::OutputTooSmall, std::nullopt};
        }

        std::memcpy(output, &destination.ethernet, sizeof(rte_ether_hdr));
        output += sizeof(rte_ether_hdr);

        std::memcpy(output, &ipv4, sizeof(rte_ipv4_hdr));
        output += sizeof(rte_ipv4_hdr);

        std::memcpy(output, &udp, sizeof(rte_udp_hdr));
        output += sizeof(rte_udp_hdr);

        return build_canonical(
            output,
            canonical_size,
            session_id,
            data_seq,
            frame_view
        );
    }
}
