#!/usr/bin/env bash

set -euo pipefail

step10_script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
step10_mode=final

if [[ "${1:-}" == "--draft" ]]; then
  step10_mode=draft
  shift
elif [[ "${1:-}" == "--final" ]]; then
  shift
fi

if [[ $# -ne 0 ]]; then
  printf 'Usage: %s [--draft|--final]\n' "$0" >&2
  exit 2
fi

step10_git_ref="${EDGESCOPE_STEP10_GITHUB_REF:-origin/main}"
step10_default_xsa="/home/user4/Downloads/Logic Analyzer/edgescope_lite_bd_wrapper.xsa"
step10_hardware_xsa="${EDGESCOPE_STEP10_XSA:-$step10_default_xsa}"

if [[ "$step10_mode" == final ]]; then
  "$step10_script_dir/run_step9_resource_timing.sh" --strict-complete
else
  "$step10_script_dir/run_step9_resource_timing.sh"
fi

"$step10_script_dir/run_step10_github_audit.sh" \
  "$step10_git_ref" "$step10_hardware_xsa"

PYTHONDONTWRITEBYTECODE=1 python3 -B \
  "$step10_script_dir/host/build_step10_final_package.py" \
  --mode "$step10_mode" \
  --github-ref "$step10_git_ref"

(
  cd "$step10_script_dir/results/step10"
  sha256sum -c SHA256SUMS
)

if ! rg -q '^EVIDENCE_PACKAGE=PASS$' \
    "$step10_script_dir/results/step10/step10_status.rpt"; then
  printf 'STEP10_EVIDENCE_PACKAGE=FAIL\n' >&2
  exit 1
fi

printf 'STEP10_EVIDENCE_PACKAGE=PASS\n'
printf 'PACKAGE_MODE=%s\n' "${step10_mode^^}"
