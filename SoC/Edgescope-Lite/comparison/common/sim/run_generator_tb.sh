#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
common_dir="$(cd -- "${script_dir}/.." && pwd)"
build_dir="${common_dir}/build/generator_sim"

mkdir -p "${build_dir}"

iverilog \
  -g2012 \
  -Wall \
  -s tb_test_pattern_generator \
  -o "${build_dir}/tb_test_pattern_generator.vvp" \
  "${common_dir}/rtl/test_pattern_generator_gpio_adapter.v" \
  "${common_dir}/rtl/test_pattern_generator.sv" \
  "${script_dir}/tb_test_pattern_generator.sv"

(
  cd "${build_dir}"
  vvp ./tb_test_pattern_generator.vvp
)

iverilog \
  -g2012 \
  -Wall \
  -s tb_test_pattern_generator_frozen \
  -o "${build_dir}/tb_test_pattern_generator_frozen.vvp" \
  "${common_dir}/rtl/test_pattern_generator_gpio_adapter.v" \
  "${common_dir}/rtl/test_pattern_generator.sv" \
  "${script_dir}/tb_test_pattern_generator_frozen.sv"

(
  cd "${build_dir}"
  vvp ./tb_test_pattern_generator_frozen.vvp
)
