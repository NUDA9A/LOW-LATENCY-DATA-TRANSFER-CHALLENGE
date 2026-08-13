#include <lldt/dpdk/ena_port_info.hpp>


#include <cstring>

namespace dpdk
{
    std::optional<EnaPortInfo> try_get_ena_port_info() noexcept
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

        EnaPortInfo ena_port_info{};

        ena_port_info.port_id = selected_port;
        if (rte_eth_dev_info_get(ena_port_info.port_id, &ena_port_info.eth_dev_info) != 0)
        {
            return std::nullopt;
        }

        if (ena_port_info.eth_dev_info.driver_name == nullptr || std::strcmp(ena_port_info.eth_dev_info.driver_name, "net_ena") != 0)
        {
            return std::nullopt;
        }

        if (rte_eth_macaddr_get(ena_port_info.port_id, &ena_port_info.eth_addr) != 0)
        {
            return std::nullopt;
        }

        if (ena_port_info.socket_id = rte_eth_dev_socket_id(ena_port_info.port_id); ena_port_info.socket_id < 0)
        {
            return std::nullopt;
        }

        return ena_port_info;
    }
}