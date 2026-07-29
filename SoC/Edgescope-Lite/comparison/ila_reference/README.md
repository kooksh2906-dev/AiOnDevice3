# Vivado ILA 비교군

담당: 윤형욱
도구: Vivado 2024.2
보드: Digilent Basys 3 (`xc7a35tcpg236-1`)

## 단계 진행표

| 단계 | 내용 | 상태 |
|---:|---|---|
| 1 | 공통 Base SoC 생성·검증 | 완료 |
| 2 | 공통 Test Pattern Generator 구현·연결 | 완료 |
| 3 | Vivado ILA 추가 및 1,024-depth 설정 | 완료 |
| 4 | Trigger 조건 3종 설정 | 완료 — Step 6 Hardware Readback PASS |
| 5 | 합성·구현·Bitstream 생성 | 완료 — Step 6 Program PASS |
| 6 | Hardware Manager 기능 시험 | 완료 — 보드 실측 4종 PASS |
| 7 | CSV Export 및 정규화 | 완료 — 3종 무손실 변환·검산 PASS |
| 8 | Pulse Stress 시험 | 완료 — 6개 폭 × 10회, 60/60 검출 PASS |
| 9 | 자원·Timing 비교표 작성 | 완료 — Baseline·CPU·ILA 검증 PASS, Custom 전체 Routed 보고서 대기 |
| 10 | 증거 자료와 발표 결과 정리 | 진행 — 검증된 Draft PASS, Custom 공식 수치 대기 |

## Step 1 결과

공통 Base SoC Source:

```text
comparison/common/base_soc.tcl
```

포함된 공통 Block:

- MicroBlaze V, I/D Cache 비활성화
- 128 KiB Local Memory
- AXI Interconnect 2.1
- AXI Interrupt Controller
- AXI UART Lite, 9,600 baud, 8-N-1
- AXI Timer, 32-bit Dual Timer
- 공통 Generator 제어용 AXI GPIO
- Clocking Wizard 100 MHz 및 Processor System Reset

Step 1 Base Source에서 의도적으로 제외한 Block:

- Vivado ILA
- Probe Sampler / Basic Trigger Engine / Circular Trace Buffer
- Capture BRAM / AXI BRAM Controller
- Test Pattern Generator RTL — 아래 Step 2 Source로 추가

`base_soc.tcl`은 Validate Design뿐 아니라 FPGA Part, IP 개수, Cache,
BRAM 깊이, UART·Timer·GPIO 설정, Interrupt 입력 수, Clock/Reset Net,
주소 범위를 자동 검사한다.

## Step 2 결과

공통 Generator Source:

```text
comparison/common/rtl/test_pattern_generator.sv
comparison/common/rtl/test_pattern_generator_gpio_adapter.v
```

`test_pattern_generator_gpio_adapter`는 공통 AXI GPIO와 다음처럼 연결된다.

| AXI GPIO | Generator | 기능 |
|---|---|---|
| Channel 1 Output `[25:0]` | `control_i[25:0]` | START, Test ID, Pulse 폭, CLEAR |
| Channel 2 Input `[1:0]` | `status_o[1:0]` | BUSY, DONE |

`probe_test_o[7:0]`는 세 비교군이 함께 사용하는 시험 신호다. Step 2에서는
의도적으로 연결하지 않았으며, Step 3에서 Vivado ILA의 Probe에 연결한다.

### Test ID

| ID | 시험 | 파형 |
|---:|---|---|
| `0x0` | Safe / Benchmark | START 거부, Probe/Status 유지 |
| `0x1` | P-01 Rising | `0x00 → 0x01` |
| `0x2` | P-02 Falling | `0x01 → 0x00` |
| `0x3` | P-03 Pattern | `0x95 → 0xA5` |
| `0x4` | P-04 Pattern Hold | `0x95 → 0xA5`, 10 ms 유지 |
| `0x5` | P-05 No Trigger | `0x00`, START부터 100 ms 유지 |
| `0x6` | Pulse Stress | `0x00 → 0x01 → 0x00` |
| `0x7~0xF` | Reserved | START 거부, Probe/Status 유지 |

ID `0x0`과 Reserved ID는 START를 무시하므로 RESET/CLEAR 직후의 안전값
`0x00`을 바꾸지 않는다. 이전 시험이 DONE인 경우에는 CLEAR 전까지 이전
Post-event 값을 그대로 유지한다. ID `0x3`과 `0x4`는 파형이 같으며,
결과 Log에서 두 시험 목적을 구분하기 위한 별도 ID다.

100 MHz 기준 ID `0x1~0x4`, `0x6`은 START 수락 후 정확히
1,000,000 Clock(10 ms)을 기다려 Event를 만들고, Event 후 1,000,000 Clock
동안 상태를 유지한다. ID `0x5`는 이 Pre-event 구간 없이 START부터
10,000,000 Clock 동안 `0x00`을 유지한다. Pulse Stress는 선택한 `W` Clock
동안 High이며 `W=0`은 1 Clock으로 보정한다. DONE은 CLEAR 전까지 유지된다.
`reset_n_i`는 100 MHz Clock에 동기식인 Active-low Reset이다.

### Source 동등성

```text
Common Git Commit: PENDING (현재 Source가 아직 Commit되지 않음)

test_pattern_generator.sv
SHA-256: 9f0a1b7f9a54ddc8f9eb3e093382af9eb6a6cdf8c9ab48ab4ce65d83e7eb5440

test_pattern_generator_gpio_adapter.v
SHA-256: 73fd657010c8109d5a1c7e5168d4ae4a4d576fc80e2ddd02978b087523249580
```

공식 Hardware 시험 전에 공통 Source Commit을 만든 뒤 PENDING을 실제
Commit ID로 교체한다.

### Step 2 검증

