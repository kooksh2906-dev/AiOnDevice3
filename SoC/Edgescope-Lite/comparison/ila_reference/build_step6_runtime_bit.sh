#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "${script_dir}/../.." && pwd)"
step5_dir="${script_dir}/build/step5"
step6_dir="${script_dir}/build/step6"
firmware_dir="${script_dir}/sw/runtime_control"
firmware_elf="${firmware_dir}/build/edgescope_runtime_control.elf"
base_bit="${step5_dir}/edgescope_ila_reference.bit"
step5_ltx="${step5_dir}/debug_nets.ltx"
runtime_bit="${step6_dir}/edgescope_ila_reference_runtime.bit"
runtime_ltx="${step6_dir}/debug_nets.ltx"
runtime_mmi="${step6_dir}/edgescope_ila_reference_runtime.mmi"
runtime_manifest="${step6_dir}/runtime_pair_manifest.rpt"
runtime_checksums="${step6_dir}/SHA256SUMS"
header_normalizer="${script_dir}/tools/normalize_bit_header.py"

vivado_bin="/media/user4/data/tools/Vivado/2024.2/bin/vivado"
updatemem_bin="/media/user4/data/tools/Vivado/2024.2/bin/updatemem"
readelf_bin="/media/user4/data/tools/Vitis/2024.2/gnu/riscv/lin/riscv64-unknown-elf/bin/riscv64-unknown-elf-readelf"

for required_tool in "${vivado_bin}" "${updatemem_bin}" "${readelf_bin}"; do
  if [[ ! -x "${required_tool}" ]]; then
    echo "STEP6_RUNTIME_BIT_ERROR: executable is missing: ${required_tool}" >&2
    exit 1
  fi
done
if [[ ! -f "${header_normalizer}" ]]; then
  echo "STEP6_RUNTIME_BIT_ERROR: BIT header normalizer is missing" >&2
  exit 1
fi

mkdir -p "${step6_dir}"

cd "${script_dir}"
if ! sha256sum -c generated/ila_reference_step5_SHA256SUMS; then
  echo "STEP6_RUNTIME_BIT_ERROR: Step-5 source pair/checksum set changed" >&2
  exit 1
fi

"${firmware_dir}/build.sh"
if [[ ! -s "${firmware_elf}" ]]; then
  echo "STEP6_RUNTIME_BIT_ERROR: runtime ELF was not built" >&2
  exit 1
fi

elf_class="$("${readelf_bin}" -h "${firmware_elf}" |
  awk -F: '/Class:/ {gsub(/^[[:space:]]+/, "", $2); print $2}')"
elf_machine="$("${readelf_bin}" -h "${firmware_elf}" |
  awk -F: '/Machine:/ {gsub(/^[[:space:]]+/, "", $2); print $2}')"
elf_entry="$("${readelf_bin}" -h "${firmware_elf}" |
  awk '/Entry point address:/ {print $4}')"
if [[ "${elf_class}" != "ELF32" ||
      "${elf_machine}" != "RISC-V" ||
      "${elf_entry}" != "0x0" ]]; then
  echo "STEP6_RUNTIME_BIT_ERROR: unexpected firmware ELF identity" >&2
  exit 1
fi

cd "${repo_dir}"
"${vivado_bin}" \
  -mode batch \
  -journal "${step6_dir}/export_memory_map.jou" \
  -log "${step6_dir}/export_memory_map.log" \
  -source "${script_dir}/export_step6_memory_map.tcl"

if ! rg -q '^VIVADO_ILA_STEP_6_MEMORY_MAP: PASS$' \
  "${step6_dir}/export_memory_map.log"; then
  echo "STEP6_RUNTIME_BIT_ERROR: MMI export has no PASS marker" >&2
  exit 1
fi
if [[ ! -s "${runtime_mmi}" ]]; then
  echo "STEP6_RUNTIME_BIT_ERROR: runtime MMI is missing" >&2
  exit 1
fi

"${updatemem_bin}" \
  -force \
  -meminfo "${runtime_mmi}" \
  -data "${firmware_elf}" \
  -bit "${base_bit}" \
  -proc base_soc_i/microblaze_riscv_0 \
  -out "${runtime_bit}"

if [[ ! -s "${runtime_bit}" ]]; then
  echo "STEP6_RUNTIME_BIT_ERROR: updatemem did not create the runtime BIT" >&2
  exit 1
fi

# updatemem writes the current wall-clock time into the non-programmed BIT
# container header.  Copy only the Step-5 date/time header fields so identical
# inputs produce an identical file; the normalizer proves that the FPGA
# configuration payload SHA-256 is unchanged.
python3 -B "${header_normalizer}" \
  --reference "${base_bit}" \
  --target "${runtime_bit}"

if cmp -s "${base_bit}" "${runtime_bit}"; then
  echo "STEP6_RUNTIME_BIT_ERROR: runtime BIT equals the bootloop BIT" >&2
  exit 1
fi

cp -- "${step5_ltx}" "${runtime_ltx}"
if ! cmp -s "${step5_ltx}" "${runtime_ltx}"; then
  echo "STEP6_RUNTIME_BIT_ERROR: copied LTX differs from the Step-5 LTX" >&2
  exit 1
fi

base_bit_sha="$(sha256sum "${base_bit}" | awk '{print $1}')"
runtime_bit_sha="$(sha256sum "${runtime_bit}" | awk '{print $1}')"
runtime_ltx_sha="$(sha256sum "${runtime_ltx}" | awk '{print $1}')"
runtime_mmi_sha="$(sha256sum "${runtime_mmi}" | awk '{print $1}')"
firmware_elf_sha="$(sha256sum "${firmware_elf}" | awk '{print $1}')"

{
  echo "EdgeScope-Lite Vivado ILA Reference - Step 6 Runtime Pair"
  echo "========================================================="
  echo "Hardware implementation : frozen Step-5 routed design"
  echo "BRAM update method       : Vivado 2024.2 updatemem"
  echo "BIT header date/time      : normalized to Step-5 container"
  echo "Processor instance       : base_soc_i/microblaze_riscv_0"
  echo "Firmware ELF class       : ${elf_class}"
  echo "Firmware machine         : ${elf_machine}"
  echo "Firmware entry           : ${elf_entry}"
  echo "Runtime command path      : UART RUN"
  echo "UART                      : 9600 baud, 8-N-1"
  echo "Base BIT SHA-256          : ${base_bit_sha}"
  echo "Runtime BIT SHA-256       : ${runtime_bit_sha}"
  echo "Runtime LTX SHA-256       : ${runtime_ltx_sha}"
  echo "Runtime MMI SHA-256       : ${runtime_mmi_sha}"
  echo "Firmware ELF SHA-256      : ${firmware_elf_sha}"
  echo "Runtime BIT differs       : PASS"
  echo "LTX unchanged from Step 5 : PASS"
  echo "Hardware pair readback    : PENDING STEP 6 BOARD SESSION"
} > "${runtime_manifest}"

cd "${step6_dir}"
sha256sum \
  edgescope_ila_reference_runtime.bit \
  debug_nets.ltx \
  edgescope_ila_reference_runtime.mmi \
  ../../sw/runtime_control/build/edgescope_runtime_control.elf \
  runtime_pair_manifest.rpt \
  > SHA256SUMS

echo "STEP6_RUNTIME_BIT: PASS"
echo "Runtime BIT: ${runtime_bit}"
echo "Runtime LTX: ${runtime_ltx}"
echo "Manifest   : ${runtime_manifest}"
