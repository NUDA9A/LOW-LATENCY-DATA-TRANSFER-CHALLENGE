#pragma once


#include <lldt/validated_source_frame_view.hpp>
#include <lldt/canonical_data_packet_view.hpp>

#include <rte_mbuf.h>
#include <rte_ether.h>
#include <rte_ip4.h>
#include <rte_udp.h>

#include <cstddef>
#include <cstdint>
#include <optional>

namespace transport
{
    enum class RawDataPacketBuildStatus
    {
        Ok, OutputTooSmall
    };

    struct RawDataPacketBuildResult
    {
        RawDataPacketBuildStatus status = RawDataPacketBuildStatus::OutputTooSmall;
        std::optional<CanonicalDataPacketView> canonical_data = std::nullopt;
    };

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

    class RawDataPacketBuilder
    {
    public:
        static RawDataPacketBuildResult build_canonical(
            std::byte* output,
            std::size_t capacity,
            std::uint64_t session_id,
            std::uint64_t data_seq,
            const ValidatedSourceFrameView& frame_view) noexcept;

        static RawDataPacketBuildResult build(
            rte_mbuf* mbuf,
            const PreparedDestination& destination,
            std::uint64_t session_id,
            std::uint64_t data_seq,
            const ValidatedSourceFrameView& frame_view
            ) noexcept;

        static PreparedDestination prepare_destination(
            const rte_ether_addr& local_mac,
            const rte_ether_addr& next_hop_mac,
            rte_be32_t local_ipv4,
            rte_be32_t receiver_ipv4,
            std::uint16_t data_port
            ) noexcept;
    private:
        template <typename T>
        static std::size_t writeSizeofTBE(std::byte* output, T value) noexcept
        {
            const auto size = sizeof(T);
            for (std::size_t i = 0; i < size; ++i)
            {
                output[i] = static_cast<std::byte>((value >> 8 * (size - i - 1)) & 0xFF);
            }

            return size;
        }
    };
}