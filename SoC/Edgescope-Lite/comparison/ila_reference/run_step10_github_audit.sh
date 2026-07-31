#!/usr/bin/env bash

set -euo pipefail

step10_script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
step10_repo_dir="$(cd -- "$step10_script_dir/../.." && pwd)"
step10_output_dir="$step10_script_dir/results/step10"
step10_git_ref="${1:-origin/main}"
step10_hardware_xsa="${2:-}"
step10_commit="$(git -C "$step10_repo_dir" rev-parse --verify "${step10_git_ref}^{commit}")"
step10_tmp="$(mktemp -d /tmp/edgescope-step10-github.XXXXXX)"
step10_raw_log="$step10_tmp/github_remote_tests.raw.log"
step10_circular_log="$step10_tmp/circular_buffer.log"
step10_trigger_log="$step10_tmp/basic_trigger_engine.log"
step10_sampler_log="$step10_tmp/probe_sampler.log"
step10_cpu_log="$step10_tmp/cpu_polling.log"
step10_demo_log="$step10_tmp/final_demo.log"
step10_log="$step10_output_dir/github_remote_tests.log"
step10_report="$step10_output_dir/github_remote_tests.rpt"

cleanup_step10_tmp() {
  rm -rf -- "$step10_tmp"
}
trap cleanup_step10_tmp EXIT

mkdir -p "$step10_output_dir"
git -C "$step10_repo_dir" archive "$step10_commit" |
  tar -x -C "$step10_tmp"
mkdir -p "$step10_tmp/build/step10"

step10_circular=FAIL
step10_trigger=FAIL
step10_sampler=FAIL
step10_cpu=FAIL

if "$step10_tmp/scripts/run_regression.sh" >"$step10_circular_log" 2>&1 &&
  rg -F -x -q 'PASS: 7 SystemVerilog tests and C register-header check' \
    "$step10_circular_log" &&
  ! rg -q '(^|[[:space:]])(FAIL|FATAL):' "$step10_circular_log"; then
  step10_circular=PASS
fi

if iverilog -g2012 -Wall -s tb_basic_trigger_engine \
    -o "$step10_tmp/build/step10/tb_basic_trigger_engine.vvp" \
    "$step10_tmp/rtl/core/basic_trigger_engine.v" \
    "$step10_tmp/sim/tb/tb_basic_trigger_engine.v" \
    >"$step10_trigger_log" 2>&1 &&
  vvp "$step10_tmp/build/step10/tb_basic_trigger_engine.vvp" \
    >>"$step10_trigger_log" 2>&1 &&
  rg -q 'ALL TESTS PASSED: 213 checks, 7 trigger events' \
    "$step10_trigger_log" &&
  ! rg -q 'TEST FAILED|FAIL: Simulation timeout' "$step10_trigger_log"; then
  step10_trigger=PASS
fi

if iverilog -g2012 -Wall -s tb_probe_sampler \
    -o "$step10_tmp/build/step10/tb_probe_sampler.vvp" \
    "$step10_tmp/rtl/core/probe_sampler.sv" \
    "$step10_tmp/sim/tb/tb_probe_sampler.sv" \
    >"$step10_sampler_log" 2>&1 &&
  vvp "$step10_tmp/build/step10/tb_probe_sampler.vvp" \
    >>"$step10_sampler_log" 2>&1 &&
  rg -F -x -q 'PASS: tb_probe_sampler (246 checks)' \
    "$step10_sampler_log"; then
  step10_sampler=PASS
fi

if make -C "$step10_tmp/comparison/cpu_polling/sw" test \
    >"$step10_cpu_log" 2>&1 &&
  rg -F -x -q 'cpu_polling_engine: all tests passed' \
    "$step10_cpu_log"; then
  step10_cpu=PASS
fi

step10_main_regression_new_ip_tests=FAIL
if rg -q 'tb_basic_trigger_engine' "$step10_tmp/scripts/run_regression.sh" &&
  rg -q 'tb_probe_sampler' "$step10_tmp/scripts/run_regression.sh"; then
  step10_main_regression_new_ip_tests=PASS
fi

