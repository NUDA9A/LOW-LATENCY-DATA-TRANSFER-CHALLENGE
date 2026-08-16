#pragma once


#include <cstdint>

#include "rte_mempool.h"

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

        bool try_initialize(int socket_id) noexcept;

        rte_mempool* get_tx_mbuf_pool() const noexcept;
    private:
        std::uint16_t port_id_;
        rte_mempool* tx_mbuf_pool_{nullptr};
    };
}
