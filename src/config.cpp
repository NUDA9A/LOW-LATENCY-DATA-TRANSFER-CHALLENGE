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
std::optional<T> parseNumFromString(const char* str, const std::size_t size, const std::string& name, int base = 10)
{
    T res{};

    auto [ptr, ec] = std::from_chars(str, str + size, res, base);
    if (ec != std::errc() || ptr != str + size)
    {
        std::fprintf(stderr, "[ERROR]: Invalid %s: %s.\n", name.c_str(), str);
        return std::nullopt;
    }

    return res;
}

static bool parseIpArg(
    bool& ipFlag,
    const std::string& flagName,
    std::uint32_t& ipMember,
    const std::function<std::optional<std::string>()>& next)
{
    if (ipFlag)
    {
        std::fprintf(stderr, "[ERROR]: --%s flag already set.\n", flagName.c_str());
        return false;
    }

    const auto& ipArgOpt = next();
    if (!ipArgOpt)
    {
        return false;
    }

    in_addr ip_binary{};

    if (inet_pton(AF_INET, ipArgOpt->c_str(), &ip_binary) != 1)
    {
        std::fprintf(stderr, "[ERROR]: Invalid %s address.\n", flagName.c_str());
        return false;
    }

    ipMember = ip_binary.s_addr;

    ipFlag = true;

    return true;
}

static bool parsePortArg(
    bool& portFlag,
    const std::string& flagName,
    std::uint16_t& portMember,
    const std::function<std::optional<std::string>()>& next)
{
    if (portFlag)
    {
        std::fprintf(stderr, "[ERROR]: --%s flag already set.\n", flagName.c_str());
        return false;
    }

    const auto& portArgOpt = next();
    if (!portArgOpt)
    {
        return false;
    }

    const auto portOpt = parseNumFromString<std::uint16_t>(portArgOpt->c_str(), portArgOpt->size(), flagName.c_str());
    if (!portOpt)
    {
        return false;
    }

    const std::uint16_t port = *portOpt;
    if (port == 0)
    {
        std::fprintf(stderr, "[ERROR]: %s value is zero: %s.\n", flagName.c_str(), portArgOpt->c_str());
        return false;
    }

    portMember = port;

    portFlag = true;

    return true;
}

