#!/bin/bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"

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
    -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON

cmake --build "${BUILD_DIR}" --target lldt_sender