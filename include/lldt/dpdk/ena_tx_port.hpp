#pragma once


#include <cstdint>

namespace dpdk
{
    class EnaTxPort
    {
    public:
        EnaTxPort() = delete;
        EnaTxPort(const EnaTxPort&) = delete;
        EnaTxPort(EnaTxPort&&) = delete;
        EnaTxPort& operator=(const EnaTxPort&) = delete;
        EnaTxPort& operator=(EnaTxPort&&) = delete;

        ~EnaTxPort();

        explicit EnaTxPort(std::uint16_t port_id) noexcept;

        bool try_configure() const noexcept;
        bool try_setup_tx_queue(int socket_id, std::uint16_t desc_count) noexcept;
        std::uint16_t get_effective_desc_count() const noexcept;
    private:
        std::uint16_t port_id_;
        std::uint16_t desc_count_{};
    };
}