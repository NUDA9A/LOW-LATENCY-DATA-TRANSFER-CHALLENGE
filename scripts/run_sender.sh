#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 3 || $# -gt 4 ]]; then
    echo "Usage: $0 <local-ip> <peer-ip> <peer-mac> [--batching]" >&2
    exit 1
fi

LOCAL_IP="$1"
PEER_IP="$2"
PEER_MAC="$3"

BATCHING_ARGS=()
if [[ $# -eq 4 ]]; then
    if [[ "$4" != "--batching" ]]; then
        echo "ERROR: unknown argument: $4" >&2
        exit 1
    fi

    BATCHING_ARGS+=(--batching)
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

BINARY="${ROOT}/build/lldt_release/lldt_sender"

CORE="${LLDT_CORE:-4}"
SHM="${LLDT_SHM:-/fanout_ring}"
SLOTS="${LLDT_SLOTS:-1024}"
DATA_PORT="${LLDT_DATA_PORT:-9000}"

find_dpdk_bdf()
{
    local candidates=()
    local device
    local driver

    for device in /sys/bus/pci/devices/*; do
        [[ -r "${device}/class" ]] || continue
        [[ "$(<"${device}/class")" == "0x020000" ]] || continue
        [[ -L "${device}/driver" ]] || continue

        driver="$(basename "$(readlink -f "${device}/driver")")"

        if [[ "${driver}" == "vfio-pci" ]]; then
            candidates+=("${device##*/}")
        fi
    done

    if [[ ${#candidates[@]} -ne 1 ]]; then
        echo "ERROR: expected exactly one Ethernet device bound to vfio-pci, found ${#candidates[@]}." >&2
        exit 1
    fi

    printf '%s\n' "${candidates[0]}"
}

DPDK_BDF="$(find_dpdk_bdf)"

exec sudo "${BINARY}" \
    -l "${CORE}" \
    -a "${DPDK_BDF}" \
    -- \
    --shm "${SHM}" \
    --slots "${SLOTS}" \
    --local-ip "${LOCAL_IP}" \
    --peer-ip "${PEER_IP}" \
    --data-port "${DATA_PORT}" \
    --next-hop-mac "${PEER_MAC}" \
    "${BATCHING_ARGS[@]}"