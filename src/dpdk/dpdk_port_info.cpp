#include <lldt/dpdk/dpdk_port_info.hpp>


#include <cstring>

#include <rte_lcore.h>


namespace dpdk
{
    std::optional<DpdkPortInfo> try_get_dpdk_port_info() noexcept
    {
        uint16_t p, selected_port{RTE_MAX_ETHPORTS};

        RTE_ETH_FOREACH_DEV(p)
        {
            if (selected_port == RTE_MAX_ETHPORTS)
            {
                selected_port = p;
            }
            else
            {
                return std::nullopt;
            }
        }

        if (selected_port == RTE_MAX_ETHPORTS)
        {
            return std::nullopt;
        }

        DpdkPortInfo dpdk_port_info{};

        dpdk_port_info.port_id = selected_port;
        if (rte_eth_dev_info_get(dpdk_port_info.port_id, &dpdk_port_info.eth_dev_info) != 0)
        {
            return std::nullopt;
        }

        if (dpdk_port_info.eth_dev_info.driver_name == nullptr ||
            (std::strcmp(dpdk_port_info.eth_dev_info.driver_name, "net_ena") != 0 &&
            std::strcmp(dpdk_port_info.eth_dev_info.driver_name, "net_virtio") != 0))
        {
            return std::nullopt;
        }

        if (rte_eth_macaddr_get(dpdk_port_info.port_id, &dpdk_port_info.eth_addr) != 0)
        {
            return std::nullopt;
        }

        if (dpdk_port_info.socket_id = rte_eth_dev_socket_id(dpdk_port_info.port_id); dpdk_port_info.socket_id < 0)
        {
            dpdk_port_info.socket_id = static_cast<int>(rte_socket_id());
        }

        return dpdk_port_info;
    }
}