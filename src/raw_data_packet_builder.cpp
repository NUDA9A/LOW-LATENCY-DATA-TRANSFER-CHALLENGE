#include <lldt/raw_data_packet_builder.hpp>


#include <cstring>


namespace transport
{
    static constexpr std::uint32_t MAGIC_LLDT = 0x4c'4c'44'54; // LLDT

    RawDataPacketBuilder::RawDataPacketBuilder(
        std::byte* output,
        const std::size_t capacity,
        const std::uint64_t data_seq,
        const ValidatedSourceFrameView& first_frame
        ) noexcept :
    output_(output),
    write_pos_(output + DATA_HEADER_SIZE + first_frame.frame_size),
    remaining_payload_capacity_(capacity - DATA_HEADER_SIZE - first_frame.frame_size),
    data_seq_(data_seq),
    record_count_(1)
    {
        std::memcpy(output + DATA_HEADER_SIZE, first_frame.data, first_frame.frame_size);
    }

    RawDataPacketBuildStatus RawDataPacketBuilder::try_append(const ValidatedSourceFrameView& frame) noexcept
    {
        if (frame.frame_size > remaining_payload_capacity_)
        {
            return RawDataPacketBuildStatus::OutputTooSmall;
        }

        std::memcpy(write_pos_, frame.data, frame.frame_size);
        write_pos_ += frame.frame_size;
        remaining_payload_capacity_ -= frame.frame_size;
        record_count_++;

        return RawDataPacketBuildStatus::Ok;
    }

    void RawDataPacketBuilder::writeLLDTHeader(
        std::byte* output,
        const std::uint64_t data_seq,
        const std::uint16_t record_count) noexcept
    {
        auto offset = writeSizeofTBE(output, MAGIC_LLDT);

        constexpr std::uint8_t protocol_version = 1;
        offset += writeSizeofTBE(output + offset, protocol_version);

        offset += writeSizeofTBE(output + offset, DATA_HEADER_SIZE);

        offset += writeSizeofTBE(output + offset, data_seq);

        offset += writeSizeofTBE(output + offset, record_count); // amount of source frames into payload of 1 Data-packet

        // padding
        std::uint8_t padding_byte{};
        for (std::size_t i = 0; i < 5; ++i)
        {
            offset += writeSizeofTBE(output + offset, padding_byte);
        }
    }

    CanonicalDataPacketView RawDataPacketBuilder::finalize() noexcept
    {
        writeLLDTHeader(output_, data_seq_, record_count_);
        const std::size_t packet_size = write_pos_ - output_;

        return CanonicalDataPacketView{
            output_,
            packet_size,
            data_seq_,
            record_count_
        };
    }

    RawDataPacketBuildResult RawDataPacketBuilder::build_canonical(
        std::byte* output,
        const std::size_t capacity,
        const std::uint64_t data_seq,
        const ValidatedSourceFrameView& frame_view) noexcept
    {
        if (capacity < DATA_HEADER_SIZE + frame_view.frame_size)
        {
            return {RawDataPacketBuildStatus::OutputTooSmall, std::nullopt};
        }

        RawDataPacketBuilder builder{
            output,
            capacity,
            data_seq,
            frame_view
        };

        return {
            RawDataPacketBuildStatus::Ok,
            builder.finalize()
        };
    }
}