namespace transport
{
    std::optional<EndpointConfig> try_parse_endpoint_config(const int argc, const char* const argv[])
    {
        EndpointConfig config{};

        bool shmFlag = false;
        bool slotsFlag = false;
        bool localIpFlag = false;
        bool peerIpFlag = false;
        bool dataPortFlag = false;
        bool controlPortFlag = false;
        bool nextHopMacFlag = false;
        bool observabilityFlag = false;

        for (int i = 1; i < argc; ++i)
        {
            const auto arg = argv[i];

            auto next = [&]() -> std::optional<std::string> {
                if (i + 1 >= argc || (strlen(argv[i + 1]) > 1 && argv[i + 1][0] == '-' && argv[i + 1][1] == '-')) {
                    std::fprintf(stderr, "[ERROR]: Usage: ./executable\n"
                                "<EAL args>\n"
                                "--\n"
                                "--shm <name>\n"
                                "--slots <N>\n"
                                "--local-ip <IPv4>\n"
                                "--peer-ip <IPv4>\n"
                                "--data-port <port>\n"
                                "--control-port <port>\n"
                                "--next-hop-mac <xx:xx:xx:xx:xx:xx>\n"
                                "--observability minimal|performance|diagnostic\n");
                    return std::nullopt;
                }
                return argv[++i];
            };

            if (equals_ignore_case(arg, "--shm"))
            {
                if (shmFlag)
                {
                    std::fprintf(stderr, "[ERROR]: --shm flag already set.\n");
                    return std::nullopt;
                }
                const auto shmNameOpt = next();
                if (!shmNameOpt)
                {
                    return std::nullopt;
                }
                config.shm_name = *shmNameOpt;
                shmFlag = true;
            }
            else if (equals_ignore_case(arg, "--slots"))
            {
                if (slotsFlag)
                {
                    std::fprintf(stderr, "[ERROR]: --slots flag already set.\n");
                    return std::nullopt;
                }

                const auto slotsArgOpt = next();
                if (!slotsArgOpt)
                {
                    return std::nullopt;
                }

                const auto slotsOpt = parseNumFromString<std::uint32_t>(slotsArgOpt->c_str(), slotsArgOpt->size(), "slots");
                if (!slotsOpt)
                {
                    return std::nullopt;
                }

                const std::uint32_t slots = *slotsOpt;
                if (slots == 0 || ((slots - 1) & slots))
                {
                    std::fprintf(stderr, "[ERROR]: Slots value is zero or not power of 2: %s.\n", slotsArgOpt->c_str());
                    return std::nullopt;
                }

                config.slots = slots;
                slotsFlag = true;
            }
            else if (equals_ignore_case(arg, "--local-ip"))
            {
                if (!parseIpArg(localIpFlag, "local-ip", config.local_ipv4_be, next))
                {
                    return std::nullopt;
                }
            }
            else if (equals_ignore_case(arg, "--peer-ip"))
            {
                if (!parseIpArg(peerIpFlag, "peer-ip", config.peer_ipv4_be, next))
                {
                    return std::nullopt;
                }

            }
            else if (equals_ignore_case(arg, "--data-port"))
            {
                if (!parsePortArg(dataPortFlag, "data-port", config.data_port, next))
                {
                    return std::nullopt;
                }
            }
            else if (equals_ignore_case(arg, "--control-port"))
            {
                if (!parsePortArg(controlPortFlag, "control-port", config.control_port, next))
                {
                    return std::nullopt;
                }
            }
            else if (equals_ignore_case(arg, "--observability"))
            {
                if (observabilityFlag)
                {
                    std::fprintf(stderr, "[ERROR]: --observability flag already set.\n");
                    return std::nullopt;
                }

                const auto observabilityArgOpt = next();
                if (!observabilityArgOpt)
                {
                    return std::nullopt;
                }

                if (equals_ignore_case(*observabilityArgOpt, "minimal", true))
                {
                    config.observability = ObservabilityMode::Minimal;
                }
                else if (equals_ignore_case(*observabilityArgOpt, "performance", true))
                {
                    config.observability = ObservabilityMode::Performance;
                }
                else if (equals_ignore_case(*observabilityArgOpt, "diagnostic", true))
                {
                    config.observability = ObservabilityMode::Diagnostic;
                }
                else
                {
                    std::fprintf(stderr, "[ERROR]: Invalid observability mode: %s.\n", observabilityArgOpt->c_str());
                    return std::nullopt;
                }

                observabilityFlag = true;
            }
            else if (equals_ignore_case(arg, "--next-hop-mac"))
            {
                if (nextHopMacFlag)
                {
                    std::fprintf(stderr, "[ERROR]: --next-hop-mac flag already set.\n");
                    return std::nullopt;
                }

                const auto nextHopMacArgOpt = next();
                if (!nextHopMacArgOpt)
                {
                    return std::nullopt;
                }

                const auto& nextHopMac = *nextHopMacArgOpt;

                if (nextHopMac.size() != 17) // 6 * 2 octets + 5 ':' = 17
                {
                    std::fprintf(stderr, "[ERROR]: Invalid next-hop-mac argument: %s.\n", nextHopMac.c_str());
                    return std::nullopt;
                }

                std::size_t zeroOctetsCount = 0;
                for (std::size_t octet_idx = 0; octet_idx < 6; ++octet_idx)
                {
                    if (octet_idx < 5 && nextHopMac[octet_idx * 3 + 2] != ':')
                    {
                        std::fprintf(stderr, "[ERROR]: Invalid next-hop-mac argument: %s.\n", nextHopMac.c_str());
                        return std::nullopt;
                    }

                    const auto octetOpt = parseNumFromString<std::uint8_t>(
                        nextHopMac.substr(octet_idx * 3, 2).c_str(),
                        2,
                        "next-hop-mac",
                        16
                    );

                    if (!octetOpt)
                    {
                        return std::nullopt;
                    }

                    config.next_hop_mac[octet_idx] = *octetOpt;

                    if (config.next_hop_mac[octet_idx] == 0)
                    {
                        zeroOctetsCount++;
                    }
                }

                if (zeroOctetsCount == 6)
                {
                    std::fprintf(stderr, "[ERROR]: Zero MAC is not supported\n");
                    return std::nullopt;
                }

                if ((config.next_hop_mac[0] & 0x01u) != 0)
                {
                    std::fprintf(stderr, "[ERROR]: Multicast MAC is not supported.\n");
                    return std::nullopt;
                }

                nextHopMacFlag = true;
            }
            else
            {
                std::fprintf(stderr, "[ERROR]: Unknown argument: %s.\n", arg);
                return std::nullopt;
            }
        }

        if (!shmFlag || !slotsFlag || !localIpFlag || !peerIpFlag || !dataPortFlag || !controlPortFlag || !nextHopMacFlag || !observabilityFlag)
        {
            std::fprintf(stderr, "[ERROR]: Usage: ./executable\n"
                                "<EAL args>\n"
                                "--\n"
                                "--shm <name>\n"
                                "--slots <N>\n"
                                "--local-ip <IPv4>\n"
                                "--peer-ip <IPv4>\n"
                                "--data-port <port>\n"
                                "--control-port <port>\n"
                                "--next-hop-mac <xx:xx:xx:xx:xx:xx>\n"
                                "--observability minimal|performance|diagnostic\n");
            return std::nullopt;
        }

        if (config.data_port == config.control_port)
        {
            std::fprintf(stderr, "[ERROR]: Data-port == control-port.\n");
            return std::nullopt;
        }

        return config;
    }
}