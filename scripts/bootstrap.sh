#!/bin/bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"

if [ "$(uname -m)" != "x86_64" ]; then
    echo "ERROR: x86_64 architecture is required." >&2
    exit 1
fi

source /etc/os-release

if [[ $ID != "ubuntu" || ($VERSION_ID != 20.04 && $VERSION_ID != 22.04 && $VERSION_ID != 24.04) ]]; then
    echo "ERROR: Ubuntu 20.04/22.04/24.04 is required." >&2
    exit 1
fi

if [ "$EUID" -eq 0 ]; then
    echo "ERROR: script must be run as a non-root user." >&2
    exit 1
fi

sudo -v

sudo apt-get update
sudo apt-get install --no-install-recommends -y build-essential cmake pkg-config ninja-build python3 python3-venv curl ca-certificates xz-utils libnuma-dev

WHEELS_DIR="${ROOT}/build/tools/wheels"

mkdir -p "${WHEELS_DIR}"

VENV="${ROOT}/build/tools/venv"

if [ ! -x "${VENV}/bin/python" ]; then
    python3 -m venv "${VENV}"
fi

"${VENV}/bin/python" --version
"${VENV}/bin/python" -m pip --version

MESON_FILENAME="meson-1.8.5-py3-none-any.whl"
MESON_URL="https://files.pythonhosted.org/packages/22/a3/9b9ca250146b2eace017d7931cabb44a65c04b79f6f046d74e9c94bd5da3/meson-1.8.5-py3-none-any.whl"
MESON_CHECKSUM="15ab2cca08271bc055bc33a4929b7c58f15ad67df4c1fa65dc223e822b882bef"

PYELFTOOLS_FILENAME="pyelftools-0.32-py3-none-any.whl"
PYELFTOOLS_URL="https://files.pythonhosted.org/packages/af/43/700932c4f0638c3421177144a2e86448c0d75dbaee2c7936bda3f9fd0878/pyelftools-0.32-py3-none-any.whl"
PYELFTOOLS_CHECKSUM="013df952a006db5e138b1edf6d8a68ecc50630adbd0d83a2d41e7f846163d738"


download_verified_wheel() {
  local filename="$1"
  local url="$2"
  local expected_checksum="$3"
  local result_path="${WHEELS_DIR}/${filename}"
  local hash
  local tmp_file
  if [[ -f "${result_path}" ]]; then
      hash=$(sha256sum "${result_path}" | awk '{print $1}')
      if [[ $hash == $expected_checksum ]]; then
          return 0
      fi

      rm -f -- "${result_path}"
  fi

  tmp_file=$(mktemp "${WHEELS_DIR}/tmp_file.XXXXXX")
  if ! curl --fail --location --retry 5 -o "${tmp_file}" "${url}"; then
      rm -f -- "${tmp_file}"
      echo "ERROR: Curl error." >&2
      return 1
  fi

  hash=$(sha256sum "${tmp_file}" | awk '{print $1}')
  if [[ "${hash}" != "${expected_checksum}" ]]; then
      rm -f -- "${tmp_file}"
      echo "ERROR: Can not download correct ${filename}." >&2
      return 1
  fi

  mv -- "${tmp_file}" "${result_path}"
}

download_verified_wheel "${MESON_FILENAME}" "${MESON_URL}" "${MESON_CHECKSUM}"
download_verified_wheel "${PYELFTOOLS_FILENAME}" "${PYELFTOOLS_URL}" "${PYELFTOOLS_CHECKSUM}"

"${VENV}/bin/python" -m pip install --disable-pip-version-check --no-index --no-deps "${WHEELS_DIR}/${MESON_FILENAME}" "${WHEELS_DIR}/${PYELFTOOLS_FILENAME}"

MESON_VERSION="$("${VENV}/bin/meson" --version)"
if [[ "${MESON_VERSION}" != "1.8.5" ]]; then
    echo "ERROR: Meson version 1.8.5 is required. Current is ${MESON_VERSION}" >&2
    exit 2
fi

PYELFTOOLS_VERSION="$("${VENV}/bin/python" -c 'import elftools; print(elftools.__version__)')"
if [[ "${PYELFTOOLS_VERSION}" != "0.32" ]]; then
    echo "ERROR: Pyelftools version 0.32 is required. Current is ${PYELFTOOLS_VERSION}" >&2
    exit 2
fi