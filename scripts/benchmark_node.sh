#!/usr/bin/env bash
set -Eeuo pipefail

ROLE=""
RUN_ID=""
PROFILE="raw"
BATCHING="0"
RATE="200000"
SAMPLES="1000000"
MESSAGE_TYPE="mixed"
WARMUP_SECONDS="5"
SLOTS="1024"
DATA_PORT="9000"
SHM_NAME="/fanout_ring"
SENDER_DATA_IP="10.131.0.4"
RECEIVER_DATA_IP="10.131.0.24"
NEXT_HOP_MAC="00:00:5e:00:01:00"
SENDER_MANAGEMENT_IP="10.129.0.17"
MEASUREMENT_TIMEOUT=""
SOURCE_MARGIN_PERCENT="25"
POST_MEASURE_SECONDS="2"
SKIP_BUILD="0"
RESULT_ROOT="/var/tmp/lldt-benchmark"
HOUSEKEEPING_CORES="${LLDT_HOUSEKEEPING_CORES:-0,6}"

usage()
{
    cat >&2 <<USAGE
Usage: sudo $0 --role sender|receiver --run-id ID [options]

Options:
  --profile raw|compact
  --batching 0|1
  --rate N
  --samples N
  --message-type trade|bbo|book|mixed
  --warmup-seconds N
  --slots N
  --data-port N
  --shm NAME
  --sender-data-ip IP
  --receiver-data-ip IP
  --next-hop-mac MAC
  --sender-management-ip IP
  --measurement-timeout N
  --source-margin-percent N
  --post-measure-seconds N
  --skip-build 0|1
USAGE
    exit 2
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --role) ROLE="${2:-}"; shift 2 ;;
        --run-id) RUN_ID="${2:-}"; shift 2 ;;
        --profile) PROFILE="${2:-}"; shift 2 ;;
        --batching) BATCHING="${2:-}"; shift 2 ;;
        --rate) RATE="${2:-}"; shift 2 ;;
        --samples) SAMPLES="${2:-}"; shift 2 ;;
        --message-type) MESSAGE_TYPE="${2:-}"; shift 2 ;;
        --warmup-seconds) WARMUP_SECONDS="${2:-}"; shift 2 ;;
        --slots) SLOTS="${2:-}"; shift 2 ;;
        --data-port) DATA_PORT="${2:-}"; shift 2 ;;
        --shm) SHM_NAME="${2:-}"; shift 2 ;;
        --sender-data-ip) SENDER_DATA_IP="${2:-}"; shift 2 ;;
        --receiver-data-ip) RECEIVER_DATA_IP="${2:-}"; shift 2 ;;
        --next-hop-mac) NEXT_HOP_MAC="${2:-}"; shift 2 ;;
        --sender-management-ip) SENDER_MANAGEMENT_IP="${2:-}"; shift 2 ;;
        --measurement-timeout) MEASUREMENT_TIMEOUT="${2:-}"; shift 2 ;;
        --source-margin-percent) SOURCE_MARGIN_PERCENT="${2:-}"; shift 2 ;;
        --post-measure-seconds) POST_MEASURE_SECONDS="${2:-}"; shift 2 ;;
        --skip-build) SKIP_BUILD="${2:-}"; shift 2 ;;
        *) usage ;;
    esac
done

[[ "${EUID}" -eq 0 ]] || { echo "ERROR: benchmark_node.sh must run as root." >&2; exit 1; }
[[ "${ROLE}" == "sender" || "${ROLE}" == "receiver" ]] || usage
[[ -n "${RUN_ID}" && "${RUN_ID}" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "ERROR: invalid run id." >&2; exit 1; }
[[ "${PROFILE}" == "raw" || "${PROFILE}" == "compact" ]] || usage
[[ "${BATCHING}" == "0" || "${BATCHING}" == "1" ]] || usage
[[ "${SKIP_BUILD}" == "0" || "${SKIP_BUILD}" == "1" ]] || usage
[[ "${RATE}" =~ ^[0-9]+$ && "${RATE}" -gt 0 ]] || { echo "ERROR: rate must be > 0." >&2; exit 1; }
[[ "${SAMPLES}" =~ ^[0-9]+$ && "${SAMPLES}" -gt 0 ]] || { echo "ERROR: samples must be > 0." >&2; exit 1; }
[[ "${WARMUP_SECONDS}" =~ ^[0-9]+$ ]] || usage
[[ "${SLOTS}" =~ ^[0-9]+$ && "${SLOTS}" -gt 0 ]] || usage
[[ "${DATA_PORT}" =~ ^[0-9]+$ && "${DATA_PORT}" -gt 0 ]] || usage
[[ "${SOURCE_MARGIN_PERCENT}" =~ ^[0-9]+$ ]] || usage
[[ "${POST_MEASURE_SECONDS}" =~ ^[0-9]+$ ]] || usage

case "${MESSAGE_TYPE}" in
    trade|bbo|book|mixed) ;;
    *) usage ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_OWNER="$(stat -c '%U' "${ROOT}")"
