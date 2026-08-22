#!/usr/bin/env bash
set -euo pipefail

if [[ $# -gt 1 ]]; then
    echo "Usage: $0 [master-management-ip]" >&2
    exit 1
fi

MASTER_IP="${1:-}"

MAX_CORRECTION="${LLDT_CLOCK_MAX_CORRECTION:-0.000200}"
MAX_SKEW_PPM="${LLDT_CLOCK_MAX_SKEW_PPM:-5}"

chronyc waitsync \
    120 \
    "${MAX_CORRECTION}" \
    "${MAX_SKEW_PPM}" \
    0.5

echo "=== tracking ==="
chronyc tracking

echo
echo "=== sources ==="
chronyc sources -v

echo
echo "=== source statistics ==="
chronyc sourcestats -v

if [[ -n "${MASTER_IP}" ]]; then
    echo
    echo "=== master NTP data ==="
    chronyc ntpdata "${MASTER_IP}"
fi