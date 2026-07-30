#!/usr/bin/env bash

set -u

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd -- "$script_dir/.." && pwd)"
failures=0
warnings=0

pass() {
  printf 'PASS  %s\n' "$1"
}

warn() {
  printf 'WARN  %s\n' "$1"
  warnings=$((warnings + 1))
}

fail() {
  printf 'FAIL  %s\n' "$1"
  failures=$((failures + 1))
}

check_command() {
  local command_name="$1"
  if command -v "$command_name" >/dev/null 2>&1; then
    pass "$command_name: $(command -v "$command_name")"
  else
    fail "$command_name is not available in PATH"
  fi
}

check_artifact() {
  local relative_path="$1"
  if [[ -s "$project_dir/$relative_path" ]]; then
    pass "$relative_path"
  else
    fail "missing portable artifact: $relative_path"
  fi
}

printf 'EdgeScope-Lite portable environment check\n'
printf 'Project: %s\n\n' "$project_dir"

for required_command in git python3 cc vivado vitis updatemem xvlog xelab xsim; do
  check_command "$required_command"
done

if command -v vivado >/dev/null 2>&1; then
  vivado_version="$(vivado -version 2>/dev/null | sed -n '1p')"
  if [[ "$vivado_version" == *"v2024.2"* ]]; then
    pass "Vivado version: $vivado_version"
  else
    fail "Vivado 2024.2 required; detected: ${vivado_version:-unknown}"
  fi
fi

if python3 -c 'import serial' >/dev/null 2>&1; then
  serial_version="$(python3 -c 'import serial; print(serial.__version__)')"
  pass "pyserial: $serial_version"
else
  warn "pyserial is missing; install with: python3 -m pip install -r requirements-gui.txt"
fi

if [[ -n "${VIVADO:-}" ]]; then
  if [[ -x "$VIVADO" ]]; then
    pass "VIVADO override: $VIVADO"
  else
    fail "VIVADO must point to an executable Vivado binary: $VIVADO"
  fi
else
  warn "VIVADO is not set; the GUI will use the Vivado 2024.2 binary from PATH or standard install paths"
fi

if [[ -n "${EDGESCOPE_BOARD_REPO:-}" ]]; then
  if [[ -d "$EDGESCOPE_BOARD_REPO" ]]; then
    pass "EDGESCOPE_BOARD_REPO: $EDGESCOPE_BOARD_REPO"
  else
    fail "EDGESCOPE_BOARD_REPO is not a directory: $EDGESCOPE_BOARD_REPO"
  fi
else
  warn "EDGESCOPE_BOARD_REPO is not set; Vivado/XHub standard board paths will be searched"
fi

check_artifact comparison/cpu_polling/vitis_artifacts/cpu_polling_app.bit
check_artifact comparison/edgescope_lite/vitis_artifacts/edgescope_lite_app.bit
check_artifact comparison/vivado_ila/vitis_artifacts/vivado_ila_app.bit
check_artifact comparison/vivado_ila/hw/vivado_ila_reference.ltx

if command -v lsusb >/dev/null 2>&1; then
  if lsusb | grep -Eiq 'Digilent|Xilinx|0403:6010'; then
    pass "Digilent/Xilinx USB device detected"
  else
    warn "no Digilent/Xilinx USB device detected; GUI DEMO works, but board programming does not"
  fi
else
  warn "lsusb is unavailable; JTAG USB detection was skipped"
fi

if compgen -G '/dev/ttyUSB*' >/dev/null ||
   compgen -G '/dev/ttyACM*' >/dev/null; then
  pass "at least one ttyUSB/ttyACM serial device is present"
else
  warn "no ttyUSB/ttyACM serial device is present"
fi

printf '\nSummary: %d failure(s), %d warning(s)\n' "$failures" "$warnings"
if ((failures != 0)); then
  exit 1
fi

printf 'Portable environment: PASS\n'