- 빠른 전체 기능 Regression: PASS
- 실제 동결 Timing Regression: PASS
  - Pre/Post 각각 1,000,000 Clock
  - P-05 10,000,000 Clock
  - 공식 Pulse 폭 1, 10, 100, 1,000, 10,000, 100,000 Clock
- Vivado 2024.2 Clean Rebuild 및 Validate Design: PASS
- Generator 단독 Mixed-language Synthesis: Error 0, Critical Warning 0
- 단독 합성 참고값: Slice LUT 111, Slice Register 65, BRAM/DSP 0

단독 합성값에는 Top-level I/O Buffer가 포함되며 최종 시스템 자원값이 아니다.
공식 비교 자원은 이후 동일 Base SoC에서 Implementation까지 마친 뒤 측정한다.

## Step 3 결과

Vivado ILA Reference Source:

```text
comparison/ila_reference/add_vivado_ila.tcl
comparison/ila_reference/build_step3_ila.tcl
```

Step 3에서 공통 Generator 출력에 Native Vivado ILA 6.2를 직접 연결했다.

```text
clk_wiz/clk_out1 (100 MHz)
    ├─ Test Pattern Generator / clk_i
    └─ ila_reference_0 / clk

Test Pattern Generator / probe_test_o[7:0]
    └─ ila_reference_0 / probe0[7:0]
```

### 동결 ILA 구조

| 항목 | 동결값 |
|---|---:|
| IP | Vivado ILA 6.2 |
| Monitor Type | Native |
| ILA 개수 | 1 |
| Probe 개수 | 1 |
| Probe 폭 | 8-bit |
| Probe Type | Data and Trigger |
| Match Unit | 1 |
| Capture Depth | 1,024 Samples |
| Clock | Generator와 동일한 100 MHz Net |
| Input Pipeline | 0 Stage |
| Advanced Trigger | Disabled |
| Storage Qualification | Disabled |
| TRIG_IN / TRIG_OUT | Disabled / Disabled |

Vivado 2024.2에서는 새 ILA가 AXI Monitor와 다수 Probe로 시작할 수 있으므로
`C_MONITOR_TYPE=Native`, `C_NUM_OF_PROBES=1`을 Tcl에 명시했다. Probe는
`probe_test_o[7:0]` 하나뿐이며 BUSY, DONE, AXI 신호 등은 추가하지 않았다.

### 512:512 Capture Geometry

Step 3에서 Hardware 최대 깊이 `C_DATA_DEPTH=1024`를 고정했다. Step 4의
Hardware Manager 공통 설정은 다음 값으로 고정한다.

```text
CONTROL.DATA_DEPTH       = 1024
CONTROL.WINDOW_COUNT     = 1
CONTROL.TRIGGER_POSITION = 512
CONTROL.CAPTURE_MODE     = ALWAYS
CONTROL.TRIGGER_MODE     = BASIC_ONLY
```

Trigger Position 512의 정규화 의미:

```text
Index   0~511  : Trigger 직전 512 Samples
Index     512  : Trigger Sample
Index 513~1023 : Trigger 이후 추가 511 Samples
```

즉 Post-trigger 512개는 Trigger Sample을 포함한다. `C_DATA_DEPTH=1024`만으로
Trigger Position 512가 자동 설정되는 것은 아니므로, 위 Runtime 값은 Step 4
Tcl에서 설정하고 Bitstream 생성 후 Hardware Manager에서 Readback한다.

Hardware 시험의 실행 순서는 다음으로 고정한다.

```text
run_hw_ila
→ Pre-trigger 512개가 채워짐
→ ILA 상태가 Waiting for Trigger인지 확인
→ UART RUN
→ MicroBlaze가 Generator START
```

P-05 No-trigger 시험에서 ILA 비교값의 Mask를 `0x00`으로 두면 모든 Bit가
Don't-care로 해석돼 즉시 Trigger될 수 있다. ILA는 Generator가 만들지 않는
`probe0 == 0xFF` 같은 불가능 조건을 사용해 100 ms 동안 Trigger가 없음을
확인한다. 이때 강제로 중단한 Partial Capture를 정상 1,024-Sample 결과로
취급하지 않는다.

### Step 3 자동 검증 결과

- Step 1부터 시작하는 Clean Rebuild: PASS
- Validate Design: PASS
- Native ILA 6.2 정확히 1개: PASS
- Probe 1개, 8-bit, Data and Trigger: PASS
- Capture Depth 1,024, Input Pipeline 0: PASS
- ILA와 Generator의 100 MHz Clock Net 일치: PASS
- `probe_test_o[7:0]`와 `probe0[7:0]` Net 일치: PASS
- 기존 Base Block, 주소, 외부 Port 불변: PASS
- System ILA, VIO, CPU Probe GPIO, Custom Analyzer IP 없음: PASS
- 모든 Project IP Status `Up-to-date`: PASS
- ILA 및 Block Design Output Product 생성: PASS

Step 3에서는 전체 합성, Implementation, Bitstream, `.ltx`, Utilization,
Timing 및 실제 Hardware Capture를 실행하지 않았다. 해당 검증은 Step 5
이후 범위다.

## Step 4 결과

Hardware Manager용 Runtime Trigger Source:

```text
comparison/ila_reference/hw/ila_trigger_control.tcl
```

### 동결 Trigger Profile

| Profile | 기능 | `TRIGGER_COMPARE_VALUE` |
|---|---|---|
| `rising` | CH0 Rising Edge | `eq8'bXXXXXXXR` |
| `falling` | CH0 Falling Edge | `eq8'bXXXXXXXF` |
| `pattern` | Pattern `0xA0`, Mask `0xF0` | `eq8'b1010XXXX` |
| `no_trigger` | P-05용 불가능 조건 `0xFF` | `eq8'hFF` |

