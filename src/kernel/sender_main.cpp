#include <lldt/config.hpp>
#include <lldt/sender_shm_reader.hpp>
#include <kernel/kernel_udp_tx.hpp>
#include <lldt/raw_data_packet_builder.hpp>

#include <array>
#include <cstddef>
#include <cstdint>
#include <cstdio>

#include <sys/random.h>


using SenderConfig = transport::EndpointConfig;

constexpr static std::size_t BUFFER_SIZE = 1472; // MTU=1500, 1500 - 20 (IP Header) - 8 (UDP Header) = 1472

int main(const int argc, const char* argv[])
{
    const SenderConfig config = transport::parse_endpoint_config(argc, argv);
    if (config.err != transport::StartupError::OK)
    {
        return 1;
    }

    transport::SenderShmReader reader(config.shm_name, config.slots);
    transport::KernelUdpTx udp_tx(config.local_ip);
    transport::RawDataPacketBuilder builder{};
    const auto dst = transport::KernelUdpTx::prepare_destination(config.peer_ip, config.data_port);
    std::array<std::byte, BUFFER_SIZE> buffer{};

    std::uint64_t session_id{};
    while (session_id == 0)
    {
        if (const auto res = getrandom(&session_id, sizeof(session_id), 0); res == -1 || res != static_cast<ssize_t>(sizeof(session_id)))
        {
            std::fprintf(stderr, "Failed to generate session id\n");
            return 2;
        }
    }
    std::uint64_t data_seq{};

    while (true)
    {
        const auto data = reader.try_read();
        if (data.status != transport::SenderShmReaderStatus::Ok)
        {
            continue;
        }

        const auto packet = builder.build(buffer.data(), BUFFER_SIZE, session_id, data_seq, *data.frame_view);
        if (packet.status != transport::RawDataPacketBuildStatus::Ok)
        {
            std::fprintf(stderr, "Failed to build packet\n");
            return 3;
        }
        data_seq++;

        const auto send_res = udp_tx.send(packet.canonical_data->data, packet.canonical_data->packet_size, dst);
        if (send_res.status == transport::SendStatus::HardError)
        {
            std::fprintf(stderr, "FATAL ERROR: Failed to send data. Error code: %i\nExiting...\n", send_res.error_number);
            return 4;
        }
    }

    return 0;
}