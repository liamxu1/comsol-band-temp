#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Usage:
#   ./list_failed_cases.sh [output_dir]
# Examples:
#   ./list_failed_cases.sh
#   ./list_failed_cases.sh output
#   ./list_failed_cases.sh /path/to/output_dir
OUTPUT_DIR_ARG="${1:-output}"
if [[ "${OUTPUT_DIR_ARG}" = /* ]]; then
    OUTPUT_DIR="${OUTPUT_DIR_ARG}"
else
    OUTPUT_DIR="${SCRIPT_DIR}/${OUTPUT_DIR_ARG}"
fi

if [[ ! -d "${OUTPUT_DIR}" ]]; then
    echo "Output directory does not exist: ${OUTPUT_DIR}" >&2
    exit 1
fi

print_row() {
    local case_id="$1"
    local attempt_count="$2"
    local failure_kind="$3"
    local worker_exit_reason="$4"
    local message="$5"

    printf '%s,%s,%s,%s,%s\n' \
        "$(csv_escape "${case_id}")" \
        "$(csv_escape "${attempt_count}")" \
        "$(csv_escape "${failure_kind}")" \
        "$(csv_escape "${worker_exit_reason}")" \
        "$(csv_escape "${message}")"
}

csv_escape() {
    local value="$1"
    value="${value//\"/\"\"}"
    printf '"%s"' "${value}"
}

printf '%s\n' '"case_id","attempt_count","failure_kind","worker_exit_reason","message"'

found_any="false"
while IFS= read -r done_file; do
    case_dir="$(dirname "${done_file}")"
    case_id="$(basename "${case_dir}")"

    status=""
    attempt_count=""
    failure_kind=""
    worker_exit_reason=""
    message=""

    while IFS= read -r line; do
        key="${line%%=*}"
        value="${line#*=}"
        if [[ "${line}" != *=* ]]; then
            continue
        fi
        case "${key}" in
            status)
                status="${value}"
                ;;
            attempt_count)
                attempt_count="${value}"
                ;;
            failure_kind)
                failure_kind="${value}"
                ;;
            worker_exit_reason)
                worker_exit_reason="${value}"
                ;;
            message)
                message="${value}"
                ;;
        esac
    done < "${done_file}"

    if [[ "${status}" != "error" ]]; then
        continue
    fi

    found_any="true"
    print_row \
        "${case_id}" \
        "${attempt_count}" \
        "${failure_kind}" \
        "${worker_exit_reason}" \
        "${message}"
done < <(find "${OUTPUT_DIR}" -mindepth 2 -maxdepth 2 -type f -name '.done' | sort)

if [[ "${found_any}" != "true" ]]; then
    echo "No failed cases found under ${OUTPUT_DIR}" >&2
fi
