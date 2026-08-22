#include <lldt/dpdk/ingress_packet_parser.hpp>


#include <rte_mbuf_core.h>

#include <cstring>
#include <cstdint>


namespace transport
{
    std::optional<CanonicalDataPacketView> try_parse_canonical_data_packet(rte_mbuf* mbuf) noexcept
    {
        if (mbuf->data_len < 64)
        {
            return std::nullopt;
        }

        constexpr std::uint8_t DATA_PREFIX[] = {
            0x4c, 0x4c, 0x44, 0x54, // LLDT
            0x01,                   // version
            0x00, 0x16,              // header size = 22
        };

        const auto* data = rte_pktmbuf_mtod_offset(mbuf, const std::byte*, OUTER_HEADER_SIZE);

        if (std::memcmp(data, DATA_PREFIX, sizeof(DATA_PREFIX)) != 0)
        {
            return std::nullopt;
        }

        rte_be64_t data_seq{};
        std::memcpy(&data_seq, data + 7, sizeof(data_seq));

        rte_be16_t record_count{};
        std::memcpy(&record_count, data + 15, sizeof(record_count));

        return CanonicalDataPacketView{
            data,
            mbuf->data_len - OUTER_HEADER_SIZE,
            rte_be_to_cpu_64(data_seq),
            rte_be_to_cpu_16(record_count)
        };
    }
}