8-bit 문자열은 CH7부터 CH0 순서이므로 CH0은 가장 오른쪽 문자다.
`RXXXXXXX` 또는 `FXXXXXXX`로 설정하면 CH7 Trigger가 되므로 사용하지 않는다.

`pattern`은 ILA의 Level Match다. 공통 파형 `0x95 → 0xA5`에서는
Nonmatch에서 Match로 진입하는 Sample이 한 번뿐이므로 CPU/Custom의
Pattern-entry 시험과 같은 Sample에서 Trigger된다. 이 결과를 임의 파형에 대한
일반 Pattern-entry Detector 구현으로 확대 해석하지 않는다.

P-05에서 `eq8'bXXXXXXXX`은 Trigger 비활성화가 아니라 항상 일치할 수 있다.
따라서 Generator가 `0x00`을 유지하는 동안 만들어질 수 없는 `0xFF`를
대체 조건으로 사용한다.

### 매 시험 강제되는 Runtime 값

```text
CONTROL.DATA_DEPTH        = 1024
CONTROL.WINDOW_COUNT      = 1
CONTROL.TRIGGER_POSITION  = 512
CONTROL.CAPTURE_MODE      = ALWAYS
CONTROL.CAPTURE_CONDITION = AND
CONTROL.TRIGGER_MODE      = BASIC_ONLY
CONTROL.TRIGGER_CONDITION = AND
CAPTURE_COMPARE_VALUE     = eq8'bXXXXXXXX
```

각 Profile을 적용하기 전에 `reset_hw_ila -reset_compare_values true`를
호출한 다음 모든 값을 다시 설정한다. 이전 GUI Session이나 Trigger Mode의
Compare 값, Position 0, Capture 조건이 다음 시험에 남는 것을 방지한다.

Hardware Manager 사용 예:

```tcl
source comparison/ila_reference/hw/ila_trigger_control.tcl

edgescope_ila::configure rising
# 또는 falling / pattern / no_trigger
```

`configure`는 다음 조건을 자동 검사한다.

- 현재 Device, ILA, ILA Probe가 각각 정확히 1개
- ILA 상태가 `IDLE`
- Static 최대 Depth 1,024
- Probe Port 0, 폭 8-bit, Comparator 1개
- 모든 Runtime Control과 Trigger/Capture Compare 값 Readback

이 함수는 `run_hw_ila`를 자동 호출하지 않는다. 설정 PASS 후 사용자가
ILA를 실행하고 `Waiting for Trigger` 상태를 확인한 다음 Generator를
시작해야 한다.

### Step 4 검증 결과

- Rising/Falling/Pattern/P-05 Profile 문자열 검사: PASS
- Vivado 2024.2 Tcl 파싱: PASS
- Step 1부터 시작하는 Clean Rebuild: PASS
- Step 3 ILA 구조 및 Depth 불변: PASS
- 오염된 이전 Control/Compare 초기화 후 재설정: PASS
- Mode 연속 전환 및 대소문자 정규화: PASS
- 잘못된 Mode, 7-bit Probe, Depth 512, Position 511 검출: PASS
- 실행 중 ILA, 복수 ILA, 복수 Probe 거부: PASS
- Mock Readback Regression: PASS

오프라인 Mock PASS는 설정 정책과 stale-state 방지 로직의 검증 결과다.
실제 Hardware Manager의 `HW_ILA/HW_PROBE` 객체에 대한 Profile 적용,
Readback과 실제 Trigger 발생은 Bitstream과 `.ltx`가 준비된 Step 6에서
최종 검증한다. Trigger Mode별로 Bitstream을 다시 합성하지 않는다.

## Step 5 결과

재현 가능한 Build Source:

```text
comparison/ila_reference/implement_step5_bitstream.tcl
comparison/ila_reference/constraints/ila_debug_hub.xdc
comparison/ila_reference/run_step5_build.sh
```

Step 5에서 잘못 자동 선택되어 있던 Generator Adapter 단독 Top을 막기 위해
Block Design Wrapper를 Project Source로 가져오고 Top을
`base_soc_wrapper`로 강제한다. 따라서 합성 대상은 Generator만이 아니라
MicroBlaze V, 공통 주변장치, Generator, ILA를 모두 포함한 전체 SoC다.

자동 삽입되는 Debug Hub는 실제 연결된 100 MHz Clock과 일치하도록
`C_CLK_INPUT_FREQ_HZ=100000000`으로 고정했다. 구현 과정에서 생성된
`dbg_hub_stub.v`도 100 MHz 설정을 다시 읽어 검사한다. Basys 3의 구성 Bank
전압은 `CFGBVS=VCCO`, `CONFIG_VOLTAGE=3.3`으로 명시했다.

### 구현 Sign-off

| 항목 | 결과 |
|---|---:|
| Synthesis | PASS, Error 0 / Critical Warning 0 |
| Implementation | PASS, Fully Placed / Fully Routed |
| Route Error | 0 |
| WNS / TNS | `+1.544 ns` / `0.000 ns` |
| WHS / THS | `+0.014 ns` / `0.000 ns` |
| WPWS / TPWS | `+3.000 ns` / `0.000 ns` |
| 내부 Unconstrained Endpoint | 0 |
| CDC | 동기화된 Info 15건 / 비정상 0건 |
| Debug Hub Bus Skew | 4/4 MET |
| Post-route DRC Error / Critical | 0 / 0 |
| System / ILA / Debug Hub Clock | 100 MHz / 100 MHz / 100 MHz |
| ILA | 1개, 8-bit Probe 1개, Depth 1,024 |

