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

        explicit EnaTxPort(std::uint16_t) noexcept;

        bool try_configure() const noexcept;
    private:
        std::uint16_t port_id_;
    };
}