#include <lldt/dpdk/dpdk_tx_port.hpp>


#include <rte_ethdev.h>
#include <rte_mbuf.h>

#include <array>
#include <cstring>

namespace
{
    constexpr std::uint16_t RX_QUEUE_NUMBER = 0;
    constexpr std::uint16_t TX_QUEUE_NUMBER = 1;
    constexpr std::uint16_t PRIV_SIZE = 0; // Need if we have metadata, which we don't have.
    constexpr std::uint16_t TX_DESC_COUNT = 512;
    constexpr unsigned TX_MBUF_COUNT = 2047; // We need TX_MBUF_COUNT = 2^q - 1, so we take TX_DESC_COUNT(==1024) * 2 - 1
    constexpr unsigned TX_MBUF_CACHE_SIZE = 23; // We need TX_MBUF_COUNT % TX_MBUF_CACHE_SIZE == 0
    constexpr char MBUF_POOL_NAME[] = "lldt_tx_mbuf_pool";
}

namespace dpdk
{
    DpdkTxPort::DpdkTxPort(const std::uint16_t port_id) noexcept : port_id_(port_id) {}

    DpdkTxPort::~DpdkTxPort()
    {
        rte_eth_dev_stop(port_id_);
        rte_eth_dev_close(port_id_);
        rte_mempool_free(tx_mbuf_pool_);
    }

    bool DpdkTxPort::try_initialize(const int socket_id) noexcept
    {
        rte_eth_conf cfg{};

        if (rte_eth_dev_configure(port_id_, RX_QUEUE_NUMBER, TX_QUEUE_NUMBER, &cfg) != 0)
        {
            return false;
        }

        if (rte_eth_tx_queue_setup(port_id_, TX_QUEUE_ID, TX_DESC_COUNT, socket_id, nullptr) != 0)
        {
            return false;
        }

        tx_mbuf_pool_ = rte_pktmbuf_pool_create(
            MBUF_POOL_NAME,
            TX_MBUF_COUNT,
            TX_MBUF_CACHE_SIZE,
            PRIV_SIZE,
            RTE_MBUF_DEFAULT_BUF_SIZE,
            socket_id
        );
        if (!tx_mbuf_pool_)
        {
            return false;
        }

        std::array<rte_mbuf*, TX_MBUF_COUNT> tx_mbufs{};
        if (rte_pktmbuf_alloc_bulk(tx_mbuf_pool_, tx_mbufs.data(), TX_MBUF_COUNT) != 0)
        {
            return false;
        }

        for (auto* mbuf : tx_mbufs)
        {
            std::memset(mbuf->buf_addr, 0, mbuf->buf_len);
        }

        rte_pktmbuf_free_bulk(tx_mbufs.data(), TX_MBUF_COUNT);

        rte_mbuf* cache_warmup_mbuf{nullptr};

        if (cache_warmup_mbuf = rte_pktmbuf_alloc(tx_mbuf_pool_); !cache_warmup_mbuf)
        {
            return false;
        }

        rte_pktmbuf_free(cache_warmup_mbuf);

        return rte_eth_dev_start(port_id_) == 0;
    }

    rte_mempool* DpdkTxPort::get_tx_mbuf_pool() const noexcept
    {
        return tx_mbuf_pool_;
    }
}
