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

find_worker_log_files() {
    find "${OUTPUT_DIR}" -maxdepth 1 -type f \
        \( -name 'worker_*.log' -o -name 'extra_*.log' \) \
        -print 2>/dev/null || true
}

unique_pid_lines() {
    awk 'NF { print $1 }' | sort -n -u
}

find_worker_pids_from_logs() {
    if ! command -v lsof >/dev/null 2>&1; then
        return
    fi

    while read -r log_file; do
        [[ -z "${log_file}" ]] && continue
        lsof -t -- "${log_file}" 2>/dev/null || true
    done < <(find_worker_log_files)
}

find_worker_pids() {
    {
        find_worker_pids_from_logs
        find_pids "run_band_dataset_worker\\('${OUTPUT_DIR}/batch_config.mat'\\)"
    } | unique_pid_lines
}

find_descendant_pids() {
    local root_pids="$1"
    local queue=()
    local pid=""
    local idx=0
    declare -A seen=()

    while read -r pid; do
        pid="${pid//[[:space:]]/}"
        [[ -z "${pid}" ]] && continue
        if [[ -z "${seen[$pid]+x}" ]]; then
            seen["$pid"]=1
            queue+=("$pid")
        fi
    done <<< "${root_pids}"

    while [[ "${idx}" -lt "${#queue[@]}" ]]; do
        local parent_pid="${queue[$idx]}"
        local child_pid=""
        idx=$((idx + 1))

        while read -r child_pid; do
            child_pid="${child_pid//[[:space:]]/}"
            [[ -z "${child_pid}" ]] && continue
            if [[ -z "${seen[$child_pid]+x}" ]]; then
                seen["$child_pid"]=1
                queue+=("$child_pid")
                echo "${child_pid}"
            fi
        done < <(ps -o pid= --ppid "${parent_pid}" 2>/dev/null || true)
    done
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

MATLAB_PIDS="$(find_worker_pids)"
RELATED_CHILD_PIDS="$(find_descendant_pids "${MATLAB_PIDS}" | unique_pid_lines)"

case "${ACTION}" in
    status)
        print_group "MATLAB worker processes" "${MATLAB_PIDS}"
        print_group "Worker child processes (includes COMSOL server descendants)" "${RELATED_CHILD_PIDS}"
        ;;
    pause)
        signal_group STOP "${MATLAB_PIDS}"
        signal_group STOP "${RELATED_CHILD_PIDS}"
        echo "Paused matching MATLAB workers and their child processes."
        ;;
    resume)
        signal_group CONT "${MATLAB_PIDS}"
        signal_group CONT "${RELATED_CHILD_PIDS}"
        echo "Resumed matching MATLAB workers and their child processes."
        ;;
    stop)
        signal_group TERM "${MATLAB_PIDS}"
        signal_group TERM "${RELATED_CHILD_PIDS}"
        echo "Sent TERM to matching MATLAB workers and their child processes."
        echo "If some cases remain locked after stop, run cleanup_portable_batch_linux.sh."
        ;;
    *)
        echo "Usage: $0 [output_dir] [status|pause|resume|stop]" >&2
        exit 1
        ;;
esac
