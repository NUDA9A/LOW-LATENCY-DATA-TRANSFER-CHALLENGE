#!/usr/bin/env bash
set -euo pipefail

usage()
{
    echo "Usage:" >&2
    echo "  sudo $0 master" >&2
    echo "  sudo $0 client <master-management-ip>" >&2
    exit 1
}

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: must be run as root." >&2
    exit 1
fi

ROLE="${1:-}"

if [[ "${ROLE}" == "master" ]]; then
    [[ $# -eq 1 ]] || usage
elif [[ "${ROLE}" == "client" ]]; then
    [[ $# -eq 2 ]] || usage
    MASTER_IP="$2"
else
    usage
fi


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

MANAGEMENT_CIDR="$(
    ip -4 -o addr show dev "${MANAGEMENT_IF}" scope global |
        awk 'NR == 1 { print $4 }'
)"

if [[ -z "${MANAGEMENT_CIDR}" ]]; then
    echo "ERROR: no IPv4 address on ${MANAGEMENT_IF}." >&2
    exit 1
fi

MANAGEMENT_IP="${MANAGEMENT_CIDR%/*}"

MANAGEMENT_NETWORK="$(
    python3 - "${MANAGEMENT_CIDR}" <<'PY'
import ipaddress
import sys

print(ipaddress.ip_interface(sys.argv[1]).network)
PY
)"


if ! command -v chronyd >/dev/null 2>&1; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y chrony
fi

systemctl disable --now systemd-timesyncd.service 2>/dev/null || true

mkdir -p /etc/chrony

if [[ -f /etc/chrony/chrony.conf &&
      ! -f /etc/chrony/chrony.conf.lldt-backup ]]; then
    cp /etc/chrony/chrony.conf \
       /etc/chrony/chrony.conf.lldt-backup
fi


if [[ "${ROLE}" == "master" ]]; then

    cat > /etc/chrony/chrony.conf <<EOF
driftfile /var/lib/chrony/chrony.drift
rtcsync

# LLDT benchmark clock master.
# Absolute UTC accuracy is not required; receivers synchronize to this clock.
local stratum 10

# Serve NTP only through the management network.
bindaddress ${MANAGEMENT_IP}
allow ${MANAGEMENT_NETWORK}

logdir /var/log/chrony
EOF

else

    cat > /etc/chrony/chrony.conf <<EOF
# LLDT benchmark clock client.
# Use exactly one benchmark master so every receiver shares the Sender clock.
server ${MASTER_IP} iburst minpoll -4 maxpoll -4 xleave filter 15

driftfile /var/lib/chrony/chrony.drift

# Initial synchronization may step the clock.
# After the initial updates chronyd returns to normal slew-only correction.
makestep 0.001 20

rtcsync
logdir /var/log/chrony
EOF

fi


systemctl enable chrony
systemctl restart chrony

if [[ "${ROLE}" == "client" ]]; then
    chronyc waitsync 120 0 0 0.5
fi

echo
echo "role:               ${ROLE}"
echo "management iface:   ${MANAGEMENT_IF}"
echo "management address: ${MANAGEMENT_IP}"
echo

chronyc tracking
echo
chronyc sources -v