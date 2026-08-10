#pragma once
#include <netinet/in.h>


#include <string>
#include <cstdint>
#include <cstddef>

#include <lldt/send_result.hpp>

namespace transport
{
    using PreparedDestination = sockaddr_in;

    class KernelUdpTx
    {
    public:
        KernelUdpTx() = delete;

        KernelUdpTx(const KernelUdpTx&) = delete;
        KernelUdpTx& operator=(const KernelUdpTx&) = delete;
        KernelUdpTx(KernelUdpTx&&) = delete;
        KernelUdpTx& operator=(KernelUdpTx&&) = delete;

        ~KernelUdpTx();

        explicit KernelUdpTx(const std::string& localIpAddress);

        static PreparedDestination prepare_destination(const std::string& peerIpAddress, std::uint16_t port);

        [[nodiscard]] SendResult send(const std::byte*, std::size_t, const PreparedDestination&) const noexcept;
    private:
        void close_fd() noexcept;

        int fd_ = -1;
    };
}
