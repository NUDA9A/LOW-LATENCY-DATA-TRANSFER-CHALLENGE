#pragma once

// Я вынес SendStatus и SendResult в отдельный хеддер, потому что мне кажется что DPDK-бэкенд сможет ис
namespace transport
{
    enum class SendStatus
    {
        Sent, Transient, HardError
    };

    struct SendResult
    {
        SendStatus status = SendStatus::HardError;
        int error_number = 0;
    };
}