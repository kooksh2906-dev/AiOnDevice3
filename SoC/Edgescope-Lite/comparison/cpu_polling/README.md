# CPU Polling Reference 비교군

[`docs/team_a_cpu_polling_comparison_conditions.md`](../../docs/team_a_cpu_polling_comparison_conditions.md)의
Frozen v1.0을 구현한
MicroBlaze V + AXI GPIO Software Polling 기준 패키지다.

## 현재 상태

| 항목 | 상태 |
|---|---|
| Trigger/Ring Buffer 핵심 로직 | 구현 및 호스트 단위시험 통과 |
| Vitis 참조 앱 | Standalone BSP 및 Release `-O2` 빌드 완료 |
| CPU 전용 AXI GPIO Overlay | 공통 Base/Generator 연결 및 Vivado 2024.2 검증 완료 |
| 공통 Generator Test ID | `1:Rising, 2:Falling, 3:Pattern, 4:Hold, 5:No-trigger, 6:Pulse` |
| XSA/Bitstream/Implementation 보고서 | 생성 완료 |
| Basys 3 보드 실측 | Benchmark, P-01~P-05, Pulse Stress 완료 |

실측 원본은 `results/uart_capture.log`에 보존하며, 개별 결과 파일은 해당
로그의 Evidence Line을 가리킨다.

## 구조

```text
comparison/cpu_polling/
├── hw/
│   ├── block_design.tcl
│   ├── build_all.tcl
│   ├── constraints.xdc
│   ├── export_reports.tcl
│   └── cpu_polling_reference.xsa
├── sw/
│   ├── cpu_polling_config.h
│   ├── cpu_polling_engine.h
│   ├── cpu_polling_engine.c
│   ├── cpu_polling_reference.c
│   ├── test_cpu_polling_engine.c
│   └── Makefile
├── reports/
│   ├── utilization.rpt
│   ├── hierarchical_utilization.rpt
│   ├── timing_summary.rpt
│   ├── drc.rpt
│   └── README.md
├── results/
│   ├── polling_speed.txt
│   ├── trigger_tests.csv
│   ├── pulse_detection.csv
│   ├── uart_capture.log
│   └── a_cpu_polling_waveform.png
├── vitis/
│   ├── build_cpu_polling.py
│   └── program_bitstream.tcl
├── vitis_artifacts/
│   ├── cpu_polling_app.elf
│   └── cpu_polling_app.bit
└── README.md
```

## 구현된 비교 조건

- AXI GPIO에서 8-bit를 한 번의 32-bit volatile read로 관측
- 1,024 × 32-bit Software Ring Buffer, 유효 데이터 `word[7:0]`
- Trigger 직전 512 Observation + Trigger 포함 이후 512 Observation
- Trigger Logical Index 512
- Trigger 대기 중 Circular Overwrite
- CH0 Rising/Falling과 `pattern=0xA0`, `mask=0xF0` Pattern Entry
- Edge ARM 후 첫 Observation은 기준값으로만 사용
- Pattern은 첫 Observation부터 `match && !previous_match` 적용
- `mask=0x00`은 Trigger 금지
- AXI Timer로 GPIO read, Buffer write, Trigger 상태 갱신, Pointer 갱신을 포함한
  Analyzer Loop 측정
- Trigger Mode별 10,000 Iteration × 3회 Benchmark
- Pulse 폭 1/10/100/1,000/10,000/100,000 Clock × 10회
- Capture 완료 후에만 UART Hex Dump

## 1. 로컬 핵심 로직 검증

Vivado 없이 Ring Buffer와 Trigger 의미를 검사한다.

```bash
cd comparison/cpu_polling/sw
make test
```

검증 범위는 Ring wrap 후 Logical Index 512 정렬, 첫 Edge Observation 억제,
Rising/Falling, Pattern 최초 진입 및 유지, Zero Mask다.

## 2. 공통 Hardware 적용 및 Vivado 빌드

먼저 다음 파일과 실제 Commit ID가 존재하는지 확인한다.

