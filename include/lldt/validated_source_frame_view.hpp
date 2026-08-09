#pragma once


#include <cstddef>
#include <cstdint>

namespace transport
{
    struct ValidatedSourceFrameView
    {
        const std::byte* data{nullptr};
        std::uint32_t frame_size{};
        std::uint64_t source_seq_id{};
        bool begins_after_source_gap{false};
    };
}