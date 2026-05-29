#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------- Quick knobs ----------------
MATLAB_BIN="/public/home/sa23001064/matlab2025a/bin/matlab"
COMSOL_ROOT="/public/home/sa23001064/COMSOL"
TENSOR_DIR="/public/home/sa23001064/xqy/acoustic-band-comsol/bspline/tensors"
OUTPUT_DIR="${SCRIPT_DIR}/output_linux"
TASK_INDEX_START=""
TASK_INDEX_END=""
WORKER_COUNT=2

# ---------------- Optional simulation overrides ----------------
SAVE_MODEL="true"
WRITE_STANDARD_OUTPUTS="true"
VERBOSE="true"

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

MATLAB_CODE=$(cat <<EOF
addpath('${SCRIPT_DIR}/portable_runner');
portable_run_batch(struct( ...
    'tensor_dir', '${TENSOR_DIR}', ...
    'output_dir', '${OUTPUT_DIR}', ...
    'task_index_start', ${TASK_INDEX_START_EXPR}, ...
    'task_index_end', ${TASK_INDEX_END_EXPR}, ...
    'worker_count', ${WORKER_COUNT}, ...
    'worker_matlab_bin', '${MATLAB_BIN}', ...
    'comsol_root', '${COMSOL_ROOT_EFFECTIVE}', ...
    'comsol_mli_dir', '${COMSOL_MLI_DIR}', ...
    'save_model', ${SAVE_MODEL}, ...
    'write_standard_outputs', ${WRITE_STANDARD_OUTPUTS}, ...
    'verbose', ${VERBOSE}, ...
    'comsol_reuse_existing_server', false));
EOF
)

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

"${MATLAB_BIN}" -batch "${MATLAB_CODE}"
