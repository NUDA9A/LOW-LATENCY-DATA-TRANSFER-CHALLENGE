#include <kernel/kernel_udp_tx.hpp>


#include <sys/socket.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <cstdio>
#include <cerrno>
#include <cstdlib>

namespace transport
{
    KernelUdpTx::KernelUdpTx(const std::string& localIpAddress)
    {
        fd_ = socket(AF_INET, SOCK_DGRAM | SOCK_NONBLOCK | SOCK_CLOEXEC, IPPROTO_UDP);
        if (fd_ == -1)
        {
            std::fprintf(stderr, "Failed to open socket\n");
            std::exit(1);
        }

        sockaddr_in local_addr{};
        local_addr.sin_family = AF_INET;
        if (inet_pton(AF_INET, localIpAddress.c_str(), &local_addr.sin_addr) != 1)
        {
            std::fprintf(stderr, "inet_pton error\n");
            std::exit(1);
        }
        local_addr.sin_port = htons(0);

        if (bind(fd_, reinterpret_cast<sockaddr*>(&local_addr), sizeof(local_addr)) < 0)
        {
            std::fprintf(stderr, "Failed to bind socket\n");
            std::exit(1);
        }
    }

    KernelUdpTx::~KernelUdpTx()
    {
        close_fd();
    }

    void KernelUdpTx::close_fd() noexcept
    {
        if (fd_ != -1)
        {
            close(fd_);
            fd_ = -1;
        }
    }

    PreparedDestination KernelUdpTx::prepare_destination(const std::string& peerIpAddress, const std::uint16_t port)
    {
        PreparedDestination res{};
        res.sin_port = htons(port);
        res.sin_family = AF_INET;
        if (inet_pton(AF_INET, peerIpAddress.c_str(), &res.sin_addr) != 1)
        {
            std::fprintf(stderr, "inet_pton error\n");
            std::exit(2);
        }

        return res;
    }

    SendResult KernelUdpTx::send(const std::byte* data, const std::size_t size, const PreparedDestination& prepared_destination) const noexcept
    {
        const auto sent_bytes = sendto(
            fd_,
            data,
            size,
            0,
            reinterpret_cast<const sockaddr*>(&prepared_destination),
            sizeof(prepared_destination)
        );

        SendResult res{};
        if (sent_bytes == static_cast<ssize_t>(size))
        {
            res.status = SendStatus::Sent;
            return res;
        }

        if (sent_bytes == -1)
        {
            res.error_number = errno;
        } else
        {
            res.error_number = EIO;
        }

        if (res.error_number != EIO && (res.error_number == EAGAIN
            || res.error_number == EINTR
            || res.error_number == ENOBUFS
            || res.error_number == ENOMEM))
        {
            res.status = SendStatus::Transient;
        }

        return res;
    }
}