RUN_DIR="${RESULT_ROOT}/${RUN_ID}/${ROLE}"
GO_FILE="${RUN_DIR}/go"
STATUS_FILE="${RUN_DIR}/status"

EXPECTED_SECONDS=$(( (SAMPLES + RATE - 1) / RATE ))
if [[ -z "${MEASUREMENT_TIMEOUT}" ]]; then
    MEASUREMENT_TIMEOUT=$(( EXPECTED_SECONDS * 3 ))
    (( MEASUREMENT_TIMEOUT < 15 )) && MEASUREMENT_TIMEOUT=15
fi
[[ "${MEASUREMENT_TIMEOUT}" =~ ^[0-9]+$ && "${MEASUREMENT_TIMEOUT}" -gt 0 ]] || usage

WARMUP_MESSAGES=$(( RATE * WARMUP_SECONDS ))
MEASURE_MESSAGES=$(( (SAMPLES * (100 + SOURCE_MARGIN_PERCENT) + 99) / 100 ))
POST_MESSAGES=$(( RATE * POST_MEASURE_SECONDS ))
PRODUCER_COUNT=$(( WARMUP_MESSAGES + MEASURE_MESSAGES + POST_MESSAGES ))
SOURCE_EXPECTED_SECONDS=$(( (PRODUCER_COUNT + RATE - 1) / RATE ))

mkdir -p "${RUN_DIR}"
chown "${REPO_OWNER}" "${RUN_DIR}"
chmod 0755 "${RUN_DIR}"
umask 022

exec > >(tee -a "${RUN_DIR}/node.log") 2>&1

taskset -pc "${HOUSEKEEPING_CORES}" $$ >/dev/null

SENDER_PID=""
RECEIVER_PID=""
PRODUCER_PID=""
AFTER_SNAPSHOT_DONE=0
FINAL_STATUS=""

status_write()
{
    printf '%s\n' "$1" > "${STATUS_FILE}.tmp"
    mv -f "${STATUS_FILE}.tmp" "${STATUS_FILE}"
}

process_alive()
{
    local pid="$1"
    local state

    [[ -n "${pid}" ]] || return 1
    kill -0 "${pid}" 2>/dev/null || return 1

    state="$(ps -o stat= -p "${pid}" 2>/dev/null | awk '{print $1}')"
    [[ -n "${state}" && "${state}" != Z* ]]
}

stop_group()
{
    local pid="$1"
    local signal="$2"

    [[ -n "${pid}" ]] || return 0
    process_alive "${pid}" || return 0

    kill -s "${signal}" -- "-${pid}" 2>/dev/null || true

    for _ in $(seq 1 100); do
        process_alive "${pid}" || return 0
        sleep 0.1
    done


    kill -KILL -- "-${pid}" 2>/dev/null || true
}

snapshot_clock()
{
    local output="$1"

    {
        echo "=== tracking ==="
        chronyc tracking
        echo
        echo "=== sources ==="
        chronyc sources -n -v
        echo
        echo "=== source statistics ==="
        chronyc sourcestats -n -v

        if [[ "${ROLE}" == "receiver" ]]; then
            echo
            echo "=== master NTP data ==="
            chronyc ntpdata "${SENDER_MANAGEMENT_IP}" || true
        fi
    } > "${output}" 2>&1 || true
}

snapshot_environment()
{
    {
        echo "=== git ==="
        git -C "${ROOT}" rev-parse HEAD
        git -C "${ROOT}" status --short
        echo
        echo "=== compiler ==="
        g++ --version | head -n 1
        echo
        echo "=== kernel ==="
        uname -a
        echo
        echo "=== cpu ==="
        lscpu -e=CPU,CORE,SOCKET,NODE,ONLINE
        echo
        echo "=== kernel command line ==="
        cat /proc/cmdline
        echo
        echo "=== hugepages ==="
        grep -E 'HugePages_Total|HugePages_Free|Hugepagesize' /proc/meminfo
        echo
        echo "=== PCI ethernet ==="
        lspci -nnk | grep -A3 -i 'Ethernet controller' || true
    } > "${RUN_DIR}/environment.txt" 2>&1
}

