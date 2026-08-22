#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 0 ]]; then
    echo "Usage: sudo $0" >&2
    exit 1
fi

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: setup_dpdk_vm.sh must be run as root." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

DPDK_VERSION="25.11.2"
DPDK_DEVBIND="${ROOT}/build/dependencies/dpdk-${DPDK_VERSION}/install/bin/dpdk-devbind.py"

ISOLATED_CORES="2,4"
HOUSEKEEPING_CORES="0,6"


pci_bdf_from_netdev()
{
    local path
    local component

    path="$(readlink -f "/sys/class/net/$1/device")" || return 1

    while [[ "${path}" != "/" && -n "${path}" ]]; do
        component="${path##*/}"

        if [[ "${component}" =~ ^[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-7]$ ]]; then
            printf '%s\n' "${component}"
            return 0
        fi

        path="${path%/*}"
        [[ -n "${path}" ]] || path="/"
    done

    return 1
}


find_management_interface()
{
    ip -4 route show default |
        awk '
        {
            dev = ""
            metric = 0

            for (i = 1; i <= NF; ++i) {
                if ($i == "dev")
                    dev = $(i + 1)
                else if ($i == "metric")
                    metric = $(i + 1)
            }

            if (dev != "")
                print metric, dev
        }' |
        sort -n |
        head -n 1 |
        awk '{print $2}'
}


MANAGEMENT_IF="$(find_management_interface)"

if [[ -z "${MANAGEMENT_IF}" ]]; then
    echo "ERROR: could not determine management interface." >&2
    exit 1
fi

MANAGEMENT_BDF="$(pci_bdf_from_netdev "${MANAGEMENT_IF}")" || {
    echo "ERROR: could not determine PCI BDF for management interface ${MANAGEMENT_IF}." >&2
    exit 1
}


DATAPATH_CANDIDATES=()

for device in /sys/bus/pci/devices/*; do
    [[ -r "${device}/class" ]] || continue
    [[ "$(<"${device}/class")" == "0x020000" ]] || continue

    bdf="${device##*/}"

    if [[ "${bdf}" != "${MANAGEMENT_BDF}" ]]; then
        DATAPATH_CANDIDATES+=("${bdf}")
    fi
done

if [[ ${#DATAPATH_CANDIDATES[@]} -ne 1 ]]; then
    echo "ERROR: expected exactly one datapath Ethernet PCI device, found ${#DATAPATH_CANDIDATES[@]}." >&2
    exit 1
fi

DATAPATH_BDF="${DATAPATH_CANDIDATES[0]}"
DATAPATH_IF=""

for netdev in /sys/class/net/*; do
    ifname="${netdev##*/}"

    [[ "${ifname}" == "lo" ]] && continue

    if bdf="$(pci_bdf_from_netdev "${ifname}" 2>/dev/null)"; then
        if [[ "${bdf}" == "${DATAPATH_BDF}" ]]; then
            DATAPATH_IF="${ifname}"
            break
        fi
    fi
done

echo "Management NIC: ${MANAGEMENT_IF} (${MANAGEMENT_BDF})"
if [[ -n "${DATAPATH_IF}" ]]; then
    echo "Datapath NIC:   ${DATAPATH_IF} (${DATAPATH_BDF})"
else
    echo "Datapath NIC:   ${DATAPATH_BDF} (no kernel netdev)"
fi


# -----------------------------------------------------------------------------
# Persistent boot configuration.
# -----------------------------------------------------------------------------

mkdir -p /etc/default/grub.d

cat > /etc/default/grub.d/99-lldt.cfg <<EOF
GRUB_CMDLINE_LINUX_DEFAULT="\${GRUB_CMDLINE_LINUX_DEFAULT} nosmt=force isolcpus=domain,managed_irq,${ISOLATED_CORES} nohz_full=${ISOLATED_CORES} rcu_nocbs=${ISOLATED_CORES} irqaffinity=${HOUSEKEEPING_CORES} hugepagesz=2M hugepages=512"
EOF

CMDLINE="$(cat /proc/cmdline)"

if [[ "${CMDLINE}" != *"isolcpus=domain,managed_irq,${ISOLATED_CORES}"* ||
      "${CMDLINE}" != *"nohz_full=${ISOLATED_CORES}"* ||
      "${CMDLINE}" != *"rcu_nocbs=${ISOLATED_CORES}"* ||
      "${CMDLINE}" != *"nosmt=force"* ]]; then

    update-grub

    echo
    echo "Kernel isolation configuration installed."
    echo "Reboot the VM, then run this script again."
    exit 0
fi


# -----------------------------------------------------------------------------
# Keep IRQ placement stable.
# -----------------------------------------------------------------------------

systemctl disable --now irqbalance 2>/dev/null || true


# -----------------------------------------------------------------------------
# DPDK / VFIO.
# -----------------------------------------------------------------------------

if [[ ! -x "${DPDK_DEVBIND}" ]]; then
    echo "ERROR: ${DPDK_DEVBIND} not found. Build DPDK first." >&2
    exit 1
fi

modprobe vfio-pci
echo 1 > /sys/module/vfio/parameters/enable_unsafe_noiommu_mode

if [[ -n "${DATAPATH_IF}" ]]; then
    ip addr flush dev "${DATAPATH_IF}"
    ip link set "${DATAPATH_IF}" down
fi

"${DPDK_DEVBIND}" --bind=vfio-pci "${DATAPATH_BDF}"


# -----------------------------------------------------------------------------
# Hugepage filesystem.
# -----------------------------------------------------------------------------

mkdir -p /dev/hugepages

mountpoint -q /dev/hugepages ||
    mount -t hugetlbfs -o pagesize=2M nodev /dev/hugepages


# -----------------------------------------------------------------------------
# Final CPU preflight.
# -----------------------------------------------------------------------------

"${SCRIPT_DIR}/check_cores.sh" 2 4