`check_timing`의 외부 I/O 지연 알림은 `reset`, `usb_uart_rxd`,
`usb_uart_txd` 3개다. Reset과 UART는 외부 동기식 병렬 인터페이스가 아니므로
근거 없는 Input/Output Delay를 임의로 추가하지 않았다. 내부 Register/Latch의
미제약 Clock 및 Maximum-delay Endpoint는 0개다.

남은 DRC Warning 14건은 모두 AMD 생성 IP 내부 항목이다. Debug Hub 계층
4건(`PDCN-1569` 3건, `RTSTAT-10` 1건), ILA 관련 PDRC 6건,
MicroBlaze V 관련 PDRC 4건이며 Custom Generator RTL 관련 경고는 없다.
Bitstream 생성을 차단하는 Error와 Critical Warning은 모두 0이고 Bitgen도
성공했다. 상세 Rule과 개수는 `ila_reference_step5_drc.rpt`에 보관한다.

Methodology Report의 `TIMING-9` 1건은 Clock Domain Crossing을
추가 확인하라는 일반 Advisory다. 별도 `report_cdc -details` 결과에서는 모든
15개 Crossing이 `ASYNC_REG` 동기화가 확인된 Info이고 Warning/Critical/Error는
0건이다. 이 CDC Report도 Step 5 PASS Gate와 산출물에 포함한다.

### 구현 자원

| Resource | 사용 | Basys 3 전체 | 사용률 |
|---|---:|---:|---:|
| Slice LUT | 3,726 | 20,800 | 17.91% |
| Slice Register | 4,230 | 41,600 | 10.17% |
| Block RAM Tile | 32.5 | 50 | 65.00% |
| Bonded IOB | 4 | 106 | 3.77% |
| BUFGCTRL | 7 | 32 | 21.88% |
| MMCM | 1 | 5 | 20.00% |

### 생성 산출물

```text
comparison/ila_reference/build/step5/
├── edgescope_ila_reference_routed.dcp
├── edgescope_ila_reference.bit
└── debug_nets.ltx

comparison/ila_reference/generated/
├── ila_reference_step5_build_manifest.rpt
├── ila_reference_step5_timing_summary.rpt
├── ila_reference_step5_check_timing.rpt
├── ila_reference_step5_bus_skew.rpt
├── ila_reference_step5_drc.rpt
├── ila_reference_step5_utilization.rpt
├── ila_reference_step5_hierarchical_utilization.rpt
├── ila_reference_step5_route_status.rpt
├── ila_reference_step5_debug_cores.rpt
├── ila_reference_step5_cdc.rpt
├── ila_reference_step5_io.rpt
├── ila_reference_step5_clocks.rpt
├── ila_reference_step5_clock_utilization.rpt
├── ila_reference_step5_methodology.rpt
└── ila_reference_step5_SHA256SUMS
```

`.bit`와 `.ltx`는 같은 Open Routed Design에서 연속 생성되며 Manifest에
Routed DCP, BIT, LTX의 SHA-256을 함께 기록한다. Step 6에서는 반드시 이 두
파일을 한 쌍으로 사용한다.

공식 진입점인 `run_step5_build.sh`는 Step 1~4 프로젝트를 다시 만든 뒤
Synthesis와 Implementation을 처음부터 실행한다. Manifest에는 Base SoC,
Generator, ILA, Trigger, XDC, Runner, Bootloop ELF, Wrapper를 포함한 Build
입력의 SHA-256을 기록한다. 현재 작업물이 아직 Commit되지 않아
`Git Worktree Dirty=true`인 사실도 그대로 남기므로, 팀 Release 시에는
Commit 후 같은 Runner를 한 번 더 실행해야 한다.

최종 검증에서는 이 공식 진입점을 실제로 실행했고 Resume 없이 `synth_1`과
`impl_1`을 새로 완료했다. Canonical Log는
`build/step5/implement_step5.log`이며 마지막 판정은
`VIVADO_ILA_STEP_5: PASS`다.

Step 5 원본 Bitstream의 MicroBlaze BRAM에는 `riscv_bootloop.elf`가 들어 있다.
Step 6에서는 동일한 Routed Design의 BRAM 내용만 Runtime Control Firmware로
교체한다. ILA Hardware, 배치·배선 및 `.ltx`는 바꾸지 않는다.

## Step 6 결과

### Runtime Firmware와 Hardware Pair

UART `RUN`으로 공통 Generator를 시작하는 RV32I/ILP32 Bare-metal
Firmware를 구현했다.

```text
comparison/ila_reference/sw/runtime_control/
├── startup.S
├── linker.ld
├── runtime_control.c
├── build.sh
└── build/edgescope_runtime_control.elf
```

- Entry Point: `0x0000_0000`
- Local BRAM: `0x0000_0000~0x0001_FFFF`
- libc 및 미해결 Symbol: 0
- Load 크기: 3,241 Bytes
- 명령: `PING`, `STATUS`, `CLEAR`, `RUN 1~6 [pulse]`, `HELP`
- ELF SHA-256:
  `7cd731b725da46489b0670666f234ee521771b3faf0b205f188866cf89150934`

`build_step6_runtime_bit.sh`는 Step 5 전체 Checksum을 먼저 검사한 뒤,
Routed DCP에서 MMI를 추출하고 `updatemem`으로 Firmware만 BRAM에 주입한다.
전체 합성·Implementation을 다시 실행하지 않는다. `updatemem`이 BIT Container
Header에 기록하는 실행 시각만 Step 5 값으로 정규화하고 FPGA Configuration
Payload가 변하지 않았음을 검사하므로, 같은 입력에서는 같은 SHA-256이 나온다.

```bash
comparison/ila_reference/build_step6_runtime_bit.sh
```

생성된 공식 Step 6 Pair:

```text
comparison/ila_reference/build/step6/
├── edgescope_ila_reference_runtime.bit
├── debug_nets.ltx
├── edgescope_ila_reference_runtime.mmi
├── runtime_pair_manifest.rpt
└── SHA256SUMS
```

