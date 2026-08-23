#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: launch_benchmark_node.sh must run as root." >&2
    exit 1
fi

ROLE=""
RUN_ID=""

args=("$@")

for ((i = 0; i < ${#args[@]}; ++i)); do
    case "${args[i]}" in
        --role)
            (( i + 1 < ${#args[@]} )) || exit 2
            ROLE="${args[i + 1]}"
            ;;
        --run-id)
            (( i + 1 < ${#args[@]} )) || exit 2
            RUN_ID="${args[i + 1]}"
            ;;
    esac
done

[[ "${ROLE}" == "sender" || "${ROLE}" == "receiver" ]] || {
    echo "ERROR: --role sender|receiver is required." >&2
    exit 2
}

[[ -n "${RUN_ID}" && "${RUN_ID}" =~ ^[A-Za-z0-9._-]+$ ]] || {
    echo "ERROR: valid --run-id is required." >&2
    exit 2
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNIT="lldt-bench-${ROLE}-${RUN_ID}"

if systemctl is-active --quiet "${UNIT}.service"; then
    echo "ERROR: ${UNIT}.service is already active." >&2
    exit 1
fi

exec systemd-run \
    --unit="${UNIT}" \
    --description="LLDT benchmark ${ROLE} ${RUN_ID}" \
    --collect \
    --property=Type=exec \
    --property=KillMode=control-group \
    --property=TimeoutStopSec=15s \
    "${SCRIPT_DIR}/benchmark_node.sh" \
    "$@"