step10_trigger_tb_failure_exit=FAIL
if rg -q '\$fatal' "$step10_tmp/sim/tb/tb_basic_trigger_engine.v"; then
  step10_trigger_tb_failure_exit=PASS
fi

step10_demo_ref=origin/agent/publish-final-demo
step10_demo_commit=NOT_AVAILABLE
step10_demo_merged=NO
step10_demo_xparameters=NOT_TESTED
step10_demo_bram_macro=NOT_TESTED
step10_demo_capture_order=NOT_TESTED
step10_demo_readme_conflict=NOT_TESTED

if git -C "$step10_repo_dir" rev-parse --verify --quiet \
    "${step10_demo_ref}^{commit}" >/dev/null; then
  step10_demo_commit="$(
    git -C "$step10_repo_dir" rev-parse "${step10_demo_ref}^{commit}"
  )"
  step10_demo_dir="$step10_tmp/final_demo_snapshot"
  mkdir -p "$step10_demo_dir" "$step10_tmp/final_demo_include"
  git -C "$step10_repo_dir" archive "$step10_demo_commit" |
    tar -x -C "$step10_demo_dir"

  if git -C "$step10_repo_dir" merge-base --is-ancestor \
      "$step10_demo_commit" "$step10_commit"; then
    step10_demo_merged=YES
  fi

  {
    printf '%s\n' '#ifndef XPARAMETERS_H'
    printf '%s\n' '#define XPARAMETERS_H'
    printf '%s\n' '#define XPAR_PROBE_SAMPLER_AXI_0_S00_AXI_BASEADDR 0x44A00000u'
    printf '%s\n' '#define XPAR_BASIC_TRIGGER_ENGINE_0_S_AXI_BASEADDR 0x44A10000u'
    printf '%s\n' '#define XPAR_CIRCULAR_TRACE_BUFFER_0_BASEADDR 0x00020000u'
    printf '%s\n' '#define XPAR_MICROBLAZE_RISCV_0_AXI_INTC_BASEADDR 0x41200000u'
    printf '%s\n' '#define XPAR_AXI_TIMER_0_BASEADDR 0x41C00000u'
    printf '%s\n' '#define XPAR_AXI_TIMER_0_CLOCK_FREQ_HZ 100000000u'
    printf '%s\n' '#define XPAR_AXI_BRAM_CTRL_0_S_AXI_BASEADDR 0xC0000000u'
    printf '%s\n' '#endif'
  } >"$step10_tmp/final_demo_include/xparameters.h"
  : >"$step10_tmp/final_demo_include/xil_io.h"
  : >"$step10_tmp/final_demo_include/xil_printf.h"

  if cc -E \
      -I "$step10_tmp/final_demo_include" \
      -I "$step10_demo_dir/sw/include" \
      -I "$step10_demo_dir/sw/vitis_app/src" \
      "$step10_demo_dir/sw/vitis_app/src/edge_scope_lite_control.c" \
      >/dev/null 2>"$step10_demo_log"; then
    step10_demo_xparameters=PASS
  else
    step10_demo_xparameters=FAIL
  fi

  step10_demo_bram_macro=FAIL
  if rg -q 'XPAR_AXI_BRAM_CTRL_0_S_AXI_BASEADDR' \
      "$step10_demo_dir/sw/vitis_app/src/edge_scope_lite_control.c"; then
    step10_demo_bram_macro=PASS
  fi

  step10_sampler_line="$(
    rg -n -F 'sampler_enable();' \
      "$step10_demo_dir/sw/vitis_app/src/main.c" |
      head -1 | cut -d: -f1 || true
  )"
  step10_arm_line="$(
    rg -n -F 'capture_arm();' \
      "$step10_demo_dir/sw/vitis_app/src/main.c" |
      head -1 | cut -d: -f1 || true
  )"
  step10_demo_capture_order=FAIL
  if [[ -n "$step10_sampler_line" && -n "$step10_arm_line" ]] &&
    (( step10_arm_line < step10_sampler_line )); then
    step10_demo_capture_order=PASS
  fi

  step10_merge_base="$(
    git -C "$step10_repo_dir" merge-base "$step10_commit" "$step10_demo_commit"
  )"
  git -C "$step10_repo_dir" merge-tree \
    "$step10_merge_base" "$step10_commit" "$step10_demo_commit" \
    >"$step10_tmp/final_demo_merge_tree.log"
  step10_demo_readme_conflict=NO
  if rg -q '<<<<<<<' "$step10_tmp/final_demo_merge_tree.log" &&
    rg -q 'README.md' "$step10_tmp/final_demo_merge_tree.log"; then
    step10_demo_readme_conflict=YES
  fi
