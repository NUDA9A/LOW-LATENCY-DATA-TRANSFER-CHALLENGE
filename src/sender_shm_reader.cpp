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
                counters_.frames_read++;
                counters_.bytes_read += read_len;

                read_index_++;
                if (read_len < sizeof(msg::Header))
                {
                    counters_.invalid_frames++;
                    return SenderShmReaderStatus::Invalid;
                }

                msg::Header header{};
                std::memcpy(&header, buffer_.data(), sizeof(msg::Header));

                if (header.body_len < sizeof(msg::Header) || header.body_len != read_len)
                {
                    counters_.invalid_frames++;
                    return SenderShmReaderStatus::Invalid;
                }

                if (!has_prev_valid_)
                {
                    has_prev_valid_ = true;
                    prev_valid_ = header.seq_id;
                } else
                {
                    if (header.seq_id > prev_valid_)
                    {
                        const auto dist = header.seq_id - prev_valid_;
                        if (dist > 1)
                        {
                            counters_.source_gap_events++;
                            counters_.source_frames_missing += dist - 1;
                        }

                        prev_valid_ = header.seq_id;
                    } else
                    {
                        counters_.source_gap_events++;
                    }
                }

                frame_len_ = read_len;

                return SenderShmReaderStatus::Ok;
            }
        case shm::Ring::FrameStatus::kEmpty:
            counters_.empty_polls++;
            return SenderShmReaderStatus::Empty;
        case shm::Ring::FrameStatus::kLapped:
            counters_.lapped_events++;
            if (resume_at > read_index_)
            {
                counters_.lapped_frames_skipped += resume_at - read_index_;
            }
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

    const SenderCounters& SenderShmReader::get_counters() const noexcept
    {
        return counters_;
    }
}
