#pragma once


#include <cstdint>

#include <rte_mempool.h>


namespace dpdk
{
    class DpdkTxPort
    {
    public:
        static constexpr std::uint16_t TX_QUEUE_ID = 0;

        DpdkTxPort() = delete;
        DpdkTxPort(const DpdkTxPort&) = delete;
        DpdkTxPort(DpdkTxPort&&) = delete;
        DpdkTxPort& operator=(const DpdkTxPort&) = delete;
        DpdkTxPort& operator=(DpdkTxPort&&) = delete;

        ~DpdkTxPort();

        explicit DpdkTxPort(std::uint16_t port_id) noexcept;

        bool try_initialize(int socket_id, std::uint64_t tx_offload_capa) noexcept;

        rte_mempool* get_tx_mbuf_pool() const noexcept;
    private:
        std::uint16_t port_id_;
        rte_mempool* tx_mbuf_pool_{nullptr};
    };
}
