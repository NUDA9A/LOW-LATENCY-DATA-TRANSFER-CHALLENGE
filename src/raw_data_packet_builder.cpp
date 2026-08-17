#include <lldt/raw_data_packet_builder.hpp>


#include <cstring>

namespace transport
{
    static constexpr std::uint32_t MAGIC_LLDT = 0x4c'4c'44'54; // LLDT
    static constexpr std::uint8_t RAW_CODEC_ID = 1;

    RawDataPacketBuildResult RawDataPacketBuilder::build_canonical(
        std::byte* output,
        const std::size_t capacity,
        const std::uint64_t session_id,
        const std::uint64_t data_seq,
        const ValidatedSourceFrameView& frame_view) noexcept
    {
        if (capacity < DATA_HEADER_SIZE + frame_view.frame_size)
        {
            return {RawDataPacketBuildStatus::OutputTooSmall, std::nullopt};
        }

        auto offset = writeSizeofTBE(output, MAGIC_LLDT);

        constexpr std::uint8_t protocol_version = 1;
        offset += writeSizeofTBE(output + offset, protocol_version);

        constexpr std::uint8_t packet_type = 1; // Data
        offset += writeSizeofTBE(output + offset, packet_type);

        offset += writeSizeofTBE(output + offset, DATA_HEADER_SIZE);

        offset += writeSizeofTBE(output + offset, session_id);

        offset += writeSizeofTBE(output + offset, data_seq);

        offset += writeSizeofTBE(output + offset, frame_view.source_seq_id); // first_source_seq

        offset += writeSizeofTBE(output + offset, frame_view.frame_size); // payload_length

        constexpr std::uint16_t record_count = 1;
        offset += writeSizeofTBE(output + offset, record_count); // amount of source frames into payload of 1 Data-packet

        offset += writeSizeofTBE(output + offset, RAW_CODEC_ID);

        constexpr std::uint8_t flags = 0;
        offset += writeSizeofTBE(output + offset, flags);

        std::memcpy(output + offset, frame_view.data, frame_view.frame_size);

        return {
            RawDataPacketBuildStatus::Ok,
            CanonicalDataPacketView{
                output,
                DATA_HEADER_SIZE + frame_view.frame_size,
                session_id,
                data_seq,
                frame_view.source_seq_id,
                record_count
            }
        };
    }
}
