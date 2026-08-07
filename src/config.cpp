#include <lldt/config.hpp>

#include <string_view>
#include <string>
#include <cctype>
#include <cstdio>
#include <charconv>
#include <cstring>
#include <system_error>
#include <optional>
#include <arpa/inet.h>
#include <functional>

static bool equals_ignore_case(const std::string_view lhs, const std::string_view rhs, const bool isValue = false) noexcept
{
    if (lhs.size() != rhs.size())
    {
        return false;
    }

    std::size_t start = 0;

    if (!isValue) {
        if (lhs[0] != rhs[0] || lhs[1] != rhs[1])
        {
            return false;
        }
        start = 2;
    }

    for (std::size_t i = start; i < lhs.size(); ++i)
    {
        if (std::tolower(static_cast<unsigned char>(lhs[i])) != std::tolower(static_cast<unsigned char>(rhs[i])))
        {
            return false;
        }
    }

    return true;
}

template <typename T>
std::optional<T> parseNumFromString(const char* str, const std::size_t size, const std::string& name)
{
    T res{};

    auto [ptr, ec] = std::from_chars(str, str + size, res);
    if (ec != std::errc() || ptr != str + size)
    {
        std::fprintf(stderr, "[ERROR]: Invalid %s: %s.\n", name.c_str(), str);
        return std::nullopt;
    }

    return res;
}

static void parseIpArg(
    bool& ipFlag,
    transport::EndpointConfig& config,
    const std::string& flagName,
    std::string& ipMember,
    const std::function<std::string()>& next)
{
    if (ipFlag)
    {
        std::fprintf(stderr, "[ERROR]: --%s flag already set.\n", flagName.c_str());
        config.err = transport::StartupError::UnknownArgument;
        return;
    }

    const auto& ipArg = next();
    if (config.err != transport::StartupError::OK)
    {
        return;
    }

    in_addr ip_binary{};

    if (inet_pton(AF_INET, ipArg.c_str(), &ip_binary) != 1)
    {
        std::fprintf(stderr, "[ERROR]: Invalid %s address.\n", flagName.c_str());
        config.err = transport::StartupError::InvalidIpAddress;
        return;
    }

    ipMember = ipArg;

    ipFlag = true;
}

static void parsePortArg(
    bool& portFlag,
    transport::EndpointConfig& config,
    const std::string& flagName,
    std::uint16_t& portMember,
    const std::function<std::string()>& next)
{
    if (portFlag)
    {
        std::fprintf(stderr, "[ERROR]: --%s flag already set.\n", flagName.c_str());
        config.err = transport::StartupError::UnknownArgument;
        return;
    }

    const auto& portArg = next();
    if (config.err != transport::StartupError::OK)
    {
        return;
    }

    config.err = transport::StartupError::InvalidPort;

    const auto portOpt = parseNumFromString<std::uint16_t>(portArg.c_str(), strlen(portArg.c_str()), flagName.c_str());
    if (!portOpt)
    {
        return;
    }

    const std::uint16_t port = *portOpt;
    if (port == 0)
    {
        std::fprintf(stderr, "[ERROR]: %s value is zero: %s.\n", flagName.c_str(), portArg.c_str());
        return;
    }

    portMember = port;
    config.err = transport::StartupError::OK;

    portFlag = true;
}

