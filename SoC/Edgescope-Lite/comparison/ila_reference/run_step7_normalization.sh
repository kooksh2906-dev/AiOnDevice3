#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source_dir="${script_dir}/results/step6"
output_dir="${script_dir}/results/step7"

python3 -B "${script_dir}/host/validate_step6_capture_results.py" \
  --results-dir "${source_dir}"
python3 -B "${script_dir}/host/normalize_step7_ila_csv.py" \
  --source-dir "${source_dir}" \
  --output-dir "${output_dir}"
python3 -B "${script_dir}/host/validate_step7_normalized.py" \
  --source-dir "${source_dir}" \
  --output-dir "${output_dir}"

(
  cd "${output_dir}"
  sha256sum \
    rising_normalized.csv \
    falling_normalized.csv \
    pattern_normalized.csv \
    normalization_manifest.rpt \
    normalization_validation.rpt \
    step7_status.rpt \
    > SHA256SUMS.tmp
  mv SHA256SUMS.tmp SHA256SUMS
  sha256sum -c SHA256SUMS
)

printf '%s\n' \
  "STEP7_RUNNER: PASS" \
  "RESULTS: ${output_dir}"
