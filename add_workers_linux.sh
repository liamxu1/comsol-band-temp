#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Usage:
#   ./add_workers_linux.sh [output_dir] [additional_workers]
# Examples:
#   ./add_workers_linux.sh
#   ./add_workers_linux.sh output 2
#   ./add_workers_linux.sh run_001_1-100 2
OUTPUT_DIR_ARG="${1:-output}"
if [[ "${OUTPUT_DIR_ARG}" = /* ]]; then
    OUTPUT_DIR="${OUTPUT_DIR_ARG}"
else
    OUTPUT_DIR="${SCRIPT_DIR}/${OUTPUT_DIR_ARG}"
fi
ADDITIONAL_WORKERS="${2:-2}"
MATLAB_BIN="/public/home/sa23001064/matlab2025a/bin/matlab"

CONFIG_FILE="${OUTPUT_DIR}/batch_config.mat"
MODULE_DIR="${SCRIPT_DIR}/acoustic_band_comsol"

if [[ ! -x "${MATLAB_BIN}" ]]; then
    echo "MATLAB binary not executable: ${MATLAB_BIN}" >&2
    exit 1
fi

if [[ ! "${ADDITIONAL_WORKERS}" =~ ^[0-9]+$ ]] || [[ "${ADDITIONAL_WORKERS}" -le 0 ]]; then
    echo "Invalid additional worker count: ${ADDITIONAL_WORKERS}" >&2
    exit 1
fi

if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "Missing config file: ${CONFIG_FILE}" >&2
    echo "Start the batch once first so batch_config.mat is created." >&2
    exit 1
fi

if [[ ! -d "${MODULE_DIR}" ]]; then
    echo "Missing module directory: ${MODULE_DIR}" >&2
    exit 1
fi

timestamp="$(date +%Y%m%d_%H%M%S)"

echo "Adding workers to existing batch"
echo "  output_dir: ${OUTPUT_DIR}"
echo "  config_file: ${CONFIG_FILE}"
echo "  additional_workers: ${ADDITIONAL_WORKERS}"

for ((i=1; i<=ADDITIONAL_WORKERS; i++)); do
    worker_tag="$(printf 'extra_%s_%02d' "${timestamp}" "${i}")"
    log_file="${OUTPUT_DIR}/${worker_tag}.log"
    matlab_code="try, addpath('${MODULE_DIR}'); AddAcousticBandPaths(); run_band_dataset_worker('${CONFIG_FILE}'); catch ME, disp(getReport(ME,'extended','hyperlinks','off')); exit(1); end; exit(0);"
    nohup "${MATLAB_BIN}" -batch "${matlab_code}" > "${log_file}" 2>&1 &
    pid=$!
    echo "  launched ${worker_tag} pid=${pid} log=${log_file}"
done
