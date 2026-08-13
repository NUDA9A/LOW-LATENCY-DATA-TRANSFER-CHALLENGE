#include <lldt/config.hpp>
#include <lldt/dpdk/ena_port_info.hpp>


#include <rte_eal.h>
#include <rte_errno.h>

#include <cstdio>

using SenderConfig = transport::EndpointConfig;

namespace
{
    int run_sender(const int argc, char* argv[])
    {
        const SenderConfig config = transport::parse_endpoint_config(argc, argv);
        if (config.err != transport::StartupError::OK)
        {
            return 1;
        }

        const auto ena_port_info = dpdk::try_get_ena_port_info();
        if (!ena_port_info)
        {
            return 1;
        }

        return 0;
    }
}

int main(int argc, char* argv[])
{
    int eal_argc{};
    if (eal_argc = rte_eal_init(argc, argv); eal_argc < 0)
    {
        std::fprintf(stderr, "ERROR: EAL init failed: %s\n", rte_strerror(rte_errno));
        return 1;
    }

    argc -= eal_argc;
    argv += eal_argc;

    const int sender_result = run_sender(argc, argv);
    const int cleanup_result = rte_eal_cleanup();

    if (sender_result)
    {
        std::fprintf(stderr, "ERROR: Could not retrieve ENA-port info\n");
        return 1;
    }

    if (cleanup_result)
    {
        std::fprintf(stderr, "ERROR: Could not cleanup EAL\n");
        return 1;
    }

    return 0;
}