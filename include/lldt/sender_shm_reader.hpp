#pragma once

#include <shm_segment.h>
#include <shm_ring.h>
#include <lldt/validated_source_frame_view.hpp>

#include <cstdint>
#include <cstddef>
#include <array>
#include <string>
#include <optional>

namespace transport
{
    struct SenderInputCounters
    {
        std::uint64_t frames_read{};
        std::uint64_t bytes_read{};
        std::uint64_t empty_polls{};
        std::uint64_t lapped_events{};
        std::uint64_t lapped_frames_skipped{};
        std::uint64_t invalid_frames{};
        std::uint64_t source_gap_events{};
        std::uint64_t source_frames_missing{};
    };

    enum class SenderShmReaderStatus
    {
        Ok, Empty, Lapped, Invalid
    };

    struct SenderReaderResult
    {
        SenderShmReaderStatus status = SenderShmReaderStatus::Empty;
        std::optional<ValidatedSourceFrameView> frame_view = std::nullopt;
    };

    class SenderShmReader
    {
    public:
        SenderShmReader(const std::string& shm_name, std::uint32_t slots);

        SenderReaderResult try_read();
        const SenderInputCounters& get_counters() const noexcept;
    private:
        shm::Segment segment_;
        shm::Ring ring_{};
        std::uint64_t read_index_{};
        std::uint64_t prev_valid_{};
        bool has_prev_valid_{false};
        std::array<std::byte, shm::kFrameCap> buffer_{};
        SenderInputCounters counters_{};
    };
}