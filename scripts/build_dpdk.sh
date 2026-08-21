#!/bin/bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"

if [ "$EUID" -eq 0 ]; then
    echo "ERROR: script must be run as a non-root user." >&2
    exit 1
fi

bash "${SCRIPT_DIR}/bootstrap.sh"

DOWNLOADS="${ROOT}/build/downloads"

mkdir -p "${DOWNLOADS}"

DPDK_VERSION="25.11.2"
URL="https://fast.dpdk.org/rel/dpdk-${DPDK_VERSION}.tar.xz"
CHECKSUM="418bfe3212640ee95a1cb10af6ed360cad2387686fe2721f8a3a9cd02d5ef4f2"

ARCHIVE_PATH="${DOWNLOADS}/dpdk-${DPDK_VERSION}.tar.xz"

NEED_DOWNLOAD=false

if [[ -f "${ARCHIVE_PATH}" ]]; then
    hash=$(sha256sum "${ARCHIVE_PATH}" | awk '{print $1}')
    if [[ "${hash}" != "${CHECKSUM}" ]]; then
        rm -f -- "${ARCHIVE_PATH}"
        NEED_DOWNLOAD=true
    fi
else
    NEED_DOWNLOAD=true
fi

tmp_archive=""

if [[ "${NEED_DOWNLOAD}" == true ]]; then
    tmp_archive=$(mktemp "${DOWNLOADS}/tmp_archive.XXXXXX")

    if ! curl --fail --location --retry 5 -o "${tmp_archive}" "${URL}"; then
        rm -f -- "${tmp_archive}"
        echo "ERROR: Curl error." >&2
        exit 1
    fi

    hash=$(sha256sum "${tmp_archive}" | awk '{print $1}')
    if [[ "${hash}" != "${CHECKSUM}" ]]; then
        rm -f -- "${tmp_archive}"
        echo "ERROR: Can not download dpdk archive." >&2
        exit 2
    fi

    mv -- "${tmp_archive}" "${ARCHIVE_PATH}"
fi

DPDK_DIR="${ROOT}/build/dependencies/dpdk-${DPDK_VERSION}"
SRC_PATH="${DPDK_DIR}/source"
ARCHIVE_ROOT="dpdk-stable-${DPDK_VERSION}"

mkdir -p "${DPDK_DIR}"

NEED_EXTRACT=true

if [[ -d "${SRC_PATH}" ]]; then
    if [[ ! -f "${SRC_PATH}/meson.build" ]]; then
        rm -rf -- "${SRC_PATH}"
    else
        NEED_EXTRACT=false
    fi
fi

if [[ "${NEED_EXTRACT}" == true ]]; then
    tmp_directory=$(mktemp -d -p "${DPDK_DIR}")
    if ! tar xJf "${ARCHIVE_PATH}" -C "${tmp_directory}"; then
        rm -rf -- "${tmp_directory}"
        echo "ERROR: Tar unzip error." >&2
        exit 3
    fi

    if [[ ! -d "${tmp_directory}/${ARCHIVE_ROOT}" || ! -f "${tmp_directory}/${ARCHIVE_ROOT}/meson.build" ]]; then
        rm -rf -- "${tmp_directory}"
        echo "ERROR: Unzip error." >&2
        exit 3
    fi

    mv -- "${tmp_directory}/${ARCHIVE_ROOT}" "${SRC_PATH}"
    rm -rf -- "${tmp_directory}"
fi

MESON="${ROOT}/build/tools/venv/bin/meson"
BUILD_PATH="${DPDK_DIR}/build"
INSTALL_PATH="${DPDK_DIR}/install"
EMPTY_PKGCONFIG_PATH="${DPDK_DIR}/empty-pkgconfig"

mkdir -p "${EMPTY_PKGCONFIG_PATH}"

if [[ ! -f "${BUILD_PATH}/build.ninja" ]]; then
    rm -rf -- "${BUILD_PATH}"

    PKG_CONFIG_PATH="" \
    PKG_CONFIG_LIBDIR="${EMPTY_PKGCONFIG_PATH}" \
    "${MESON}" setup \
    --prefix="${INSTALL_PATH}" \
    --libdir=lib \
    --buildtype=release \
    --default-library=static \
    --wrap-mode=nodownload \
    -Db_lto=true \
    -Dplatform=native \
    -Denable_drivers=net/ena,net/virtio \
    -Denable_libs=timer \
    "-Ddisable_apps=*" \
    -Dtests=false \
    "-Dexamples=" \
    -Denable_docs=false \
    -Denable_trace_fp=false \
    -Ddeveloper_mode=disabled \
    -Dmax_lcores=detect \
    -Dmax_numa_nodes=detect \
    -Denable_iova_as_pa=true \
    -Dmbuf_refcnt_atomic=true \
    -Duse_hpet=false \
     "${BUILD_PATH}" "${SRC_PATH}"
fi

ninja -C "${BUILD_PATH}" install