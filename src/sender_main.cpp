#include <lldt/config.hpp>


#include <rte_eal.h>
#include <rte_errno.h>

#include <cstdio>

using SenderConfig = transport::EndpointConfig;


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

    const SenderConfig config = transport::parse_endpoint_config(argc, argv);
    if (config.err != transport::StartupError::OK)
    {
        rte_eal_cleanup();
        return 1;
    }

    if (rte_eal_cleanup() != 0)
    {
        std::fprintf(stderr, "ERROR: EAL cleanup fa\n");
        return 2;
    }

    return 0;
}