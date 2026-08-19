#include <lldt/dpdk/ena_rx_port.hpp>


#include <rte_ethdev.h>
#include <rte_mbuf.h>

#include <array>
#include <cstring>


namespace
{
    constexpr std::uint64_t REQUIRED_RX_OFFLOADS = RTE_ETH_RX_OFFLOAD_IPV4_CKSUM | RTE_ETH_RX_OFFLOAD_UDP_CKSUM;
    constexpr std::uint16_t RX_QUEUE_NUMBER = 1;
    constexpr std::uint16_t TX_QUEUE_NUMBER = 0;
    constexpr std::uint32_t MTU = 1500;
    constexpr std::uint16_t PRIV_SIZE = 0; // Need if we have metadata, which we don't have.
    constexpr std::uint16_t RX_DESC_COUNT = 1024;
    constexpr unsigned RX_MBUF_COUNT = 2047; // We need RX_MBUF_COUNT = 2^q - 1, so we take RX_DESC_COUNT(==1024) * 2 - 1
    constexpr unsigned RX_MBUF_CACHE_SIZE = 23; // We need RX_MBUF_COUNT % RX_MBUF_CACHE_SIZE == 0
    constexpr char MBUF_POOL_NAME[] = "lldt_rx_mbuf_pool";
}

namespace dpdk
{
    EnaRxPort::EnaRxPort(const std::uint16_t port_id) noexcept : port_id_(port_id) {}

    EnaRxPort::~EnaRxPort()
    {
        rte_eth_dev_stop(port_id_);
        rte_eth_dev_close(port_id_);
        rte_mempool_free(rx_mbuf_pool_);
    }

    bool EnaRxPort::try_initialize(const int socket_id) noexcept
    {
        rte_eth_conf cfg{};
        cfg.rxmode.mtu = MTU;
        cfg.rxmode.offloads |= REQUIRED_RX_OFFLOADS;
        if (rte_eth_dev_configure(port_id_, RX_QUEUE_NUMBER, TX_QUEUE_NUMBER, &cfg) != 0)
        {
            return false;
        }

        rx_mbuf_pool_ = rte_pktmbuf_pool_create(
            MBUF_POOL_NAME,
            RX_MBUF_COUNT,
            RX_MBUF_CACHE_SIZE,
            PRIV_SIZE,
            RTE_MBUF_DEFAULT_BUF_SIZE,
            socket_id
        );
        if (!rx_mbuf_pool_)
        {
            return false;
        }

        std::array<rte_mbuf*, RX_MBUF_COUNT> rx_mbufs{};
        if (rte_pktmbuf_alloc_bulk(rx_mbuf_pool_, rx_mbufs.data(), RX_MBUF_COUNT) != 0)
        {
            return false;
        }

        for (auto* mbuf : rx_mbufs)
        {
            std::memset(mbuf->buf_addr, 0, mbuf->buf_len);
        }

        rte_pktmbuf_free_bulk(rx_mbufs.data(), RX_MBUF_COUNT);

        rte_mbuf* cache_warmup_mbuf{nullptr};

        if (cache_warmup_mbuf = rte_pktmbuf_alloc(rx_mbuf_pool_); !cache_warmup_mbuf)
        {
            return false;
        }

        rte_pktmbuf_free(cache_warmup_mbuf);

        if (rte_eth_rx_queue_setup(port_id_, RX_QUEUE_ID, RX_DESC_COUNT, socket_id, nullptr, rx_mbuf_pool_) != 0)
        {
            return false;
        }

        return rte_eth_dev_start(port_id_) == 0;
    }

    rte_mempool* EnaRxPort::get_rx_mbuf_pool() const noexcept
    {
        return rx_mbuf_pool_;
    }
}