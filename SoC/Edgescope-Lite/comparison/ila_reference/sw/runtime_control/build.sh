#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
build_dir="${script_dir}/build"

default_tool_bin="/media/user4/data/tools/Vitis/2024.2/gnu/riscv/lin/riscv64-unknown-elf/bin"
runtime_tool_bin="${EDGESCOPE_RISCV_TOOL_BIN:-${default_tool_bin}}"
runtime_tool_prefix="${EDGESCOPE_RISCV_TOOL_PREFIX:-riscv64-unknown-elf-}"

cc="${runtime_tool_bin}/${runtime_tool_prefix}gcc"
objcopy="${runtime_tool_bin}/${runtime_tool_prefix}objcopy"
objdump="${runtime_tool_bin}/${runtime_tool_prefix}objdump"
readelf="${runtime_tool_bin}/${runtime_tool_prefix}readelf"
nm="${runtime_tool_bin}/${runtime_tool_prefix}nm"
size="${runtime_tool_bin}/${runtime_tool_prefix}size"

for required_tool in \
  "${cc}" "${objcopy}" "${objdump}" "${readelf}" "${nm}" "${size}"; do
  if [[ ! -x "${required_tool}" ]]; then
    echo "ERROR: required RISC-V tool is not executable: ${required_tool}" >&2
    exit 1
  fi
done

mkdir -p "${build_dir}"
cd "${build_dir}"

arch_flags=(
  -march=rv32i_zicsr_zifencei
  -mabi=ilp32
  -mno-relax
  -msmall-data-limit=0
)

compile_flags=(
  "${arch_flags[@]}"
  -O2
  -g
  -ffreestanding
  -fno-builtin
  -fno-common
  -fno-jump-tables
  -fno-pic
  -fno-pie
  -fno-stack-protector
  -fno-unwind-tables
  -fno-asynchronous-unwind-tables
  -ffunction-sections
  -fdata-sections
  -Wall
  -Wextra
  -Werror
)

"${cc}" "${compile_flags[@]}" \
  -c ../startup.S \
  -o startup.o

"${cc}" "${compile_flags[@]}" \
  -std=c11 \
  -c ../runtime_control.c \
  -o runtime_control.o

"${cc}" "${arch_flags[@]}" \
  -nostdlib \
  -nostartfiles \
  -no-pie \
  -Wl,-T,../linker.ld \
  -Wl,--gc-sections \
  -Wl,--no-relax \
  -Wl,--build-id=none \
  -Wl,-Map,edgescope_runtime_control.map \
  startup.o \
  runtime_control.o \
  -o edgescope_runtime_control.elf

"${objcopy}" -O binary \
  edgescope_runtime_control.elf \
  edgescope_runtime_control.bin

"${readelf}" -h -l -S -A -W \
  edgescope_runtime_control.elf \
  > edgescope_runtime_control_readelf.txt
"${objdump}" -d -S \
  edgescope_runtime_control.elf \
  > edgescope_runtime_control_disassembly.txt
"${nm}" -n \
  edgescope_runtime_control.elf \
  > edgescope_runtime_control_symbols.txt
"${nm}" -u \
  edgescope_runtime_control.elf \
  > edgescope_runtime_control_undefined.txt
"${size}" -A -x \
  edgescope_runtime_control.elf \
  > edgescope_runtime_control_size.txt

elf_class="$("${readelf}" -h edgescope_runtime_control.elf |
  awk -F: '/Class:/ {gsub(/^[[:space:]]+/, "", $2); print $2}')"
elf_machine="$("${readelf}" -h edgescope_runtime_control.elf |
  awk -F: '/Machine:/ {gsub(/^[[:space:]]+/, "", $2); print $2}')"
elf_entry="$("${readelf}" -h edgescope_runtime_control.elf |
  awk '/Entry point address:/ {print $4}')"

if [[ "${elf_class}" != "ELF32" ]]; then
  echo "ERROR: expected ELF32, got ${elf_class}" >&2
  exit 1
fi
if [[ "${elf_machine}" != "RISC-V" ]]; then
  echo "ERROR: expected RISC-V machine, got ${elf_machine}" >&2
  exit 1
fi
if (( elf_entry != 0 )); then
  echo "ERROR: expected entry point 0x0, got ${elf_entry}" >&2
  exit 1
fi
if [[ -s edgescope_runtime_control_undefined.txt ]]; then
  echo "ERROR: unresolved symbols are present:" >&2
  sed -n '1,80p' edgescope_runtime_control_undefined.txt >&2
  exit 1
fi

load_count=0
while read -r segment_type segment_offset segment_vaddr segment_paddr \
              segment_filesz segment_memsz segment_flags_rest; do
  [[ "${segment_type}" == "LOAD" ]] || continue
  load_start=$((segment_paddr))
  load_size=$((segment_memsz))
  load_end=$((load_start + load_size))
  if (( load_start < 0 || load_end > 0x00020000 )); then
    echo "ERROR: LOAD segment lies outside BRAM: start=${segment_paddr}" \
         "size=${segment_memsz}" >&2
    exit 1
  fi
  load_count=$((load_count + 1))
done < <("${readelf}" -lW edgescope_runtime_control.elf |
         awk '$1 == "LOAD" {print}')

if (( load_count == 0 )); then
  echo "ERROR: ELF contains no LOAD segment" >&2
  exit 1
fi

if ! "${readelf}" -A edgescope_runtime_control.elf |
     grep -Eq 'rv32i([0-9p_]|")'; then
  echo "ERROR: ELF attributes do not identify an RV32I image" >&2
  exit 1
fi

sha256sum \
  edgescope_runtime_control.elf \
  edgescope_runtime_control.bin \
  edgescope_runtime_control.map \
  edgescope_runtime_control_disassembly.txt \
  edgescope_runtime_control_readelf.txt \
  edgescope_runtime_control_symbols.txt \
  edgescope_runtime_control_size.txt \
  > SHA256SUMS

{
  echo "EdgeScope-Lite Step 6 Runtime Firmware Build Manifest"
  echo "===================================================="
  echo "Compiler             : $("${cc}" --version | head -n 1)"
  echo "Architecture flags   : -march=rv32i_zicsr_zifencei -mabi=ilp32"
  echo "Relaxation           : disabled at compile and link"
  echo "Standard library     : none (-nostdlib -nostartfiles)"
  echo "ELF class            : ${elf_class}"
  echo "ELF machine          : ${elf_machine}"
  printf 'Entry point          : 0x%08X\n' "$((elf_entry))"
  echo "BRAM range           : 0x00000000..0x0001FFFF"
  echo "LOAD segments checked: ${load_count}"
  echo "Undefined symbols    : 0"
  echo
  "${size}" edgescope_runtime_control.elf
} > edgescope_runtime_control_manifest.txt

echo "RUNTIME_CONTROL_BUILD: PASS"
echo "ELF      : ${build_dir}/edgescope_runtime_control.elf"
echo "Manifest : ${build_dir}/edgescope_runtime_control_manifest.txt"
