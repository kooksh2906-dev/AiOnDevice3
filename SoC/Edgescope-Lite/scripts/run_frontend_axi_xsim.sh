#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
run_dir="${TMPDIR:-/tmp}/edgescope_frontend_axi_xsim"
mkdir -p "$run_dir"
cd "$run_dir"

xvlog -sv \
  "$repo_root/rtl/include/logic_analyzer_pkg.sv" \
  "$repo_root/rtl/core/probe_sampler.sv" \
  "$repo_root/rtl/core/basic_trigger_engine.v" \
  "$repo_root/rtl/bus/probe_sampler_axi.sv" \
  "$repo_root/rtl/bus/basic_trigger_engine_axi.sv" \
  "$repo_root/sim/tb/tb_frontend_axi.sv"
xelab tb_frontend_axi -s frontend_axi_sim
xsim frontend_axi_sim -runall
