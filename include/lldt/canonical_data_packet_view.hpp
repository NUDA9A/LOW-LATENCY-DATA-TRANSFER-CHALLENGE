#pragma once


#include <cstddef>
#include <cstdint>

namespace transport
{
    struct CanonicalDataPacketView
    {
        const std::byte* data{nullptr};
        std::size_t packet_size{};
        std::uint64_t data_seq{};
        std::uint16_t record_count{};
    };
}