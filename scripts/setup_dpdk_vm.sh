#!/usr/bin/env bash
set -euo pipefail

DATAPATH_IF="${1}"
DATAPATH_BDF="${2}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ISOLATED_CORES="2,4"
HOUSEKEEPING_CORES="0,6"

# -----------------------------------------------------------------------------
# Persistent boot configuration.
#
# nosmt=force:
#   leave one logical CPU per physical core.
#
# isolcpus:
#   keep normal scheduler work and managed IRQs away from latency-critical CPUs.
#
# nohz_full:
#   remove periodic scheduler tick from critical CPUs.
#
# rcu_nocbs:
#   move RCU callbacks away from critical CPUs.
#
# irqaffinity:
#   direct normal IRQs to housekeeping CPUs.
#
# hugepages:
#   reserve 512 * 2 MiB = 1 GiB at boot.
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
# Do not allow irqbalance to undo our IRQ placement.
# -----------------------------------------------------------------------------

systemctl disable --now irqbalance 2>/dev/null || true


# -----------------------------------------------------------------------------
# DPDK / VFIO.
# -----------------------------------------------------------------------------

modprobe vfio-pci
echo 1 > /sys/module/vfio/parameters/enable_unsafe_noiommu_mode

ip addr flush dev "${DATAPATH_IF}"
ip link set "${DATAPATH_IF}" down

dpdk-devbind.py --bind=vfio-pci "${DATAPATH_BDF}"


# -----------------------------------------------------------------------------
# Hugepage filesystem.
# Hugepages themselves are reserved at boot.
# -----------------------------------------------------------------------------

mkdir -p /dev/hugepages

mountpoint -q /dev/hugepages ||
    mount -t hugetlbfs -o pagesize=2M nodev /dev/hugepages


# -----------------------------------------------------------------------------
# Final CPU preflight.
# -----------------------------------------------------------------------------

"${SCRIPT_DIR}/check_cores.sh" 2 4