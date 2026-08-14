#include <lldt/dpdk/ena_tx_port.hpp>


#include <rte_ethdev.h>

namespace
{
    constexpr std::uint64_t REQUIRED_TX_OFFLOADS = RTE_ETH_TX_OFFLOAD_IPV4_CKSUM | RTE_ETH_TX_OFFLOAD_UDP_CKSUM;
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

        return rte_eth_dev_configure(port_id_, 0, 1, &cfg) == 0;
    }
}
