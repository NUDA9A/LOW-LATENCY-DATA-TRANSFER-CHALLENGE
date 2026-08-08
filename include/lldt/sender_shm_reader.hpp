#pragma once

#include <shm_segment.h>
#include <shm_ring.h>

#include <cstdint>
#include <cstddef>
#include <array>
#include <string>

namespace transport
{
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
    private:
        shm::Segment segment_;
        shm::Ring ring_{};
        std::uint64_t read_index_{};
        std::uint32_t frame_len_{};
        std::array<std::byte, shm::kFrameCap> buffer_{};
    };
}