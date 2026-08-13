#pragma once


#include <cstdint>
#include <optional>

#include <rte_ethdev.h>
#include <rte_ether.h>


namespace dpdk
{
    struct EnaPortInfo
    {
        std::uint16_t port_id{};
        rte_eth_dev_info eth_dev_info{};
        rte_ether_addr eth_addr{};
        int socket_id{};
    };

    std::optional<EnaPortInfo> try_get_ena_port_info() noexcept;
}