cleanup()
{
    local rc=$?
    trap - EXIT INT TERM
    set +e

    stop_group "${PRODUCER_PID}" TERM
    stop_group "${SENDER_PID}" INT
    stop_group "${RECEIVER_PID}" INT

    [[ -z "${PRODUCER_PID}" ]] || wait "${PRODUCER_PID}" 2>/dev/null || true
    [[ -z "${SENDER_PID}" ]] || wait "${SENDER_PID}" 2>/dev/null || true
    [[ -z "${RECEIVER_PID}" ]] || wait "${RECEIVER_PID}" 2>/dev/null || true

    if [[ "${AFTER_SNAPSHOT_DONE}" -eq 0 ]]; then
        snapshot_clock "${RUN_DIR}/clock-after.txt"
    fi

    if [[ "${FINAL_STATUS}" != "DONE" ]]; then
        status_write "FAILED ${rc}"
    fi

    chmod -R a+rX "${RUN_DIR}" 2>/dev/null || true
    exit "${rc}"
}

trap cleanup EXIT
trap 'exit 130' INT TERM

fail()
{
    echo "ERROR: $*" >&2
    exit 1
}

wait_until_epoch()
{
    local target="$1"
    local now
    local remaining

    while true; do
        now="$(date +%s)"
        (( now >= target )) && return 0

        remaining=$(( target - now ))
        if (( remaining > 1 )); then
            sleep "$(( remaining - 1 ))"
        else
            sleep 0.02
        fi
    done
}

wait_for_go()
{
    while [[ ! -s "${GO_FILE}" ]]; do
        if [[ "${ROLE}" == "receiver" && -n "${RECEIVER_PID}" ]]; then
            process_alive "${RECEIVER_PID}" || fail "Receiver exited before GO."
        fi
        sleep 0.1
    done
}

build_profile()
{
    [[ "${SKIP_BUILD}" == "0" ]] || return 0

    local command
    if [[ "${PROFILE}" == "compact" ]]; then
        command="cd '${ROOT}' && rm -rf build/lldt_release && ./scripts/build.sh --compact && make -C harness clean && make -C harness LLDT_MESSAGE_PROFILE=compact"
    else
        command="cd '${ROOT}' && rm -rf build/lldt_release && ./scripts/build.sh && make -C harness clean && make -C harness LLDT_MESSAGE_PROFILE=raw"
    fi

    sudo -u "${REPO_OWNER}" -H bash -lc "${command}"
}

status_write "PREPARING"
echo "LLDT benchmark node: role=${ROLE} run=${RUN_ID}"

echo "Building profile ${PROFILE}..."
build_profile

COMMIT="$(git -C "${ROOT}" rev-parse HEAD)"
printf '%s\n' "${COMMIT}" > "${RUN_DIR}/commit"

snapshot_environment
snapshot_clock "${RUN_DIR}/clock-before.txt"

cat > "${RUN_DIR}/manifest.json" <<EOF_JSON
{
  "run_id": "${RUN_ID}",
  "role": "${ROLE}",
  "commit": "${COMMIT}",
  "profile": "${PROFILE}",
  "batching": ${BATCHING},
  "rate": ${RATE},
  "samples": ${SAMPLES},
  "message_type": "${MESSAGE_TYPE}",
  "warmup_seconds": ${WARMUP_SECONDS},
  "measurement_timeout_seconds": ${MEASUREMENT_TIMEOUT},
  "slots": ${SLOTS},
  "data_port": ${DATA_PORT},
  "shm": "${SHM_NAME}",
  "sender_data_ip": "${SENDER_DATA_IP}",
  "receiver_data_ip": "${RECEIVER_DATA_IP}",
  "next_hop_mac": "${NEXT_HOP_MAC}"
}
EOF_JSON

SHM_PATH="/dev/shm/${SHM_NAME#/}"
rm -f "${SHM_PATH}"

if [[ "${ROLE}" == "receiver" ]]; then
    echo "Starting Receiver..."
    setsid env \
        LLDT_SHM="${SHM_NAME}" \
        LLDT_SLOTS="${SLOTS}" \
        LLDT_DATA_PORT="${DATA_PORT}" \
        "${SCRIPT_DIR}/run_receiver.sh" \
        "${RECEIVER_DATA_IP}" \
        "${SENDER_DATA_IP}" \
        "${NEXT_HOP_MAC}" \
        > "${RUN_DIR}/receiver.log" 2>&1 &
    RECEIVER_PID=$!

    sleep 1
    process_alive "${RECEIVER_PID}" || fail "Receiver exited during startup."
fi

status_write "READY"
echo "READY"
wait_for_go

