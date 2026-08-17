#pragma once

#include <string>
#include <cstdint>
#include <array>
#include <optional>

namespace transport
{
    enum class ObservabilityMode : std::uint8_t
    {
        Minimal = 1,
        Performance = 2,
        Diagnostic = 3,
        Size = 4,
    };

    struct EndpointConfig
    {
        std::string shm_name{};
        std::uint32_t slots{};
        std::uint32_t local_ipv4_be{};
        std::uint32_t peer_ipv4_be{};
        std::uint16_t data_port{};
        std::uint16_t control_port{};
        bool batching_enabled{false};
        std::array<std::uint8_t, 6> next_hop_mac{};
        ObservabilityMode observability = ObservabilityMode::Minimal;
    };

    std::optional<EndpointConfig> try_parse_endpoint_config(int argc, const char* const argv[]);
}