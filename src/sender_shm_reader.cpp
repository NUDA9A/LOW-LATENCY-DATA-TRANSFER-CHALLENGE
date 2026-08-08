#include <lldt/sender_shm_reader.hpp>

#include <cstring>

#include <message.h>


namespace transport
{
    SenderShmReader::SenderShmReader(const std::string& shm_name, const std::uint32_t slots)
    : segment_(shm::Segment::open(shm_name, shm::region_size(slots), false))
    {
        ring_.attach(segment_.base(), slots, false);
        read_index_ = ring_.live_edge();
    }

    SenderShmReader::SenderShmReaderStatus SenderShmReader::try_read()
    {
        std::uint64_t resume_at{};
        std::uint32_t read_len{};

        frame_len_ = 0;
        const auto res = ring_.read(read_index_, buffer_.data(), &read_len, &resume_at);
        switch (res)
        {
        case shm::Ring::FrameStatus::kOk:
            {
                read_index_++;
                if (read_len < sizeof(msg::Header))
                {
                    return SenderShmReaderStatus::Invalid;
                }

                msg::Header header{};
                std::memcpy(&header, buffer_.data(), sizeof(msg::Header));

                if (header.body_len < sizeof(msg::Header) || header.body_len != read_len)
                {
                    return SenderShmReaderStatus::Invalid;
                }

                frame_len_ = read_len;

                return SenderShmReaderStatus::Ok;
            }
        case shm::Ring::FrameStatus::kEmpty:
            return SenderShmReaderStatus::Empty;
        case shm::Ring::FrameStatus::kLapped:
            read_index_ = resume_at;
            return SenderShmReaderStatus::Lapped;
        }
        __builtin_unreachable();
    }

    const std::byte* SenderShmReader::get_frame_ptr() const noexcept
    {
        return buffer_.data();
    }

    std::size_t SenderShmReader::get_frame_size() const noexcept
    {
        return frame_len_;
    }
}
