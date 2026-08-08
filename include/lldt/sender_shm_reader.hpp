#pragma once

#include <shm_segment.h>
#include <shm_ring.h>

#include <cstdint>
#include <cstddef>
#include <array>
#include <string>

namespace transport
{
    struct SenderCounters
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

    class SenderShmReader
    {
    public:
        SenderShmReader(const std::string& shm_name, std::uint32_t slots);

        enum class SenderShmReaderStatus
        {
            Ok, Empty, Lapped, Invalid
        };

        SenderShmReaderStatus try_read();
        std::size_t get_frame_size() const noexcept;
        const std::byte* get_frame_ptr() const noexcept;
        const SenderCounters& get_counters() const noexcept;
    private:
        shm::Segment segment_;
        shm::Ring ring_{};
        std::uint64_t read_index_{};
        std::uint64_t prev_valid_{};
        std::uint32_t frame_len_{};
        bool has_prev_valid_{false};
        std::array<std::byte, shm::kFrameCap> buffer_{};
        SenderCounters counters_{};
    };
}