| 파일 | SHA-256 |
|---|---|
| Runtime BIT | `cd9d25d4aa3556690876be3c5a94a581e7c6299935664679f7500e83ef8f5acf` |
| LTX | `ad8b65ba6078aa52ea718c743ca12b75e2bd5e832b860145ec0aa19c36100b9b` |

LTX는 Step 5와 완전히 같고 Runtime BIT는 Bootloop BIT와 다르다. Packaging
결과는 `STEP6_RUNTIME_BIT: PASS`, Hardware 입력 Dry-run은
`EDGESCOPE_STEP6: PASS`다.

### Hardware Manager 자동화

```text
comparison/ila_reference/hw/run_step6_hardware.tcl
comparison/ila_reference/hw/run_step6_hardware.sh
comparison/ila_reference/host/uart_runtime_control.py
```

Hardware Runner는 다음을 자동 검사한다.

- Runtime BIT/LTX Manifest와 실제 SHA-256
- FPGA Part 및 Hardware Target의 유일성
- Program 후 DONE/EOS와 BIT/LTX 경로 Readback
- ILA 1개, Probe 1개, 8-bit, Port 0, Comparator 1개, Depth 1,024
- Rising/Falling/Pattern/No-trigger Profile과 Trigger Position 512 Readback
- `trigger_now` 금지 및 `WAITING_FOR_TRIGGER` 확인 후에만 UART `RUN`
- P-05에서 100 ms 동안 Waiting 유지, Partial Capture 저장 금지

오프라인 입력 검증:

```bash
comparison/ila_reference/hw/run_step6_hardware.sh dry_run
```

보드 연결 후 Pair Readback:

```bash
EDGESCOPE_HW_TARGET_PATTERN='*/Digilent/210183BEA180A' \
  comparison/ila_reference/hw/run_step6_hardware.sh pair
```

기능 Capture는 첫 Terminal에서 실행하고 `WAITING_FOR_TRIGGER`가 표시된 뒤
두 번째 Terminal에서 같은 Profile의 UART 명령을 보낸다.

```bash
# Terminal 1
EDGESCOPE_HW_TARGET_PATTERN='*/Digilent/210183BEA180A' \
  comparison/ila_reference/hw/run_step6_hardware.sh capture rising

# Terminal 2
python3 comparison/ila_reference/host/uart_runtime_control.py \
  run rising --port /dev/ttyUSB1
```

`falling`, `pattern`, `no_trigger`도 같은 방식이다. 실제 UART Port 이름은
다음 명령으로 확인한다.

```bash
python3 comparison/ila_reference/host/uart_runtime_control.py list
```

연결된 Basys 3는 USB `0403:6010`, UART `/dev/ttyUSB1`로 확인했고
`PING`은 `OK PONG`을 반환했다. 이 환경에서는 같은 물리 보드가 Digilent와
Xilinx 두 Target 경로로 열거되므로, 기본 중복 거부 정책은 유지한 채 위와
같이 성공한 Digilent Target을 명시적으로 선택했다.

실제 Hardware Manager 결과:

| 시험 | 실측 결과 | 판정 |
|---|---|---|
| Pair Program/Readback | ILA 1개, Probe 8-bit, Depth 1,024, Position 512 | PASS |
| Rising | Sample 511 `0x00`, Trigger Sample 512 `0x01` | PASS |
| Falling | Sample 511 `0x01`, Trigger Sample 512 `0x00` | PASS |
| Pattern | Sample 511 `0x95`, Trigger Sample 512 `0xA5` | PASS |
| No-trigger | 103 ms Waiting, Partial Capture 0 | PASS |

세 기능 Capture는 각각 정확히 1,024개 Sample과 Sample 512의 단일 Trigger
Marker를 포함한다. 다음 명령은 CSV, `.ila` SHA-256, Pair Readback 및
No-trigger 보고서를 함께 재검산한다.

```bash
python3 comparison/ila_reference/host/validate_step6_capture_results.py
```

최종 결과는
`comparison/ila_reference/results/step6/capture_validation.rpt`와
`step6_status.rpt`에 기록되어 있으며 Step 6 전체 판정은 `PASS`다.

## Step 7 결과

Step 6 Vivado 원본 CSV의 Header와 `Radix - ...` 행을 제거하고, 팀 공통
Frozen v1.1 비교 형식으로 정규화했다.

```csv
index,value_hex,is_trigger,ch7,ch6,ch5,ch4,ch3,ch2,ch1,ch0
```

- Logical Index: `0~1023`, Oldest → Newest
- Trigger Index: `512`
- `value_hex`: `0x` 접두사 없는 2자리 대문자 Hex
- `is_trigger`: Index 512만 `1`
- `ch7~ch0`: MSB → LSB이며 `value_hex`와 재조합 일치
- 공통 계약에 없는 시간 Column은 추가하지 않음

공식 실행:

```bash
comparison/ila_reference/run_step7_normalization.sh
```

이 Runner는 Step 6 상태, Pair Readback, 원본 CSV/ILA Hash, 공통 Generator
Hash를 먼저 확인한 뒤 변환하고, 독립 Validator와 최종 SHA-256 검사를
수행한다.

| Profile | 행 수 | Trigger | 경계값 | SHA-256 | 판정 |
|---|---:|---:|---|---|---|
| Rising | 1,024 | 512 | `00 → 01` | `b14c91f9f9c580c1c05a97a9a4a35aabe74b107d4e9334023ee92f51e3851a71` | PASS |
| Falling | 1,024 | 512 | `01 → 00` | `60df25ce4f3b7bd16481829ee16aa1896e1b2fff4be90062026645f3c58a1786` | PASS |
| Pattern | 1,024 | 512 | `95 → A5` | `1860ab5295dbb1ef4f6c2953d8cf06d825e0064744b4570909313b448fdc2d01` | PASS |

