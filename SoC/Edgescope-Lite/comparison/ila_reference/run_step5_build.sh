#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "${script_dir}/../.." && pwd)"
vivado_bin="/media/user4/data/tools/Vivado/2024.2/bin/vivado"
log_dir="${script_dir}/build/step5"

if [[ ! -x "${vivado_bin}" ]]; then
  echo "STEP5_ERROR: Vivado 2024.2 executable was not found: ${vivado_bin}" >&2
  exit 1
fi

mkdir -p "${log_dir}"

cd "${repo_dir}"

"${vivado_bin}" \
  -mode batch \
  -journal "${log_dir}/prepare_steps_1_to_4.jou" \
  -log "${log_dir}/prepare_steps_1_to_4.log" \
  -source "${script_dir}/build_step4_trigger_profiles.tcl"

"${vivado_bin}" \
  -mode batch \
  -journal "${log_dir}/implement_step5.jou" \
  -log "${log_dir}/implement_step5.log" \
  -source "${script_dir}/implement_step5_bitstream.tcl"

if ! rg -q '^VIVADO_ILA_STEP_5: PASS$' \
  "${log_dir}/implement_step5.log"; then
  echo "STEP5_ERROR: canonical log has no PASS marker" >&2
  exit 1
fi

echo "STEP5_CLEAN_BUILD: PASS"
