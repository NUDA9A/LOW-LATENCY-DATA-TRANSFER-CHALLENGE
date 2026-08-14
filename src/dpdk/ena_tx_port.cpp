#include <lldt/dpdk/ena_tx_port.hpp>


#include <rte_ethdev.h>
#include <rte_mbuf.h>

namespace
{
    constexpr std::uint64_t REQUIRED_TX_OFFLOADS = RTE_ETH_TX_OFFLOAD_IPV4_CKSUM | RTE_ETH_TX_OFFLOAD_UDP_CKSUM;
    constexpr std::uint16_t RX_QUEUE_NUMBER = 0;
    constexpr std::uint16_t TX_QUEUE_NUMBER = 1;
    constexpr std::uint16_t TX_QUEUE_ID = 0;
    constexpr std::uint16_t PRIV_SIZE = 0; // Need if we have metadata, which we don't have.
    constexpr std::uint16_t TX_DESC_COUNT = 1024;
    constexpr unsigned TX_MBUF_COUNT = 2047; // We need TX_MBUF_COUNT = 2^q - 1, so we take TX_DESC_COUNT(==1024) * 2 - 1
    constexpr unsigned TX_MBUF_CACHE_SIZE = 23; // We need TX_MBUF_COUNT % TX_MBUF_CACHE_SIZE == 0
    constexpr char MBUF_POOL_NAME[] = "lldt_tx_mbuf_pool";
}

namespace dpdk
{
    EnaTxPort::EnaTxPort(const std::uint16_t port_id) noexcept : port_id_(port_id) {}

    EnaTxPort::~EnaTxPort()
    {
        rte_eth_dev_close(port_id_);
        rte_mempool_free(tx_mbuf_pool_);
    }

    bool EnaTxPort::try_configure() const noexcept
    {
        rte_eth_conf cfg{};
        cfg.txmode.offloads |= REQUIRED_TX_OFFLOADS;

        return rte_eth_dev_configure(port_id_, RX_QUEUE_NUMBER, TX_QUEUE_NUMBER, &cfg) == 0;
    }

    bool EnaTxPort::try_setup_tx_queue(const int socket_id) const noexcept
    {
        return rte_eth_tx_queue_setup(port_id_, TX_QUEUE_ID, TX_DESC_COUNT, socket_id, nullptr) == 0;
    }

    bool EnaTxPort::try_create_tx_mbuf_pool(int socket_id) noexcept
    {
        tx_mbuf_pool_ = rte_pktmbuf_pool_create(
            MBUF_POOL_NAME,
            TX_MBUF_COUNT,
            TX_MBUF_CACHE_SIZE,
            PRIV_SIZE,
            RTE_MBUF_DEFAULT_BUF_SIZE,
            socket_id
        );

        return tx_mbuf_pool_ != nullptr;
    }

    rte_mempool* EnaTxPort::get_tx_mbuf_pool() const noexcept
    {
        return tx_mbuf_pool_;
    }
}
