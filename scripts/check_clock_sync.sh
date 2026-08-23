#!/usr/bin/env bash
set -euo pipefail

if [[ $# -gt 1 ]]; then
    echo "Usage: $0 [master-management-ip]" >&2
    exit 1
fi

MASTER_IP="${1:-}"

MAX_CORRECTION="${LLDT_CLOCK_MAX_CORRECTION:-0.000200}"
MAX_SKEW_PPM="${LLDT_CLOCK_MAX_SKEW_PPM:-5}"


if [[ -z "${MASTER_IP}" ]]; then
    # -------------------------------------------------------------------------
    # Clock master.
    #
    # The master intentionally runs chrony in local-reference mode. It is not
    # synchronized to another NTP source, so chronyc waitsync is not applicable.
    # -------------------------------------------------------------------------

    TRACKING="$(chronyc tracking)"

    if ! grep -q '7F7F0101' <<< "${TRACKING}"; then
        echo "ERROR: chrony is not using the expected local reference clock." >&2
        echo "${TRACKING}" >&2
        exit 1
    fi

    echo "=== tracking ==="
    echo "${TRACKING}"

    echo
    echo "=== sources ==="
    chronyc sources -n -v

    echo
    echo "=== source statistics ==="
    chronyc sourcestats -n -v

    exit 0
fi


# -----------------------------------------------------------------------------
# Clock client.
#
# The client must be synchronized to the benchmark master closely enough for
# cross-host one-way latency measurements.
# -----------------------------------------------------------------------------

chronyc waitsync \
    120 \
    "${MAX_CORRECTION}" \
    "${MAX_SKEW_PPM}" \
    0.5

echo "=== tracking ==="
chronyc tracking

echo
echo "=== sources ==="
chronyc sources -n -v

echo
echo "=== source statistics ==="
chronyc sourcestats -n -v

echo
echo "=== master NTP data ==="
chronyc ntpdata "${MASTER_IP}"