namespace transport
{
    EndpointConfig parse_endpoint_config(const int argc, const char* argv[])
    {
        EndpointConfig config{};

        bool shmFlag = false;
        bool slotsFlag = false;
        bool localIpFlag = false;
        bool peerIpFlag = false;
        bool dataPortFlag = false;
        bool controlPortFlag = false;
        bool observabilityFlag = false;

        for (int i = 1; i < argc; ++i)
        {
            const auto arg = argv[i];

            auto next = [&]() -> std::string {
                if (i + 1 >= argc || (strlen(argv[i + 1]) > 1 && argv[i + 1][0] == '-' && argv[i + 1][1] == '-')) {
                    std::fprintf(stderr, "[ERROR]: Usage: ./executable"
                                 "--shm <name>\n"
                                 "--slots <N>\n"
                                 "--local-ip <IPv4>\n"
                                 "--peer-ip <IPv4>\n"
                                 "--data-port <port>\n"
                                 "--control-port <port>\n"
                                 "--observability minimal|performance|diagnostic\n");
                    config.err = StartupError::MissingValue;
                    return "";
                }
                return argv[++i];
            };

            if (equals_ignore_case(arg, "--shm"))
            {
                if (shmFlag)
                {
                    std::fprintf(stderr, "[ERROR]: --shm flag already set.\n");
                    config.err = StartupError::UnknownArgument;
                    return config;
                }
                config.shm_name = next();
                if (config.err != StartupError::OK)
                {
                    return config;
                }
                shmFlag = true;
            }
            else if (equals_ignore_case(arg, "--slots"))
            {
                if (slotsFlag)
                {
                    std::fprintf(stderr, "[ERROR]: --slots flag already set.\n");
                    config.err = StartupError::UnknownArgument;
                    return config;
                }

                const auto& slotsArg = next();
                if (config.err != StartupError::OK)
                {
                    return config;
                }

                config.err = StartupError::InvalidSlotsValue;

                const auto slotsOpt = parseNumFromString<std::uint32_t>(slotsArg.c_str(), strlen(slotsArg.c_str()), "slots");
                if (!slotsOpt)
                {
                    return config;
                }

                const std::uint32_t slots = *slotsOpt;
                if (slots == 0 || ((slots - 1) & slots))
                {
                    std::fprintf(stderr, "[ERROR]: Slots value is zero or not power of 2: %s.\n", slotsArg.c_str());
                    return config;
                }

                config.slots = slots;
                config.err = StartupError::OK;
                slotsFlag = true;
            }
            else if (equals_ignore_case(arg, "--local-ip"))
            {
                parseIpArg(localIpFlag, config, "local-ip", config.local_ip, next);
                if (config.err != StartupError::OK)
                {
                    return config;
                }
            }
            else if (equals_ignore_case(arg, "--peer-ip"))
            {
                parseIpArg(peerIpFlag, config, "peer-ip", config.peer_ip, next);
                if (config.err != StartupError::OK)
                {
                    return config;
                }
            }
            else if (equals_ignore_case(arg, "--data-port"))
            {
                parsePortArg(dataPortFlag, config, "data-port", config.data_port, next);
                if (config.err != StartupError::OK)
                {
                    return config;
                }
            }
            else if (equals_ignore_case(arg, "--control-port"))
            {
                parsePortArg(controlPortFlag, config, "control-port", config.control_port, next);
                if (config.err != StartupError::OK)
                {
                    return config;
                }
            }
            else if (equals_ignore_case(arg, "--observability"))
            {
                if (observabilityFlag)
                {
                    std::fprintf(stderr, "[ERROR]: --observability flag already set.\n");
                    config.err = StartupError::UnknownArgument;
                    return config;
                }

                const auto& observabilityArg = next();
                if (config.err != StartupError::OK)
                {
                    return config;
                }

                if (equals_ignore_case(observabilityArg, "minimal", true))
                {
                    config.observability = ObservabilityMode::Minimal;
                }
                else if (equals_ignore_case(observabilityArg, "performance", true))
                {
                    config.observability = ObservabilityMode::Performance;
                }
                else if (equals_ignore_case(observabilityArg, "diagnostic", true))
                {
                    config.observability = ObservabilityMode::Diagnostic;
                }
                else
                {
                    std::fprintf(stderr, "[ERROR]: Invalid observability mode: %s.\n", observabilityArg.c_str());
                    config.err = StartupError::InvalidObservabilityMode;
                    return config;
                }

                observabilityFlag = true;
            }
            else
            {
                std::fprintf(stderr, "[ERROR]: Unknown argument: %s.\n", arg);
                config.err = StartupError::UnknownArgument;
                return config;
            }
        }

        if (!shmFlag || !slotsFlag || !localIpFlag || !peerIpFlag || !dataPortFlag || !controlPortFlag || !observabilityFlag)
        {
            std::fprintf(stderr, "[ERROR]: Usage: ./executable"
                                 "--shm <name>\n"
                                 "--slots <N>\n"
                                 "--local-ip <IPv4>\n"
                                 "--peer-ip <IPv4>\n"
                                 "--data-port <port>\n"
                                 "--control-port <port>\n"
                                 "--observability minimal|performance|diagnostic\n");
            config.err = StartupError::MissingValue;
            return config;
        }

        if (config.data_port == config.control_port)
        {
            std::fprintf(stderr, "[ERROR]: Data-port == control-port.\n");
            config.err = StartupError::InvalidPort;
        }

        return config;
    }
}