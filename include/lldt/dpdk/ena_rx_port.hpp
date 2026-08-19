#pragma once


#include <cstdint>

#include <rte_mempool.h>


namespace dpdk
{
    class EnaRxPort
    {
    public:
        static constexpr std::uint16_t RX_QUEUE_ID = 0;

        EnaRxPort() = delete;
        EnaRxPort(const EnaRxPort&) = delete;
        EnaRxPort(EnaRxPort&&) = delete;
        EnaRxPort& operator=(const EnaRxPort&) = delete;
        EnaRxPort& operator=(EnaRxPort&&) = delete;

        ~EnaRxPort();

        explicit EnaRxPort(std::uint16_t port_id) noexcept;

        bool try_initialize(int socket_id) noexcept;

        rte_mempool* get_rx_mbuf_pool() const noexcept;
    private:
        std::uint16_t port_id_;
        rte_mempool* rx_mbuf_pool_{nullptr};
    };
}