```text
comparison/common/base_soc.tcl
comparison/common/rtl/test_pattern_generator.sv
```

Generator Source의 SHA-256을 기록한다.

```bash
sha256sum comparison/common/rtl/test_pattern_generator.sv
```

Vivado 2024.2에서 Overlay를 적용하고 블록 설계를 검증한다.

```bash
vivado -mode batch -source comparison/cpu_polling/hw/block_design.tcl
```

그다음 합성, 구현, Bitstream, XSA, 보고서를 한 번에 생성한다.

```bash
vivado -mode batch -source comparison/cpu_polling/hw/build_all.tcl
```

공통 Base의 Instance 이름이 기본값과 다를 때는 환경변수로 정확한 대상을
지정한다.

```bash
CPU_POLL_AXI_MASTER=microblaze_riscv_0/M_AXI_DP \
CPU_POLL_PROBE_PIN=test_pattern_generator_0/probe_test_o \
CPU_POLL_ADDR_SPACE=microblaze_riscv_0/Data \
vivado -mode batch -source comparison/cpu_polling/hw/block_design.tcl
```

Overlay는 다음을 검증한다.

- 공통 Base에 `axi_gpio_test_ctrl`이 존재
- Processor가 MicroBlaze V
- CPU 전용 `axi_gpio_probe`가 8-bit, Input-only, Interrupt disabled
- CPU 전용 GPIO 주소가 `0x4001_0000`, Range 64 KiB

`constraints.xdc`는 공통 Base의 Basys 3 Pin Mapping과 100 MHz
`sys_clock` 제약을 복제하지 않는다. 공통 Clock Wizard가 생성하는
10.000 ns 제약을 그대로 사용한다.

## 3. Vitis 2024.2 앱 구성

공통 XSA에서 Standalone Platform/Application을 만들고 다음 네 Source를 앱에
추가한다.

```text
cpu_polling_reference.c
cpu_polling_engine.c
cpu_polling_engine.h
cpu_polling_config.h
```

Build 조건:

```text
Configuration : Release
Optimization  : -O2
I/D Cache     : Disabled / Disabled
stdin/stdout  : AXI UART Lite
UART          : 9,600 baud, 8-N-1
Local Memory  : 128 KiB
```

Unified Vitis 2024.2는 Component 경로에 공백이 있으면 실패하므로 자동화
스크립트는 XSA와 Source를 `/tmp/cpu_polling_vitis_build_v2`에 스테이징한다.
빌드된 ELF는 프로젝트의 `vitis_artifacts/`로 다시 복사한다.

```bash
XILINX_VITIS_DATA_DIR=/tmp/cpu_polling_vitis_data \
vitis -s comparison/cpu_polling/vitis/build_cpu_polling.py
```

MicroBlaze V Debug Target이 XSDB에 열거되지 않는 경우에는 `updatemem`으로 ELF를
BRAM 초기값에 삽입한 `cpu_polling_app.bit`을 사용한다. 현재 보드 실측도 이
Bootable Bitstream으로 수행했다.

공통 AXI Timer의 `xparameters.h` 이름이
`XPAR_AXI_TIMER_0_BASEADDR` 또는 `XPAR_XTMRCTR_0_BASEADDR`가 아니면
`cpu_polling_config.h`의 `CPU_POLL_TIMER_BASEADDR` 선택부에 생성된 Symbol을
추가한다. Timer 주소는 임의로 추정하지 않는다.

공통 Generator의 `test_id[3:0]` 표는 다음 값으로 동결되어
`cpu_polling_config.h`에 반영되어 있다.

```c
CPU_POLL_TEST_ID_RISING       1
CPU_POLL_TEST_ID_FALLING      2
CPU_POLL_TEST_ID_PATTERN      3
CPU_POLL_TEST_ID_PATTERN_HOLD 4
CPU_POLL_TEST_ID_NO_TRIGGER   5
CPU_POLL_TEST_ID_PULSE        6
```

공통 Generator의 ID가 변경되면 세 비교군 계약을 먼저 갱신하고 이 설정도
동시에 변경한다.

