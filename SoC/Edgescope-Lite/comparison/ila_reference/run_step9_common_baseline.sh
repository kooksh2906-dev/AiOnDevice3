#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
tcl_script="${script_dir}/build_step9_common_baseline.tcl"
log_dir="${script_dir}/results/step9/baseline_raw"
log_file="${log_dir}/baseline_build.log"

if [[ -n "${VIVADO_BIN:-}" ]]; then
  vivado_bin="${VIVADO_BIN}"
elif command -v vivado >/dev/null 2>&1; then
  vivado_bin="$(command -v vivado)"
elif [[ -x /media/user4/data/tools/Vivado/2024.2/bin/vivado ]]; then
  vivado_bin=/media/user4/data/tools/Vivado/2024.2/bin/vivado
else
  printf '%s\n' \
    'ERROR: Vivado was not found. Set VIVADO_BIN to Vivado 2024.2.' >&2
  exit 127
fi

version_line="$("${vivado_bin}" -version 2>/dev/null | sed -n '1p')"
if [[ "${version_line,,}" != *'vivado v2024.2'* ]]; then
  printf 'ERROR: Vivado 2024.2 is required; detected: %s\n' \
    "${version_line}" >&2
  exit 2
fi

mkdir -p -- "${log_dir}"
printf 'STEP9_BASELINE_LAUNCH|log=%s\n' "${log_file}"

set +e
"${vivado_bin}" \
  -mode batch \
  -nolog \
  -nojournal \
  -notrace \
  -source "${tcl_script}" \
  2>&1 | tee "${log_file}"
vivado_status="${PIPESTATUS[0]}"
set -e

if (( vivado_status != 0 )); then
  printf 'STEP9_BASELINE_LAUNCH|result=FAIL|exit_code=%d\n' \
    "${vivado_status}" | tee -a "${log_file}" >&2
  exit "${vivado_status}"
fi

printf '%s\n' \
  'STEP9_BASELINE_LAUNCH|result=PASS|exit_code=0' | tee -a "${log_file}"

printf '%s\n' \
  'STEP9_BASELINE_RUNNER: PASS' \
  "RESULTS: ${log_dir}"
