#!/bin/bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"
CODEC="raw"

if [[ $# -eq 1 ]]; then
  if [[ $1 == "--compact" ]]; then
    CODEC="compact"
  else
    echo "ERROR: unknown flag"
    exit 1
  fi
elif [[ $# -gt 1 ]]; then
  echo "ERROR: Usage: ./build.sh [--compact]"
  exit 1
fi

export CC="${CC:-gcc}"
export CXX="${CXX:-g++}"

bash "${SCRIPT_DIR}/build_dpdk.sh"

BUILD_DIR="${ROOT}/build/lldt_release"

cmake \
    -S "${ROOT}" \
    -B "${BUILD_DIR}" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_TESTING=OFF \
    -DCMAKE_CXX_COMPILER="${CXX}" \
    -DCMAKE_CXX_FLAGS="-march=native" \
    -DLLDT_MESSAGE_PROFILE="${CODEC}" \
    -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON

cmake --build "${BUILD_DIR}" --target lldt_sender lldt_receiver