## 4. UART 시험

앱 시작 후 명령:

| 명령 | 동작 |
|---|---|
| `b` | B-RISE/B-FALL/B-PATTERN을 각각 3회 측정 |
| `r` | P-01 Rising Capture + Hex Dump |
| `f` | P-02 Falling Capture + Hex Dump |
| `p` | P-03 Pattern Capture + Hex Dump |
| `h` | P-04 Pattern Hold Capture + Hex Dump |
| `z` | P-05 Zero Mask Timeout |
| `s` | 6개 Pulse 폭을 각각 10회 시험 |
| `q` | 종료 |

### GUI 시연

터미널의 긴 Hex Dump 대신 8채널 파형과 측정 결과를 브라우저 GUI에서 볼 수
있다. 보드가 없을 때는 저장된 실측 UART 로그로 즉시 시연된다.

```bash
python3 scripts/cpu_polling_gui.py
```

실시간 Basys3 연결 및 영상 촬영 방법은
[`gui/README.md`](gui/README.md)에 정리되어 있다.

Benchmark 전 Generator Clear 이후 10 ms를 기다리며, 저장된 입력이 모두
`0x00`이고 Trigger Count가 0인지 확인한다. 하나라도 다르면 해당 Trial은
`BENCHMARK_INVALID`이므로 공식 평균에서 제외하고 원인을 고친 뒤 다시 측정한다.

Pulse Trial은 Capture Pre-fill/ARM이 끝난 뒤에만 Generator START를 보내며,
Generator Done 확인 후 최소 10 ms Gap을 둔다. 검출 실패도 수정하지 않고
`detected/10`에 그대로 반영한다.

## 5. 결과와 보고서

UART 원본 로그와 실측 결과를 `results/`에 보존했다.

- Representative Polling: `1,666,666 observations/s`
- P-01 Rising: PASS, Index 511=`00`, Index 512=`01`
- P-02 Falling: PASS, Index 511=`01`, Index 512=`00`
- P-03 Pattern: PASS, Index 511=`95`, Index 512=`A5`
- P-04 Pattern Hold: PASS, Trigger Count 1
- P-05 Zero Mask: PASS, Trigger Count 0
- Pulse 1/10 cycle: `0/10`
- Pulse 100/1,000/10,000/100,000 cycle: `10/10`

Rising 캡처를 8채널 파형으로 변환한 결과는
[`results/a_cpu_polling_waveform.png`](results/a_cpu_polling_waveform.png)에서
확인할 수 있다. CPU Polling의 시간축은 대표 평균 처리량을 적용한 근사값이며,
100 MHz 등간격 Hardware Sample을 뜻하지 않는다.

`uart_capture.log`에는 네 개의 완전한
`CPU_POLLING_REFERENCE`–`CAPTURE_END` 구간과 Benchmark/Pulse 원본이 포함돼
있다.

`build_all.tcl`이 다음 보고서를 자동으로 생성한다. 구현 Run을 직접 연 경우에는
같은 보고서를 다시 내보낼 수 있다.

```tcl
source comparison/cpu_polling/hw/export_reports.tcl
```

전체 자원과 `Base SoC + AXI GPIO - Base SoC` 순증가량을 함께 기록할 수 있지만,
CPU Polling을 EdgeScope-Lite/ILA와 동급 100 MS/s Analyzer로 표현하거나 CPU를
포함한 공식 자원 절감률을 계산하지 않는다.

## 제출 전 확인

- Base SoC Commit ID 기록
- Generator Commit ID와 SHA-256 기록
- XSA와 Release `-O2` ELF 보존
- 세 Mode × 3회 Polling 속도 원본 로그 보존
- P-01~P-05와 Pulse Stress 결과에 Evidence Log 연결
- Resource Build에서 ILA/Custom Analyzer/Capture BRAM 미포함 확인
- WNS/TNS, Utilization, Hierarchical Utilization, DRC 보고서 보존
- 실측하지 않은 항목은 `PASS`가 아닌 `NOT_RUN` 유지
