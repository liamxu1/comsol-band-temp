#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Usage:
#   ./start_portable_batch_linux.sh [start] [end] [worker_count] [output_dir_name]
# Examples:
#   ./start_portable_batch_linux.sh
#   ./start_portable_batch_linux.sh 1 1000 4 run_a
# Output directory rule:
#   if start/end are provided -> ${output_dir_name}_${start}-${end}
#   otherwise                 -> ${output_dir_name}

# ---------------- Environment defaults ----------------
MATLAB_BIN="/public/home/sa23001064/matlab2025a/bin/matlab"
COMSOL_ROOT="/public/home/sa23001064/COMSOL"
TENSOR_DIR="/public/home/sa23001064/xqy/acoustic-band-comsol/bspline/tensors"

TASK_INDEX_START="${1:-}"
TASK_INDEX_END="${2:-}"
WORKER_COUNT="${3:-2}"
OUTPUT_DIR_NAME="${4:-output}"

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

MATLAB_CODE="try, addpath('${SCRIPT_DIR}/portable_runner'); portable_run_batch(struct('tensor_dir','${TENSOR_DIR}','output_dir','${OUTPUT_DIR}','task_index_start',${TASK_INDEX_START_EXPR},'task_index_end',${TASK_INDEX_END_EXPR},'worker_count',${WORKER_COUNT},'worker_matlab_bin','${MATLAB_BIN}','comsol_root','${COMSOL_ROOT_EFFECTIVE}','comsol_mli_dir','${COMSOL_MLI_DIR}','save_model',${SAVE_MODEL},'write_standard_outputs',${WRITE_STANDARD_OUTPUTS},'verbose',${VERBOSE},'comsol_reuse_existing_server',false)); catch ME, disp(getReport(ME,'extended','hyperlinks','off')); exit(1); end; exit(0);"

echo "Launching portable batch on Linux"
echo "  repo_root: ${SCRIPT_DIR}"
echo "  tensor_dir: ${TENSOR_DIR}"
echo "  output_dir: ${OUTPUT_DIR}"
echo "  task_index_start: ${TASK_INDEX_START:-<all>}"
echo "  task_index_end: ${TASK_INDEX_END:-<all>}"
echo "  worker_count: ${WORKER_COUNT}"
echo "  comsol_root_input: ${COMSOL_ROOT}"
echo "  comsol_root_effective: ${COMSOL_ROOT_EFFECTIVE}"
echo "  comsol_mli_dir: ${COMSOL_MLI_DIR}"
echo "  matlab_batch_entry: portable_run_batch(struct(...))"

"${MATLAB_BIN}" -batch "${MATLAB_CODE}"