read -r GO_EPOCH < "${GO_FILE}"
[[ "${GO_EPOCH}" =~ ^[0-9]+$ ]] || fail "Invalid GO timestamp."

NOW="$(date +%s)"
(( GO_EPOCH > NOW )) || fail "GO timestamp is not in the future."

printf '%s\n' "${GO_EPOCH}" > "${RUN_DIR}/go-accepted"

if [[ "${ROLE}" == "sender" ]]; then
    wait_until_epoch "${GO_EPOCH}"

    echo "Starting Producer..."
    setsid timeout \
        --signal=TERM \
        --kill-after=2s \
        "$(( SOURCE_EXPECTED_SECONDS + 10 ))s" \
        taskset -c 2 \
        "${ROOT}/harness/bin/producer" \
        --shm "${SHM_NAME}" \
        --slots "${SLOTS}" \
        --count "${PRODUCER_COUNT}" \
        --rate "${RATE}" \
        --type "${MESSAGE_TYPE}" \
        > "${RUN_DIR}/producer.log" 2>&1 &
    PRODUCER_PID=$!

    sleep 0.2
    process_alive "${PRODUCER_PID}" || fail "Producer exited during startup."

    echo "Starting Sender..."
    BATCHING_ARGS=()
    [[ "${BATCHING}" == "1" ]] && BATCHING_ARGS+=(--batching)

    setsid env \
        LLDT_SHM="${SHM_NAME}" \
        LLDT_SLOTS="${SLOTS}" \
        LLDT_DATA_PORT="${DATA_PORT}" \
        "${SCRIPT_DIR}/run_sender.sh" \
        "${SENDER_DATA_IP}" \
        "${RECEIVER_DATA_IP}" \
        "${NEXT_HOP_MAC}" \
        "${BATCHING_ARGS[@]}" \
        > "${RUN_DIR}/sender.log" 2>&1 &
    SENDER_PID=$!

    sleep 1
    process_alive "${SENDER_PID}" || fail "Sender exited during startup."

    status_write "RUNNING"

    set +e
    wait "${PRODUCER_PID}"
    PRODUCER_RC=$?
    set -e
    PRODUCER_PID=""
    [[ "${PRODUCER_RC}" -eq 0 ]] || fail "Producer failed with exit code ${PRODUCER_RC}."

    process_alive "${SENDER_PID}" || fail "Sender exited during source run."

    sleep "${POST_MEASURE_SECONDS}"

    stop_group "${SENDER_PID}" INT
    wait "${SENDER_PID}" 2>/dev/null || true
    SENDER_PID=""

    snapshot_clock "${RUN_DIR}/clock-after.txt"
    AFTER_SNAPSHOT_DONE=1
    FINAL_STATUS="DONE"
    status_write "DONE"
    echo "DONE"
    exit 0
fi

CONSUMER_START=$(( GO_EPOCH + WARMUP_SECONDS ))
wait_until_epoch "${CONSUMER_START}"

status_write "RUNNING"
echo "Starting measured Consumer..."

set +e
timeout \
    --signal=TERM \
    --kill-after=2s \
    "${MEASUREMENT_TIMEOUT}s" \
    taskset -c 2 \
    "${ROOT}/harness/bin/consumer" \
    --shm "${SHM_NAME}" \
    --slots "${SLOTS}" \
    --from-edge \
    --count "${SAMPLES}" \
    --idle-ms 10000 \
    --csv "${RUN_DIR}/latency.csv" \
    > "${RUN_DIR}/consumer.log" 2>&1
CONSUMER_RC=$?
set -e

[[ "${CONSUMER_RC}" -eq 0 ]] || fail "Consumer failed with exit code ${CONSUMER_RC}."
[[ -f "${RUN_DIR}/latency.csv" ]] || fail "latency.csv was not produced."

CSV_LINES="$(wc -l < "${RUN_DIR}/latency.csv")"
EXPECTED_LINES=$(( SAMPLES + 1 ))
[[ "${CSV_LINES}" -eq "${EXPECTED_LINES}" ]] || \
    fail "Consumer collected $(( CSV_LINES - 1 )) samples, expected ${SAMPLES}."

process_alive "${RECEIVER_PID}" || fail "Receiver exited during measured phase."

stop_group "${RECEIVER_PID}" INT
wait "${RECEIVER_PID}" 2>/dev/null || true
RECEIVER_PID=""

snapshot_clock "${RUN_DIR}/clock-after.txt"
AFTER_SNAPSHOT_DONE=1
FINAL_STATUS="DONE"
status_write "DONE"
echo "DONE"
exit 0
