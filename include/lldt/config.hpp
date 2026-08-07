#pragma once

#include <string>
#include <cstdint>

namespace transport
{
    enum class StartupError
    {
        InvalidIpAddress,
        InvalidPort,
        UnknownArgument,
        InvalidSlotsValue,
        MissingValue,
        InvalidObservabilityMode,
        OK,
    };

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
        std::string local_ip{};
        std::string peer_ip{};
        std::uint16_t data_port{};
        std::uint16_t control_port{};
        ObservabilityMode observability = ObservabilityMode::Minimal;
        StartupError err = StartupError::OK;
    };

    EndpointConfig parse_endpoint_config(int argc, const char* argv[]);
}