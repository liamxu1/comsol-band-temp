#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Usage:
#   ./cleanup_portable_batch_linux.sh [output_dir]
# Examples:
#   ./cleanup_portable_batch_linux.sh
#   ./cleanup_portable_batch_linux.sh output
#   ./cleanup_portable_batch_linux.sh run_001_1-100
OUTPUT_DIR_ARG="${1:-output}"
if [[ "${OUTPUT_DIR_ARG}" = /* ]]; then
    OUTPUT_DIR="${OUTPUT_DIR_ARG}"
else
    OUTPUT_DIR="${SCRIPT_DIR}/${OUTPUT_DIR_ARG}"
fi
KILL_COMSOL_SERVER="true"

find_worker_log_files() {
    find "${OUTPUT_DIR}" -maxdepth 1 -type f \
        \( -name 'worker_*.log' -o -name 'extra_*.log' \) \
        -print 2>/dev/null || true
}

unique_pid_lines() {
    awk 'NF { print $1 }' | sort -n -u
}

find_worker_pids() {
    if ! command -v lsof >/dev/null 2>&1; then
        return
    fi

    while read -r log_file; do
        [[ -z "${log_file}" ]] && continue
        lsof -t -- "${log_file}" 2>/dev/null || true
    done < <(find_worker_log_files)
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

signal_group() {
    local signal_name="$1"
    local pids="$2"
    if [[ -z "${pids}" ]]; then
        return
    fi
    while read -r pid; do
        [[ -z "${pid}" ]] && continue
        kill "-${signal_name}" "${pid}" 2>/dev/null || true
    done <<< "${pids}"
}

if [[ ! -d "${OUTPUT_DIR}" ]]; then
    echo "Output directory does not exist: ${OUTPUT_DIR}"
else
    echo "Removing lock directories under ${OUTPUT_DIR}"
    find "${OUTPUT_DIR}" \
        \( -type d -name '.lock' -o -type d -name '.batch_summary.lock' -o -type d -name '.comsol_server_start.lock' -o -type d -name '.task_cursor.lock' \) \
        -print -exec rm -rf {} +
    find "${OUTPUT_DIR}" -maxdepth 1 -type f \
        \( -name '.task_cursor.txt' -o -name '.batch_summary_event_count.txt' -o -name '.batch_summary_snapshot_event_count.txt' \) \
        -print -delete
fi

if [[ "${KILL_COMSOL_SERVER}" == "true" ]]; then
    if command -v lsof >/dev/null 2>&1; then
        MATLAB_PIDS="$(find_worker_pids | unique_pid_lines)"
        CHILD_PIDS="$(find_descendant_pids "${MATLAB_PIDS}" | unique_pid_lines)"
        if [[ -n "${MATLAB_PIDS}${CHILD_PIDS}" ]]; then
            echo "Stopping batch worker processes: ${MATLAB_PIDS}"
            if [[ -n "${CHILD_PIDS}" ]]; then
                echo "Stopping batch child processes: ${CHILD_PIDS}"
            fi
            signal_group TERM "${CHILD_PIDS}"
            signal_group TERM "${MATLAB_PIDS}"
        else
            echo "No batch worker or child processes found for ${OUTPUT_DIR}"
        fi
    else
        echo "lsof not available; skipped worker process cleanup"
    fi
fi

echo "Cleanup finished."
