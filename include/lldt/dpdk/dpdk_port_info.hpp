#pragma once


#include <cstdint>
#include <optional>

#include <rte_ethdev.h>
#include <rte_ether.h>


namespace dpdk
{
    struct DpdkPortInfo
    {
        std::uint16_t port_id{};
        rte_eth_dev_info eth_dev_info{};
        rte_ether_addr eth_addr{};
        int socket_id{};
    };

    std::optional<DpdkPortInfo> try_get_dpdk_port_info() noexcept;
}