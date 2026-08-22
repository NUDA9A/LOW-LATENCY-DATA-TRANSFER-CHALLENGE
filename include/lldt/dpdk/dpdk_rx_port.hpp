#pragma once


#include <cstdint>

#include <rte_mempool.h>


namespace dpdk
{
    class DpdkRxPort
    {
    public:
        static constexpr std::uint16_t RX_QUEUE_ID = 0;

        DpdkRxPort() = delete;
        DpdkRxPort(const DpdkRxPort&) = delete;
        DpdkRxPort(DpdkRxPort&&) = delete;
        DpdkRxPort& operator=(const DpdkRxPort&) = delete;
        DpdkRxPort& operator=(DpdkRxPort&&) = delete;

        ~DpdkRxPort();

        explicit DpdkRxPort(std::uint16_t port_id) noexcept;

        bool try_initialize(int socket_id) noexcept;

        rte_mempool* get_rx_mbuf_pool() const noexcept;
    private:
        std::uint16_t port_id_;
        rte_mempool* rx_mbuf_pool_{nullptr};
    };
}