```text
comparison/ila_reference/results/step7/
├── rising_normalized.csv
├── falling_normalized.csv
├── pattern_normalized.csv
├── normalization_manifest.rpt
├── normalization_validation.rpt
├── step7_status.rpt
└── SHA256SUMS
```

No-trigger는 완전한 Capture가 없는 것이 정상 결과이므로 가짜
`no_trigger_normalized.csv`를 만들지 않는다. Step 6의 103 ms Waiting 및
Partial Capture 0 증거를 Manifest에 연결했다.

정규화 CSV는 세 비교군의 값·순서·논리 Trigger 위치 비교용이다. CPU
Polling Observation을 ILA의 100 MHz 등간격 Sample과 같은 시간축으로
해석하거나 UART와 JTAG 전송속도를 비교하지 않는다. ILA Pattern Level
Match와 CPU/Custom Pattern Entry는 동결 파형 `0x95 → 0xA5`에서만 같은
Trigger Sample을 만든다. P-04 Pattern Hold는 별도 실측하지 않았으며
P-03 결과를 복제해 표시하지 않는다.

## Step 8 결과

Test ID `0x6` Pulse Stress를 100 MHz 실기기에서 다음 조건으로 측정했다.
FPGA는 한 번만 Program하고, 각 시험마다 ILA를 새로 Reset·설정·Arm한 뒤
`WAITING_FOR_TRIGGER`를 확인하고 UART `RUN 6 <pulse_width>`를 보냈다.
각 Pulse 폭당 유효 시험 10회, 총 60회를 수행했으며 강제 Trigger,
`trigger_now`, Timeout 뒤 Partial Capture는 사용하지 않았다.

| Pulse 폭 | 시간 | 유효 시험 | ILA 검출 | 검출률 | Capture 파형 판정 |
|---:|---:|---:|---:|---:|---|
| 1 Clock | 10 ns | 10 | 10 | 100% | High `512`, 첫 Low `513` |
| 10 Clock | 100 ns | 10 | 10 | 100% | High `512~521`, 첫 Low `522` |
| 100 Clock | 1 µs | 10 | 10 | 100% | High `512~611`, 첫 Low `612` |
| 1,000 Clock | 10 µs | 10 | 10 | 100% | `512~1023` High, 하강은 창 밖 |
| 10,000 Clock | 100 µs | 10 | 10 | 100% | `512~1023` High, 하강은 창 밖 |
| 100,000 Clock | 1 ms | 10 | 10 | 100% | `512~1023` High, 하강은 창 밖 |

모든 Capture에서 Index `0~511`은 `0x00`, Trigger Index `512`는
`0x01`이며 Trigger Marker는 하나다. 1·10·100 Clock 시험은 Capture 안의
정확한 High Sample 수와 첫 Low 위치까지 확인했다. 1,000 Clock 이상은
고정된 512:512 Capture 창보다 길기 때문에 실제 Pulse 종료 시점을 측정했다고
표현하지 않고, Rising 검출과 창 끝까지 High인 사실만 합격 기준으로 삼았다.

공식 자동 실행:

```bash
EDGESCOPE_HW_TARGET_PATTERN='*/Digilent/210183BEA180A' \
EDGESCOPE_UART_PORT=/dev/ttyUSB1 \
  comparison/ila_reference/hw/run_step8_pulse_stress.sh capture
```

Hardware 없이 저장된 증거만 다시 검사:

```bash
comparison/ila_reference/hw/run_step8_pulse_stress.sh --validate-only
```

Step 8 전용 Source:

```text
comparison/ila_reference/hw/run_step8_pulse_stress.tcl
comparison/ila_reference/hw/run_step8_pulse_stress.sh
comparison/ila_reference/host/validate_step8_pulse_stress.py
```

검증 산출물:

```text
comparison/ila_reference/results/step8/
├── hardware_session.log         # 공식 60회 Hardware Manager 실행 기록
├── raw/                         # Vivado 원본 CSV 60개
├── ila/                         # Vivado ILA 세션 60개
├── trials/                      # 회차별 UART/ILA 증거 60개
├── normalized/                  # 공통 형식 CSV 60개
├── pulse_detection.csv          # 전체 60회 판정
├── pulse_detection_summary.csv  # 폭별 검출률
├── pulse_stress_validation.rpt  # 파형·계약 검증
├── pulse_stress_manifest.rpt    # 입력 및 산출물 추적
├── step8_status.rpt             # 최종 PASS 상태
└── SHA256SUMS                   # 공식 증거 무결성
```

최종 판정은 Pulse 폭 6종 모두 `10/10`, 전체 `60/60`, 검출률
`100.0%`이며 `PARTIAL_CAPTURE_COUNT=0`, `FPGA_PROGRAM_COUNT=1`이다.
원본·정규화 파형, ILA 세션, UART 응답, 실행 순서와 전체 SHA-256을 독립
Validator로 다시 확인했고 Step 8 전체 판정은 `PASS`다.

## Step 9 진행 결과

자원·Timing 비교는 세 방식 모두 Basys 3 `xc7a35tcpg236-1`, Vivado 2024.2,
100 MHz(`10.000 ns`), 기본 Synthesis/Implementation Strategy로 끝까지
구현한 전체 `base_soc_wrapper`의 Routed Report만 공식 입력으로 사용한다.
IP 단독 OOC 또는 Subsystem Synthesis 수치는 아래 전체 시스템 합계와
혼합하지 않는다.

### 비교 입력 상태

