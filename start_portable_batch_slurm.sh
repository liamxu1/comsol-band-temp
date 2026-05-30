#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Usage:
#   ./start_portable_batch_slurm.sh [start] [end] [worker_count] [output_dir_name] [comsol_np]
# Examples:
#   ./start_portable_batch_slurm.sh
#   ./start_portable_batch_slurm.sh 1 1000 16 run_a 2
# Output directory rule:
#   if start/end are provided -> ${output_dir_name}_${start}-${end}
#   otherwise                 -> ${output_dir_name}
#
# This script is intended for execution inside a single SLURM allocation.
# It keeps the batch job alive in the foreground until all MATLAB workers exit.

# ---------------- Environment defaults ----------------
MATLAB_BIN="/public/home/sa23001064/matlab2025a/bin/matlab"
COMSOL_ROOT="/public/home/sa23001064/COMSOL"
TENSOR_DIR="/public/home/sa23001064/xqy/acoustic-band-comsol/bspline/tensors"

TASK_INDEX_START="${1:-}"
TASK_INDEX_END="${2:-}"
WORKER_COUNT="${3:-2}"
OUTPUT_DIR_NAME="${4:-output}"
COMSOL_NP="${5:-2}"

# ---------------- Optional simulation overrides ----------------
SAVE_MODEL="false"
WRITE_STANDARD_OUTPUTS="false"
VERBOSE="true"

if [[ -n "${TASK_INDEX_START}" && ! "${TASK_INDEX_START}" =~ ^[0-9]+$ ]]; then
    echo "Invalid start index: ${TASK_INDEX_START}" >&2
    exit 1
fi

if [[ -n "${TASK_INDEX_END}" && ! "${TASK_INDEX_END}" =~ ^[0-9]+$ ]]; then
    echo "Invalid end index: ${TASK_INDEX_END}" >&2
    exit 1
fi

if [[ ! "${WORKER_COUNT}" =~ ^[0-9]+$ ]] || [[ "${WORKER_COUNT}" -le 0 ]]; then
    echo "Invalid worker count: ${WORKER_COUNT}" >&2
    exit 1
fi

if [[ ! "${COMSOL_NP}" =~ ^[0-9]+$ ]]; then
    echo "Invalid comsol_np: ${COMSOL_NP}" >&2
    exit 1
fi

if [[ -z "${OUTPUT_DIR_NAME}" ]]; then
    echo "Output directory name must not be empty." >&2
    exit 1
fi

if [[ -n "${TASK_INDEX_START}" || -n "${TASK_INDEX_END}" ]]; then
    if [[ -z "${TASK_INDEX_START}" || -z "${TASK_INDEX_END}" ]]; then
        echo "Start and end must be provided together." >&2
        exit 1
    fi
    if [[ "${TASK_INDEX_START}" -gt "${TASK_INDEX_END}" ]]; then
        echo "Start index must be <= end index." >&2
        exit 1
    fi
    OUTPUT_DIR="${SCRIPT_DIR}/${OUTPUT_DIR_NAME}_${TASK_INDEX_START}-${TASK_INDEX_END}"
else
    OUTPUT_DIR="${SCRIPT_DIR}/${OUTPUT_DIR_NAME}"
fi

if [[ ! -x "${MATLAB_BIN}" ]]; then
    echo "MATLAB binary not executable: ${MATLAB_BIN}" >&2
    exit 1
fi

if [[ ! -d "${COMSOL_ROOT}" ]]; then
    echo "COMSOL root missing: ${COMSOL_ROOT}" >&2
    exit 1
fi

COMSOL_ROOT_EFFECTIVE="${COMSOL_ROOT}"
COMSOL_MLI_DIR="${COMSOL_ROOT_EFFECTIVE}/mli"
if [[ ! -d "${COMSOL_MLI_DIR}" && -d "${COMSOL_ROOT}/Multiphysics/mli" ]]; then
    COMSOL_ROOT_EFFECTIVE="${COMSOL_ROOT}/Multiphysics"
    COMSOL_MLI_DIR="${COMSOL_ROOT_EFFECTIVE}/mli"
fi

if [[ ! -d "${COMSOL_MLI_DIR}" ]]; then
    echo "COMSOL LiveLink mli directory missing under either:" >&2
    echo "  ${COMSOL_ROOT}/mli" >&2
    echo "  ${COMSOL_ROOT}/Multiphysics/mli" >&2
    echo "Update COMSOL_ROOT in this script to the directory that contains mli." >&2
    exit 1
fi

if [[ ! -d "${TENSOR_DIR}" ]]; then
    echo "Tensor directory missing: ${TENSOR_DIR}" >&2
    exit 1
fi

if ! command -v lsof >/dev/null 2>&1; then
    echo "Required command not found: lsof" >&2
    exit 1
fi

mkdir -p "${OUTPUT_DIR}"

if [[ -n "${TASK_INDEX_START}" ]]; then
    TASK_INDEX_START_EXPR="${TASK_INDEX_START}"
