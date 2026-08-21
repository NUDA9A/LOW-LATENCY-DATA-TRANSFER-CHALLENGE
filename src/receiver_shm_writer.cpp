#include <lldt/receiver_shm_writer.hpp>


#include "message.h"

#include <cstring>


namespace transport
{
    ReceiverShmWriter::ReceiverShmWriter(const std::string& shm_name, const std::uint32_t slots)
        : segment_(shm::Segment::open(shm_name, shm::region_size(slots), true))
    {
        ring_.attach(segment_.base(), slots, true);
    }

    ReceiverShmWriter::~ReceiverShmWriter()
    {
        segment_.unlink();
    }

    void ReceiverShmWriter::write(const CanonicalDataPacketView& packet) noexcept
    {
        const std::byte* frame = packet.data + 22;

        for (std::size_t i = 0; i < packet.record_count; ++i)
        {
            msg::Header hdr{};
            std::memcpy(&hdr, frame, sizeof(hdr));

            const auto frame_size = msg::frame_size(hdr);
            ring_.publish(frame, frame_size);
            frame += frame_size;
        }
    }
}