| 입력 | 현재 상태 | 공식 비교 사용 |
|---|---|---|
| Common Base + Generator | 별도 Clean Build 전체 Routed 검증 완료 | 공식 Delta 기준 |
| CPU Polling | Drive Routed Report 수신·로컬 원본 보존·필수 필드 검증 완료 | Total/참고용 Delta 산출 완료 |
| Vivado ILA | 전체 Routed 자원·Timing 검증 완료 | Total/공식 비교용 Delta 산출 완료 |
| Custom Circular Trace Buffer | `NOT_RECEIVED` — 전체 Routed Report 미수신 | 아직 사용 불가 |

CPU Polling 원본 보고서와 출처 Manifest는 다음 위치에 복사해 보존했다.

```text
comparison/ila_reference/results/step9/inputs/cpu_polling/
```

Clean Common Build는 Step 3~5의 ILA가 들어 있던 기존 프로젝트를 Baseline으로
재사용하지 않고, 동결된 공통 Base와 Generator만 분리해 다시 구현했다.
아래 표는 자동 검증을 통과한 전체 Routed **Total**을 표시한다.

### 전체 Routed Total

| 방식 | Slice LUT | LUT as Logic | LUT as Memory | LUTRAM | SRL | Slice Register | RAMB36 | RAMB18 | DSP48E1 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Common Baseline | 2,685 | 2,547 | 138 | 96 | 42 | 2,455 | 32 | 0 | 0 |
| CPU Polling | 2,782 | 2,644 | 138 | 96 | 42 | 2,560 | 32 | 0 | 0 |
| Vivado ILA | 3,726 | 3,500 | 226 | 120 | 106 | 4,230 | 32 | 1 | 0 |
| Custom | `NOT_RECEIVED` | `NOT_RECEIVED` | `NOT_RECEIVED` | `NOT_RECEIVED` | `NOT_RECEIVED` | `NOT_RECEIVED` | `NOT_RECEIVED` | `NOT_RECEIVED` | `NOT_RECEIVED` |

RAMB36와 RAMB18은 서로 다른 자원이므로 공식 표에서는 분리한다. 참고용
Block RAM Tile 환산값 `RAMB36 + 0.5 × RAMB18`은 Common Baseline과
CPU Polling `32.0`, Vivado ILA `32.5`지만 이 환산값으로 원래 두 열을
대체하지 않는다.

### 전체 Routed Timing

| 방식 | WNS | TNS | WHS | THS | WPWS | TPWS | 판정 |
|---|---:|---:|---:|---:|---:|---:|---|
| Common Baseline | `+1.313 ns` | `0.000 ns` | `+0.033 ns` | `0.000 ns` | `+3.000 ns` | `0.000 ns` | 100 MHz Timing MET |
| CPU Polling | `+0.939 ns` | `0.000 ns` | `+0.047 ns` | `0.000 ns` | `+3.000 ns` | `0.000 ns` | 100 MHz Timing MET |
| Vivado ILA | `+1.544 ns` | `0.000 ns` | `+0.014 ns` | `0.000 ns` | `+3.000 ns` | `0.000 ns` | 100 MHz Timing MET |
| Custom | `NOT_RECEIVED` | `NOT_RECEIVED` | `NOT_RECEIVED` | `NOT_RECEIVED` | `NOT_RECEIVED` | `NOT_RECEIVED` | 판정 불가 |

WNS는 동결된 100 MHz 제약에서 Timing을 만족하는지 확인하는 값이다. 이
WNS만으로 각 설계의 최대 동작 주파수(Fmax)를 계산하거나 순위를 매기지 않는다.

### ILA와 Debug Hub 계층 구분

Vivado ILA 방식의 전체 합계에는 사용자가 추가한 ILA IP뿐 아니라 Vivado가
통신을 위해 자동 삽입한 Debug Hub도 포함된다.

| 계층 | Total LUT | LUT as Logic | LUT as Memory/SRL | Slice Register | RAMB18 |
|---|---:|---:|---:|---:|---:|
| ILA IP | 591 | 527 | SRL 64 | 1,034 | 1 |
| Debug Hub | 449 | 425 | LUTRAM 24 | 741 | 0 |
| 두 계층 단순 합 | 1,040 | 952 | LUTRAM 24 + SRL 64 | 1,775 | 1 |

이 계층 수치는 어떤 Block이 자원을 사용하는지 설명하는
`Hierarchical Utilization`이며, Common Baseline을 뺀 순증가량(Delta)이
아니다. 계층 합을 ILA의 공식 추가 비용으로 표시하지 않는다.

### Total, Delta와 공식 절감률

각 방식의 전체 Routed Total과 `방식 Total - Clean Common Baseline Total`인
Delta를 별도 열로 관리한다. 음수 Delta가 나와도 임의로 0으로 보정하지
않는다.

| 방식 | Delta LUT | Delta LUT Logic | Delta LUT Memory | Delta FF | Delta RAMB36 | Delta RAMB18 |
|---|---:|---:|---:|---:|---:|---:|
| CPU Polling | +97 | +97 | 0 | +105 | 0 | 0 |
| Vivado ILA | +1,041 | +953 | +88 | +1,775 | 0 | +1 |
| Custom | `NOT_RECEIVED` | `NOT_RECEIVED` | `NOT_RECEIVED` | `NOT_RECEIVED` | `NOT_RECEIVED` | `NOT_RECEIVED` |

CPU Polling Delta는 전체 시스템 비용을 설명하기 위한 참고값일 뿐 공식
Analyzer 절감률 계산에는 쓰지 않는다.

Custom 전체 Routed Report가 수신되기 전까지 세 방식 공식 비교와
`Custom Delta` 대 `ILA Delta` 절감률은 `PENDING_CUSTOM`이다. CPU Polling은
동작 방식이 다르므로 Custom 자원 절감률 계산의 기준으로 사용하지 않는다.

