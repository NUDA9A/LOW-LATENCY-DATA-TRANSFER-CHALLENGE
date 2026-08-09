#pragma once


#include <lldt/validated_source_frame_view.hpp>
#include <lldt/canonical_data_packet_view.hpp>

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

    class RawDataPacketBuilder
    {
    public:
        static RawDataPacketBuildResult build(
            std::byte* output,
            std::size_t capacity,
            std::uint64_t session_id,
            std::uint64_t data_seq,
            const ValidatedSourceFrameView& frame_view) noexcept;
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