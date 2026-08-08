#include <lldt/config.hpp>

using SenderConfig = transport::EndpointConfig;

int main(const int argc, const char* argv[])
{
    const SenderConfig config = transport::parse_endpoint_config(argc, argv);
    if (config.err != transport::StartupError::OK)
    {
        return 1;
    }

    return 0;
}