fi

cat \
  "$step10_circular_log" \
  "$step10_trigger_log" \
  "$step10_sampler_log" \
  "$step10_cpu_log" \
  "$step10_demo_log" \
  >"$step10_raw_log"
sed "s#${step10_tmp}#<REMOTE_MAIN_SNAPSHOT>#g" \
  "$step10_raw_log" >"$step10_log"

step10_overall=PASS
for step10_result in \
  "$step10_circular" "$step10_trigger" "$step10_sampler" "$step10_cpu"; do
  if [[ "$step10_result" != PASS ]]; then
    step10_overall=FAIL
  fi
done

{
  printf '%s\n' '# EdgeScope-Lite GitHub remote main test report'
  printf 'REMOTE_MAIN_REFERENCE=%s\n' "$step10_git_ref"
  printf 'REMOTE_MAIN_COMMIT=%s\n' "$step10_commit"
  printf 'REMOTE_MAIN_TESTS=%s\n' "$step10_overall"
  printf 'CIRCULAR_BUFFER_REGRESSION=%s\n' "$step10_circular"
  printf 'CIRCULAR_BUFFER_TEST_COUNT=7\n'
  printf 'BASIC_TRIGGER_ENGINE_TEST=%s\n' "$step10_trigger"
  printf 'BASIC_TRIGGER_ENGINE_CHECK_COUNT=213\n'
  printf 'PROBE_SAMPLER_TEST=%s\n' "$step10_sampler"
  printf 'PROBE_SAMPLER_CHECK_COUNT=246\n'
  printf 'CPU_POLLING_ENGINE_TEST=%s\n' "$step10_cpu"
  printf 'MAIN_REGRESSION_INCLUDES_NEW_IP_TESTS=%s\n' \
    "$step10_main_regression_new_ip_tests"
  printf 'BASIC_TRIGGER_TB_FAILURE_EXIT_NONZERO=%s\n' \
    "$step10_trigger_tb_failure_exit"
  printf 'FINAL_DEMO_REFERENCE=%s\n' "$step10_demo_ref"
  printf 'FINAL_DEMO_COMMIT=%s\n' "$step10_demo_commit"
  printf 'FINAL_DEMO_MERGED_TO_MAIN=%s\n' "$step10_demo_merged"
  printf 'FINAL_DEMO_XPARAMETERS_COMPATIBILITY=%s\n' \
    "$step10_demo_xparameters"
  printf 'FINAL_DEMO_BRAM_MACRO_COMPATIBILITY=%s\n' \
    "$step10_demo_bram_macro"
  printf 'FINAL_DEMO_ARM_BEFORE_SAMPLER=%s\n' \
    "$step10_demo_capture_order"
  printf 'FINAL_DEMO_README_MERGE_CONFLICT=%s\n' \
    "$step10_demo_readme_conflict"
  if [[ -n "$step10_hardware_xsa" && -f "$step10_hardware_xsa" ]]; then
    printf 'HARDWARE_XSA_SHA256=%s\n' \
      "$(sha256sum "$step10_hardware_xsa" | cut -d' ' -f1)"
  else
    printf 'HARDWARE_XSA_SHA256=NOT_PROVIDED\n'
  fi
  printf 'TEST_LOG_SHA256=%s\n' "$(sha256sum "$step10_log" | cut -d' ' -f1)"
} >"$step10_report"

if [[ "$step10_overall" != PASS ]]; then
  printf 'GITHUB_REMOTE_AUDIT=FAIL\n' >&2
  exit 1
fi

printf 'GITHUB_REMOTE_AUDIT=PASS\n'
printf 'REMOTE_MAIN_COMMIT=%s\n' "$step10_commit"
