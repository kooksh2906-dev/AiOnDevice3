#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
reference_dir="$(cd -- "${script_dir}/.." && pwd)"
results_dir="${reference_dir}/results/step8"
tcl_script="${script_dir}/run_step8_pulse_stress.tcl"
validator="${reference_dir}/host/validate_step8_pulse_stress.py"
action="${1:-capture}"

usage() {
  printf '%s\n' \
    'Usage:' \
    '  run_step8_pulse_stress.sh' \
    '  run_step8_pulse_stress.sh capture' \
    '  run_step8_pulse_stress.sh --validate-only' \
    '' \
    'Required for capture:' \
    '  EDGESCOPE_HW_TARGET_PATTERN  exact hardware-target name glob' \
    '  EDGESCOPE_UART_PORT          Basys 3 UART port, e.g. /dev/ttyUSB1' \
    '' \
    'Optional:' \
    '  VIVADO_BIN                   Vivado 2024.2 executable' \
    '  EDGESCOPE_HW_SERVER_URL      default localhost:3121'
}

if (( $# > 1 )); then
  usage >&2
  exit 2
fi
case "${action}" in
  capture|--validate-only) ;;
  *)
    usage >&2
    exit 2
    ;;
esac

mkdir -p -- "${results_dir}"

if [[ "${action}" == "capture" ]]; then
  if [[ -z "${EDGESCOPE_HW_TARGET_PATTERN:-}" ]]; then
    printf '%s\n' 'ERROR: EDGESCOPE_HW_TARGET_PATTERN is required.' >&2
    exit 2
  fi
  if [[ -z "${EDGESCOPE_UART_PORT:-}" ]]; then
    printf '%s\n' 'ERROR: EDGESCOPE_UART_PORT is required.' >&2
    exit 2
  fi

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

  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  session_log="${results_dir}/hardware_session_${timestamp}.log"
  latest_log="${results_dir}/hardware_session.log"
  printf 'STEP8_LAUNCH|matrix=6x10|log=%s\n' "${session_log}"

  set +e
  "${vivado_bin}" \
    -mode batch \
    -nolog \
    -nojournal \
    -notrace \
    -source "${tcl_script}" \
    2>&1 | tee "${session_log}" "${latest_log}"
  vivado_status="${PIPESTATUS[0]}"
  set -e
  if (( vivado_status != 0 )); then
    printf 'STEP8_LAUNCH|result=FAIL|exit_code=%d|log=%s\n' \
      "${vivado_status}" "${session_log}" >&2
    exit "${vivado_status}"
  fi
fi

python3 -B "${validator}" --results-dir "${results_dir}"
(
  cd "${results_dir}"
  sha256sum -c SHA256SUMS
)

printf '%s\n' \
  'STEP8_RUNNER: PASS' \
  "RESULTS: ${results_dir}"
