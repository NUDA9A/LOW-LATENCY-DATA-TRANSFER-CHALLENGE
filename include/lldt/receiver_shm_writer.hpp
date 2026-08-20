#pragma once


#include <shm_segment.h>
#include <shm_ring.h>

#include <string>
#include <cstdint>

#include <lldt/canonical_data_packet_view.hpp>


namespace transport
{
    class ReceiverShmWriter
    {
    public:
        ReceiverShmWriter(const std::string& shm_name, std::uint32_t slots);
        ~ReceiverShmWriter();

        void write(const CanonicalDataPacketView& packet) noexcept;
    private:
        shm::Segment segment_;
        shm::Ring ring_{};
    };
}
