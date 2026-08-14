#include <lldt/dpdk/ena_tx_port.hpp>


#include <rte_ethdev.h>

namespace
{
    constexpr std::uint64_t REQUIRED_TX_OFFLOADS = RTE_ETH_TX_OFFLOAD_IPV4_CKSUM | RTE_ETH_TX_OFFLOAD_UDP_CKSUM;
    constexpr std::uint16_t RX_QUEUE_NUMBER = 0;
    constexpr std::uint16_t TX_QUEUE_NUMBER = 1;
    constexpr std::uint16_t TX_QUEUE_ID = 0;
}

namespace dpdk
{
    EnaTxPort::EnaTxPort(const std::uint16_t port_id) noexcept : port_id_(port_id) {}

    EnaTxPort::~EnaTxPort()
    {
        rte_eth_dev_close(port_id_);
    }

    bool EnaTxPort::try_configure() const noexcept
    {
        rte_eth_conf cfg{};
        cfg.txmode.offloads |= REQUIRED_TX_OFFLOADS;

        return rte_eth_dev_configure(port_id_, RX_QUEUE_NUMBER, TX_QUEUE_NUMBER, &cfg) == 0;
    }

    bool EnaTxPort::try_setup_tx_queue(const int socket_id, std::uint16_t desc_count) noexcept
    {
        if (rte_eth_dev_adjust_nb_rx_tx_desc(port_id_, nullptr, &desc_count) != 0)
        {
            return false;
        }

        if (rte_eth_tx_queue_setup(port_id_, TX_QUEUE_ID, desc_count, socket_id, nullptr) != 0)
        {
            return false;
        }

        desc_count_ = desc_count;

        return true;
    }

    std::uint16_t EnaTxPort::get_effective_desc_count() const noexcept
    {
        return desc_count_;
    }
}
