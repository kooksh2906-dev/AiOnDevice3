#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
reference_dir="$(cd -- "${script_dir}/.." && pwd)"
results_dir="${reference_dir}/results/step6"
tcl_script="${script_dir}/run_step6_hardware.tcl"

usage() {
  printf '%s\n' \
    'Usage:' \
    '  run_step6_hardware.sh dry_run' \
    '  run_step6_hardware.sh pair' \
    '  run_step6_hardware.sh arm     rising|falling|pattern|no_trigger' \
    '  run_step6_hardware.sh collect rising|falling|pattern|no_trigger' \
    '  run_step6_hardware.sh capture rising|falling|pattern|no_trigger' \
    '' \
    'Aliases:' \
    '  --dry-run  is the same as dry_run' \
    '' \
    'Optional environment:' \
    '  VIVADO_BIN                         Vivado 2024.2 executable' \
    '  EDGESCOPE_HW_SERVER_URL            default localhost:3121' \
    '  EDGESCOPE_HW_TARGET_PATTERN        explicit hardware-target name glob' \
    '  EDGESCOPE_CAPTURE_TIMEOUT_MIN      default 2.0' \
    '  EDGESCOPE_NO_TRIGGER_ACK_TIMEOUT_MS default 120000'
}

if (( $# == 0 )); then
  usage >&2
  exit 2
fi

action="$1"
if [[ "${action}" == "--dry-run" ]]; then
  action="dry_run"
  shift
  set -- "${action}" "$@"
fi

case "${action}" in
  dry_run|pair)
    if (( $# != 1 )); then
      usage >&2
      exit 2
    fi
    ;;
  arm|collect|capture)
    if (( $# != 2 )); then
      usage >&2
      exit 2
    fi
    case "$2" in
      rising|falling|pattern|no_trigger) ;;
      *)
        usage >&2
        exit 2
        ;;
    esac
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

if [[ -n "${VIVADO_BIN:-}" ]]; then
  vivado_bin="${VIVADO_BIN}"
elif command -v vivado >/dev/null 2>&1; then
  vivado_bin="$(command -v vivado)"
elif [[ -x /media/user4/data/tools/Vivado/2024.2/bin/vivado ]]; then
  vivado_bin=/media/user4/data/tools/Vivado/2024.2/bin/vivado
else
  printf '%s\n' \
    'ERROR: Vivado was not found. Set VIVADO_BIN to the Vivado 2024.2 executable.' \
    >&2
  exit 127
fi

version_line="$("${vivado_bin}" -version 2>/dev/null | sed -n '1p')"
if [[ "${version_line,,}" != *'vivado v2024.2'* ]]; then
  printf 'ERROR: Vivado 2024.2 is required; detected: %s\n' "${version_line}" >&2
  exit 2
fi

mkdir -p -- "${results_dir}"
profile_suffix=""
if (( $# == 2 )); then
  profile_suffix="_$2"
fi
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
session_log="${results_dir}/hardware_session_${action}${profile_suffix}_${timestamp}.log"
latest_log="${results_dir}/hardware_session.log"

printf 'STEP6_LAUNCH|action=%s|profile=%s|log=%s\n' \
  "${action}" "${2:-none}" "${session_log}"

set +e
"${vivado_bin}" \
  -mode batch \
  -nolog \
  -nojournal \
  -notrace \
  -source "${tcl_script}" \
  -tclargs "$@" \
  2>&1 | tee "${session_log}" "${latest_log}"
vivado_status="${PIPESTATUS[0]}"
set -e

if (( vivado_status != 0 )); then
  printf 'STEP6_LAUNCH|result=FAIL|exit_code=%d|log=%s\n' \
    "${vivado_status}" "${session_log}" >&2
  exit "${vivado_status}"
fi

printf 'STEP6_LAUNCH|result=PASS|log=%s\n' "${session_log}"