Baseline은 Route `4,704/4,704`, Route Error `0`, 내부 Unconstrained
Endpoint `0`, DRC Error/Critical Warning `0/0`으로 검증됐다. CPU Polling과
Vivado ILA도 필수 자원·Timing·DRC 조건을 통과했고, ILA는 Route
`7,147/7,147`, Route Error `0`이다.

윤형욱의 ILA Step 9 산출물 상태는 `PASS_WITH_TEAM_INPUT_PENDING`이다.
즉 Baseline·CPU·ILA 비교표 작성은 완료됐고, 팀의 Custom 전체 Routed
Report가 준비된 뒤에만 세 방식 비교와 공식 Custom-vs-ILA 절감률을
확정한다.

공식 결과 파일:

```text
comparison/ila_reference/results/step9/comparison_summary.md
comparison/ila_reference/results/step9/resource_comparison.csv
comparison/ila_reference/results/step9/timing_comparison.csv
comparison/ila_reference/results/step9/resource_timing_validation.rpt
comparison/ila_reference/results/step9/step9_status.rpt
comparison/ila_reference/results/step9/SHA256SUMS
```

Clean Baseline 재생성과 Step 9 비교표 재산출:

```bash
comparison/ila_reference/run_step9_common_baseline.sh
comparison/ila_reference/run_step9_resource_timing.sh
(
  cd comparison/ila_reference/results/step9
  sha256sum -c SHA256SUMS
)
```

Custom 팀 입력은 보고서만이 아니라 실제 `routed_design.dcp`까지 포함한
7개 파일이 필요하다. 공통 SoC 계층, 12개 `check_timing` 항목, 전체
`default + bitstream_checks` DRC, DCP/보고서 Hash 계약은 아래 문서에
고정했다.

```text
comparison/ila_reference/results/step9/inputs/custom/README.md
```

## Step 10 진행 결과

Step 10은 검증된 ILA 증거를 발표용 자료로 자동 정리한다. 다만 Step 9의
Custom 전체 Routed 7개 파일이 아직 없으므로 현재 결과는
`PASS_WITH_TEAM_INPUT_PENDING` Draft다. 공식 Custom-vs-ILA 절감률을 넣은
Final 패키지는 Step 9 완료 Gate가 열린 뒤에만 생성된다.

현재 Draft 생성:

```bash
comparison/ila_reference/run_step10_final_package.sh --draft
```

Custom 입력 수신 후 Final 생성:

```bash
comparison/ila_reference/run_step9_resource_timing.sh --strict-complete
comparison/ila_reference/run_step10_final_package.sh
```

두 번째 명령은 Step 9 상태가 정확히 다음 조건을 모두 만족할 때만 통과한다.

```text
OVERALL=PASS
CUSTOM_FULL_SYSTEM=VERIFIED
THREE_WAY_COMPARISON=COMPLETE
OFFICIAL_CUSTOM_VS_ILA_SAVINGS=VERIFIED
NEXT_ACTION=STEP10_FINAL_PACKAGE
```

Step 10 산출물:

```text
comparison/ila_reference/results/step10/
├── final_summary.md
├── presentation_results.md
├── presentation_facts.csv
├── ila_result_cards.svg
├── ila_trigger_evidence.svg
├── github_repository_audit.md
├── github_remote_tests.rpt
├── github_remote_tests.log
├── team_handoff.md
├── evidence_inventory.csv
├── step10_manifest.rpt
├── step10_validation.rpt
├── step10_status.rpt
└── SHA256SUMS
```

`run_step10_github_audit.sh`는 이미 Fetch된 `origin/main`을 임시 폴더에
추출하고 Circular Buffer 7개 회귀, Basic Trigger Engine 213개 Check,
Probe Sampler 246개 Check, CPU Polling Engine 단위시험을 실행한다.
원격 파일을 작업 트리에 덮어쓰지 않는다.

## 동결 주소

| 대상 | Base | Range |
|---|---:|---:|
| Local Memory | `0x0000_0000` | 128 KiB |
| `axi_gpio_test_ctrl` | `0x4000_0000` | 64 KiB |
| AXI UART Lite | `0x4060_0000` | 64 KiB |
| AXI INTC | `0x4120_0000` | 64 KiB |
| AXI Timer | `0x41C0_0000` | 64 KiB |

## Step 1~5 재생성 및 검증

저장소 루트에서 다음을 실행한다.

```bash
/media/user4/data/tools/Vivado/2024.2/bin/vivado \
  -mode batch \
  -source comparison/ila_reference/build_step4_trigger_profiles.tcl
```

빠른 Mock Regression:

```bash
comparison/ila_reference/sim/run_step4_trigger_tests.sh
```

Step 1부터 Step 5까지 Clean Build:

```bash
comparison/ila_reference/run_step5_build.sh
```

생성되는 로컬 프로젝트:

```text
comparison/common/build/base_soc/edgescope_comparison_base.xpr
```

Git에 보관되는 검증 산출물:

```text
comparison/common/generated/base_soc_generated.tcl
comparison/common/generated/base_soc_address_map.rpt
comparison/common/generated/base_soc_with_generator_generated.tcl
comparison/common/generated/test_pattern_generator_utilization.rpt
comparison/ila_reference/generated/ila_reference_step3_generated.tcl
comparison/ila_reference/generated/ila_reference_step3_configuration.rpt
comparison/ila_reference/generated/ila_reference_step3_properties.rpt
comparison/ila_reference/generated/ila_reference_step3_ip_status.rpt
comparison/ila_reference/generated/ila_reference_step4_trigger_contract.rpt
```

참고: 제출 XSA는 Basys 3 board metadata 1.1을 사용했지만 로컬 Vivado
Board Store에는 1.2가 설치되어 있다. 두 버전은 같은 FPGA Part와
`sys_clock`, `reset`, `usb_uart` Board Interface를 사용한다.
