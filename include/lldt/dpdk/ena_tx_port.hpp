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

        bool try_configure() const noexcept;
        bool try_setup_tx_queue(int socket_id) const noexcept;
        bool try_create_tx_mbuf_pool(int socket_id) noexcept;

        rte_mempool* get_tx_mbuf_pool() const noexcept;
    private:
        std::uint16_t port_id_;
        rte_mempool* tx_mbuf_pool_{nullptr};
    };
}
