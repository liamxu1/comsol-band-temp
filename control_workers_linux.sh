#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Usage:
#   ./control_workers_linux.sh [output_dir] [status|pause|resume|stop]
# Examples:
#   ./control_workers_linux.sh
#   ./control_workers_linux.sh output status
#   ./control_workers_linux.sh run_001_1-100 pause
OUTPUT_DIR_ARG="${1:-output}"
if [[ "${OUTPUT_DIR_ARG}" = /* ]]; then
    OUTPUT_DIR="${OUTPUT_DIR_ARG}"
else
    OUTPUT_DIR="${SCRIPT_DIR}/${OUTPUT_DIR_ARG}"
fi
ACTION="${2:-status}"

find_pids() {
    local pattern="$1"
    pgrep -u "${USER}" -f "${pattern}" || true
}

print_group() {
    local title="$1"
    local pids="$2"
    echo "${title}:"
    if [[ -z "${pids}" ]]; then
        echo "  <none>"
        return
    fi
    while read -r pid; do
        [[ -z "${pid}" ]] && continue
        ps -p "${pid}" -o pid=,stat=,%cpu=,%mem=,etime=,cmd=
    done <<< "${pids}"
}

signal_group() {
    local signal_name="$1"
    local pids="$2"
    if [[ -z "${pids}" ]]; then
        return
    fi
    while read -r pid; do
        [[ -z "${pid}" ]] && continue
        kill "-${signal_name}" "${pid}"
    done <<< "${pids}"
}

MATLAB_PIDS="$(find_pids "run_band_dataset_worker\\('${OUTPUT_DIR}/batch_config.mat'\\)")"
COMSOL_PIDS="$(find_pids 'comsolmphserver')"

case "${ACTION}" in
    status)
        print_group "MATLAB worker processes" "${MATLAB_PIDS}"
        print_group "COMSOL mphserver processes" "${COMSOL_PIDS}"
        ;;
    pause)
        signal_group STOP "${MATLAB_PIDS}"
        signal_group STOP "${COMSOL_PIDS}"
        echo "Paused matching MATLAB workers and comsolmphserver processes."
        ;;
    resume)
        signal_group CONT "${MATLAB_PIDS}"
        signal_group CONT "${COMSOL_PIDS}"
        echo "Resumed matching MATLAB workers and comsolmphserver processes."
        ;;
    stop)
        signal_group TERM "${MATLAB_PIDS}"
        signal_group TERM "${COMSOL_PIDS}"
        echo "Sent TERM to matching MATLAB workers and comsolmphserver processes."
        echo "If some cases remain locked after stop, run cleanup_portable_batch_linux.sh."
        ;;
    *)
        echo "Usage: $0 [output_dir] [status|pause|resume|stop]" >&2
        exit 1
        ;;
esac
