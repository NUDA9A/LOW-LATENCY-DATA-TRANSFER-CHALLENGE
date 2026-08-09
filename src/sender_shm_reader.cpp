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

    SenderReaderResult SenderShmReader::try_read()
    {
        std::uint64_t resume_at{};
        std::uint32_t read_len{};

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
                    return {SenderShmReaderStatus::Invalid, std::nullopt};
                }

                msg::Header header{};
                std::memcpy(&header, buffer_.data(), sizeof(msg::Header));

                if (header.body_len < sizeof(msg::Header) || header.body_len != read_len)
                {
                    counters_.invalid_frames++;
                    return {SenderShmReaderStatus::Invalid, std::nullopt};
                }

                ValidatedSourceFrameView frame_view{
                    buffer_.data(),
                    read_len,
                    header.seq_id,
                    false
                };

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
                            frame_view.begins_after_source_gap = true;
                            counters_.source_gap_events++;
                            counters_.source_frames_missing += dist - 1;
                        }

                        prev_valid_ = header.seq_id;
                    } else
                    {
                        frame_view.begins_after_source_gap = true;
                        counters_.source_gap_events++;
                    }
                }

                return {SenderShmReaderStatus::Ok, frame_view};
            }
        case shm::Ring::FrameStatus::kEmpty:
            counters_.empty_polls++;
            return {SenderShmReaderStatus::Empty, std::nullopt};
        case shm::Ring::FrameStatus::kLapped:
            counters_.lapped_events++;
            if (resume_at > read_index_)
            {
                counters_.lapped_frames_skipped += resume_at - read_index_;
            }
            read_index_ = resume_at;
            return {SenderShmReaderStatus::Lapped, std::nullopt};
        }
        __builtin_unreachable();
    }

    const SenderCounters& SenderShmReader::get_counters() const noexcept
    {
        return counters_;
    }
}
