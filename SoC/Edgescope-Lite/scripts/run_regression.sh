#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd -- "$script_dir/.." && pwd)"
build_dir="$project_dir/build/regression"
wave_dir="$project_dir/artifacts/waves"
emit_waves=0

if [[ "${1:-}" == "--waves" ]]; then
  emit_waves=1
elif [[ $# -ne 0 ]]; then
  echo "Usage: $0 [--waves]" >&2
  exit 2
fi

if command -v iverilog >/dev/null 2>&1 &&
   command -v vvp >/dev/null 2>&1; then
  sv_simulator="icarus"
elif command -v xvlog >/dev/null 2>&1 &&
     command -v xelab >/dev/null 2>&1 &&
     command -v xsim >/dev/null 2>&1; then
  sv_simulator="xsim"
else
  echo "No supported SystemVerilog simulator found." >&2
  echo "Install iverilog+vvp or provide xvlog+xelab+xsim." >&2
  exit 1
fi

if ! command -v cc >/dev/null 2>&1; then
  echo "Required tool not found: cc" >&2
  exit 1
fi

mkdir -p "$build_dir"
if [[ $emit_waves -eq 1 ]]; then
  mkdir -p "$wave_dir"
fi

echo "SystemVerilog simulator: $sv_simulator"

run_sv_test_icarus() {
  local top="$1"
  shift
  local executable="$build_dir/$top.vvp"
  local log_file="$build_dir/$top.log"

  iverilog -g2012 -Wall -s "$top" -o "$executable" "$@"

  if [[ $emit_waves -eq 1 && "$top" != "tb_common_pkg" ]]; then
    (
      cd -- "$wave_dir"
      vvp "$executable" +VCD
    ) | tee "$log_file"
  else
    vvp "$executable" | tee "$log_file"
  fi
}

run_sv_test_xsim() {
  local top="$1"
  shift
  local test_dir="$build_dir/xsim/$top"
  local snapshot="${top}_sim"
  local log_file="$build_dir/$top.log"
  local generated_vcd="$test_dir/$top.vcd"

  mkdir -p "$test_dir"
  (
    cd -- "$test_dir"
    xvlog -sv "$@"
    xelab "$top" -s "$snapshot"
  )

  if [[ $emit_waves -eq 1 && "$top" != "tb_common_pkg" ]]; then
    rm -f -- "$generated_vcd"
    (
      cd -- "$test_dir"
      xsim "$snapshot" -runall -testplusarg VCD
    ) | tee "$log_file"

    if [[ ! -s "$generated_vcd" ]]; then
      echo "XSim did not create the expected waveform: $generated_vcd" >&2
      return 1
    fi
    cp -f -- "$generated_vcd" "$wave_dir/$top.vcd"
  else
    (
      cd -- "$test_dir"
      xsim "$snapshot" -runall
    ) | tee "$log_file"
  fi
}

run_sv_test() {
  if [[ "$sv_simulator" == "icarus" ]]; then
    run_sv_test_icarus "$@"
  else
    run_sv_test_xsim "$@"
  fi
}

pkg="$project_dir/rtl/include/logic_analyzer_pkg.sv"
core="$project_dir/rtl/core/circular_trace_buffer_core.sv"
axi="$project_dir/rtl/bus/circular_trace_buffer_axi.sv"
adapter="$project_dir/rtl/top/capture_bram_addr_adapter.sv"
ip_top="$project_dir/rtl/top/circular_trace_buffer_ip.sv"
bram_model="$project_dir/sim/models/capture_bram_tdp_model.sv"
tb_dir="$project_dir/sim/tb"

run_sv_test tb_common_pkg \
  "$pkg" "$tb_dir/tb_common_pkg.sv"

for test_name in basic trigger wrap control; do
  run_sv_test "tb_circular_trace_buffer_$test_name" \
    "$pkg" "$core" "$tb_dir/tb_circular_trace_buffer_$test_name.sv"
done

run_sv_test tb_circular_trace_buffer_axi \
  "$pkg" "$core" "$axi" "$tb_dir/tb_circular_trace_buffer_axi.sv"

run_sv_test tb_circular_trace_buffer_bram \
  "$pkg" "$core" "$axi" "$adapter" "$ip_top" \
  "$bram_model" "$tb_dir/tb_circular_trace_buffer_bram.sv"

cc -std=c11 -Wall -Wextra -Werror \
  -I "$project_dir/sw/include" \
  "$tb_dir/check_logic_analyzer_regs.c" \
  -o "$build_dir/check_logic_analyzer_regs"
"$build_dir/check_logic_analyzer_regs"

echo "PASS: 7 SystemVerilog tests and C register-header check"
if [[ $emit_waves -eq 1 ]]; then
  echo "Waveforms: $wave_dir"
fi
