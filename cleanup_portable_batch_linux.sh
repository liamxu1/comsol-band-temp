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

if [[ ! -d "${OUTPUT_DIR}" ]]; then
    echo "Output directory does not exist: ${OUTPUT_DIR}"
else
    echo "Removing lock directories under ${OUTPUT_DIR}"
    find "${OUTPUT_DIR}" \
        \( -type d -name '.lock' -o -type d -name '.batch_summary.lock' -o -type d -name '.comsol_server_start.lock' \) \
        -print -exec rm -rf {} +
fi

if [[ "${KILL_COMSOL_SERVER}" == "true" ]]; then
    if command -v pgrep >/dev/null 2>&1; then
        PIDS="$(pgrep -u "${USER}" -f 'comsolmphserver' || true)"
        if [[ -n "${PIDS}" ]]; then
            echo "Stopping comsolmphserver processes: ${PIDS}"
            pkill -u "${USER}" -f 'comsolmphserver' || true
        else
            echo "No comsolmphserver process found for user ${USER}"
        fi
    else
        echo "pgrep/pkill not available; skipped comsolmphserver cleanup"
    fi
fi

echo "Cleanup finished."