else
    TASK_INDEX_START_EXPR="[]"
fi

if [[ -n "${TASK_INDEX_END}" ]]; then
    TASK_INDEX_END_EXPR="${TASK_INDEX_END}"
else
    TASK_INDEX_END_EXPR="[]"
fi

HOST_LOG="${OUTPUT_DIR}/host_setup.log"
CONFIG_FILE="${OUTPUT_DIR}/batch_config.mat"

MATLAB_CODE="try, addpath('${SCRIPT_DIR}/portable_runner'); portable_run_batch(struct('tensor_dir','${TENSOR_DIR}','output_dir','${OUTPUT_DIR}','task_index_start',${TASK_INDEX_START_EXPR},'task_index_end',${TASK_INDEX_END_EXPR},'worker_count',0,'worker_matlab_bin','${MATLAB_BIN}','comsol_root','${COMSOL_ROOT_EFFECTIVE}','comsol_mli_dir','${COMSOL_MLI_DIR}','comsol_np',${COMSOL_NP},'save_model',${SAVE_MODEL},'write_standard_outputs',${WRITE_STANDARD_OUTPUTS},'verbose',${VERBOSE},'comsol_reuse_existing_server',false)); catch ME, disp(getReport(ME,'extended','hyperlinks','off')); exit(1); end; exit(0);"

echo "Launching portable batch on SLURM"
echo "  repo_root: ${SCRIPT_DIR}"
echo "  tensor_dir: ${TENSOR_DIR}"
echo "  output_dir: ${OUTPUT_DIR}"
echo "  task_index_start: ${TASK_INDEX_START:-<all>}"
echo "  task_index_end: ${TASK_INDEX_END:-<all>}"
echo "  worker_count: ${WORKER_COUNT}"
echo "  comsol_np: ${COMSOL_NP}"
echo "  comsol_root_input: ${COMSOL_ROOT}"
echo "  comsol_root_effective: ${COMSOL_ROOT_EFFECTIVE}"
echo "  comsol_mli_dir: ${COMSOL_MLI_DIR}"
if [[ -n "${SLURM_JOB_ID:-}" ]]; then
    echo "  slurm_job_id: ${SLURM_JOB_ID}"
fi
if [[ -n "${SLURM_CPUS_PER_TASK:-}" ]]; then
    echo "  slurm_cpus_per_task: ${SLURM_CPUS_PER_TASK}"
fi
if [[ -n "${SLURM_JOB_CPUS_PER_NODE:-}" ]]; then
    echo "  slurm_job_cpus_per_node: ${SLURM_JOB_CPUS_PER_NODE}"
fi
echo "  host_setup_log: ${HOST_LOG}"

"${MATLAB_BIN}" -batch "${MATLAB_CODE}" > "${HOST_LOG}" 2>&1

if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "Expected config file was not created: ${CONFIG_FILE}" >&2
    exit 1
fi

declare -a WORKER_PIDS=()

terminate_workers() {
    local pid
    for pid in "${WORKER_PIDS[@]:-}"; do
        if kill -0 "${pid}" 2>/dev/null; then
            kill -TERM "${pid}" 2>/dev/null || true
        fi
    done
    for pid in "${WORKER_PIDS[@]:-}"; do
        wait "${pid}" 2>/dev/null || true
    done
}

on_signal() {
    local signal_name="$1"
    echo "Received ${signal_name}; terminating worker processes." >&2
    terminate_workers
    exit 1
}

trap 'on_signal TERM' TERM
trap 'on_signal INT' INT

echo "Starting worker processes"
for ((i = 1; i <= WORKER_COUNT; i++)); do
    worker_tag="$(printf 'worker_%02d' "${i}")"
    log_file="${OUTPUT_DIR}/${worker_tag}.log"
    worker_code="try, addpath('${SCRIPT_DIR}/acoustic_band_comsol'); AddAcousticBandPaths(); run_band_dataset_worker('${CONFIG_FILE}'); catch ME, disp(getReport(ME,'extended','hyperlinks','off')); exit(1); end; exit(0);"
    "${MATLAB_BIN}" -batch "${worker_code}" > "${log_file}" 2>&1 &
    pid=$!
    WORKER_PIDS+=("${pid}")
    echo "  launched ${worker_tag} pid=${pid} log=${log_file}"
done

overall_status=0
for i in "${!WORKER_PIDS[@]}"; do
    pid="${WORKER_PIDS[$i]}"
    worker_tag="$(printf 'worker_%02d' "$((i + 1))")"
    if wait "${pid}"; then
        echo "  completed ${worker_tag} pid=${pid}"
    else
        status=$?
        echo "  failed ${worker_tag} pid=${pid} status=${status}" >&2
        overall_status=1
    fi
done

if [[ "${overall_status}" -ne 0 ]]; then
    echo "At least one worker exited with an error." >&2
fi

exit "${overall_status}"
