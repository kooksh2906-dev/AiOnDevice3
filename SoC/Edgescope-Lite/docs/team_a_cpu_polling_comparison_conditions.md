# EdgeScope-Lite 비교 실험 — 팀원 A CPU Polling 동결 조건

- 문서 버전: Frozen v1.0
- 작성일: 2026-07-29
- 담당 비교군: CPU Polling Reference
- 상태: 비교 조건 동결, 공통 Base/Generator Source 배포 대기
- 목적: EdgeScope-Lite 및 Vivado ILA와 동일한 조건에서 Software Polling 방식의
  성능과 한계를 측정

> 이 문서의 조건은 세 비교군의 결과를 공정하게 비교하기 위한 공통 계약이다.
> 임의로 FPGA Part, Clock, Probe 폭, Trigger 의미, Buffer 길이 또는 정규화
> 데이터 형식을 변경하지 않는다. 변경이 필요하면 세 비교군에 모두 같은
> 조건을 적용한다.
>
> CPU/Custom은 UART, ILA는 JTAG/Vivado를 사용하므로 물리 출력 Interface와
> 전송속도는 동일 조건이 아니며 직접 우열 비교하지 않는다.

## 1. CPU Polling 비교군의 위치

팀원 A의 결과물은 MicroBlaze가 AXI GPIO를 반복해서 읽고 Software에서
Trigger를 판정하는 비교 기준이다.

```text
probe_test[7:0]
    ↓
AXI GPIO Input
    ↓
MicroBlaze Polling Loop
    ├─ Software Trigger
    ├─ Software Ring Buffer
    └─ UART Result Dump
```

CPU Polling은 EdgeScope-Lite와 동일한 100 MS/s Hardware Capture를 구현하는
것이 아니다. 실제 Polling 속도와 짧은 Pulse 검출 한계를 측정하기 위한
Software Baseline이다.

문서와 발표에서는 CPU가 읽은 값을 **Polling Observation**으로 부르고,
실측하지 않은 상태에서 `100 MS/s Sample`이라고 표현하지 않는다.

## 2. 반드시 통일할 Hardware 조건

| 항목 | 동결 조건 |
|---|---|
| Board | Digilent Basys 3 |
| FPGA Part | `xc7a35tcpg236-1` |
| Vivado / Vitis | 2024.2 |
| Processor | MicroBlaze V |
| System Clock | 100 MHz |
| Clock Constraint | 10 ns |
| Probe Width | 8-bit |
| 공통 비교 신호 | `probe_test[7:0]` |
| Local Memory | 128 KiB |
| UART | AXI UART Lite, 9,600 baud, 8-N-1 |
| Timeout/측정 | AXI Timer, 100 MHz |
| Instruction/Data Cache | Disabled / Disabled |
| Synthesis Strategy | Vivado Default |
| Implementation Strategy | Vivado Default |
| Target Language | 팀 공통 설정 유지 |

세 비교군의 공통 Base SoC에는 Generator 제어용 AXI GPIO
`axi_gpio_test_ctrl`을 동일하게 포함한다.

| AXI Peripheral | Base Address | Range |
|---|---:|---:|
| 공통 `axi_gpio_test_ctrl` | `0x4000_0000` | 64 KiB |
| CPU 전용 `axi_gpio_probe` | `0x4001_0000` | 64 KiB |

CPU Polling 비교군에만 다음 Block을 추가한다.

- AXI GPIO `axi_gpio_probe` 1개
- Channel 1: 8-bit Input
- Interrupt: 사용하지 않음
- All Inputs: `probe_test[7:0]`

다음 분석용 Hardware는 CPU Polling 자원 측정 Build에 넣지 않는다.

- Probe Sampler Custom IP
- Basic Trigger Engine Custom IP
- Circular Trace Buffer Custom IP
- Capture Block Memory Generator
- AXI BRAM Controller
- Vivado ILA

Resource 비교를 시작하기 전에 공통 Base SoC를 다음 위치와 Git Commit으로
동결한다.

```text
배포 예정 위치 : comparison/common/base_soc.tcl
Base Commit ID : <공통 Source 배포 후 실제 Commit ID 기입>
```

현재 문서는 Interface와 시험 조건을 동결한 것이며 위 Source가 아직 배포되지
않은 상태다. 실제 파일과 Commit ID가 기록되기 전에는 공식 자원 측정을
시작하지 않는다.

## 3. 공통 입력 신호 조건

세 비교군은 동일 RTL `test_pattern_generator`가 생성한 같은 8-bit 신호를
사용한다.

```text
배포 예정 위치:
comparison/common/rtl/test_pattern_generator.sv

test_pattern_generator/probe_test[7:0]
    ├─ CPU Polling Build → AXI GPIO Input
    ├─ EdgeScope Build   → Probe Sampler Input
    └─ ILA Build         → ILA 8-bit Probe
```

공통 Generator Interface와 Parameter는 다음으로 고정한다.

| 항목 | 조건 |
|---|---|
| `clk_i` | 100 MHz |
| `reset_n_i` | Active-low |
| `start_event_i` | START Level의 Rising Edge를 변환한 내부 1-Clock Event |
| `test_id_i` | 아래 기능 시험 ID 선택 |
| `pulse_width_cycles_i` | Pulse Stress 폭 선택 |
| `probe_test_o[7:0]` | 세 비교군의 공통 입력 |
| `done_o` | 선택 Sequence 종료 |
| START 후 Pre-event Delay | 1,000,000 Clocks = 10 ms |
| Normal Stable Time | 최소 10 ms |
| Inter-trial Gap | 최소 10 ms |

공통 Base의 `axi_gpio_test_ctrl` 연결은 다음으로 고정한다.

| AXI GPIO | Bit | 기능 |
|---|---:|---|
| Channel 1 Output | 0 | `START_LEVEL`, Software가 `0→1→0`으로 제어 |
| Channel 1 Output | 4:1 | `test_id[3:0]` |
| Channel 1 Output | 24:5 | `pulse_width_cycles[19:0]` |
| Channel 1 Output | 25 | Generator Clear |
| Channel 2 Input | 0 | Generator Busy |
| Channel 2 Input | 1 | Generator Done |

Generator 내부에서 Channel 1 bit 0의 `0→1` 전이를 검출해 정확히 1-Clock의
`start_event_i`로 변환한다. AXI Write 사이에 `START_LEVEL=1`이 여러 Clock
유지돼도 Sequence는 한 번만 시작해야 한다.

다음 규칙을 적용한다.

- RTL Source와 Parameter를 세 Build에서 동일하게 사용
- Generator Clock은 100 MHz로 고정
- 합성 최적화 방지를 위한 조건도 동일하게 적용
- Generator 자원은 공통 Base 자원에 포함하거나 세 결과에서 동일하게 차감
- 팀원별로 Pattern Sequence를 변경하지 않음
- 외부 Switch를 조작해 생성한 신호를 공식 비교 결과로 사용하지 않음
- 시험 전 Generator Git Commit ID와 SHA-256을 결과 `README.md`에 기록

각 시험은 Capture 쪽 준비가 끝난 뒤 Generator를 시작한다.

```text
CPU Polling : Pre-fill 완료 → Software가 Test Control START → Polling Loop 복귀
Custom      : PRE_READY + Trigger ARM → Software가 Test Control START
ILA         : Hardware Manager ARM → UART RUN 명령 → MicroBlaze가 START
```

Generator는 `START`를 받은 뒤 공통 Pre-event Delay 10 ms를 기다리고 Event를
발생시킨다. 이 Delay를 통해 CPU가 AXI Write를 마치고 Polling Loop에 복귀할
시간을 보장한다. READY/ARM 전에 START하지 않으며 Generator Source, Parameter,
Sequence, START 경로 또는 Delay가 다른 결과는 서로 비교하지 않는다.

## 4. Capture 및 Buffer 의미

주 비교 조건은 다음과 같이 고정한다.

| 비교군 | 입력 설정 |
|---|---|
| CPU Polling | AXI GPIO 8-bit 값을 한 AXI Transaction으로 Read |
| EdgeScope-Lite | Sampler `divider=1`, `channel_mask=0xFF` |
| Vivado ILA | 100 MHz Clock마다 8-bit Probe Capture |

| 항목 | 공통 조건 |
|---|---:|
| Observation 개수 | 1,024 |
| Pre-trigger | Trigger 직전 Polling Observation 512개 |
| Post-trigger | Trigger Observation을 포함한 512개 |
| Trigger Logical Index | 512 |
| Trigger 이후 추가 저장 | 511개 |
| 저장 형식 | 32-bit Word |
| 유효 데이터 | `word[7:0]` |
| Reserved | `word[31:8] = 0` |

CPU Software Ring Buffer 예시:

```c
uint32_t capture[1024];
```

CPU Polling의 1,024개 Observation은 EdgeScope-Lite의 100 MHz 등간격 Sample과
시간 폭이 같지 않다. 비교 시에는 실제 Timer 측정값으로 Observation 주기를
별도로 기록한다.

## 5. Trigger 정의

### Rising Edge

선택한 Channel `ch`에 대해 다음 조건이 처음 참이 되는 Observation에서
Trigger를 발생시킨다.

```text
previous[ch] = 0
current[ch]  = 1
```

### Falling Edge

```text
previous[ch] = 1
current[ch]  = 0
```

### Masked Pattern

```text
match = ((current & mask) == (pattern & mask))
```

다음 규칙을 함께 적용한다.

- `mask=0x00`이면 Pattern Trigger를 발생시키지 않음
- 이전 Observation에서 `match=0`, 현재 `match=1`일 때만 Trigger
- Pattern이 유지되는 동안 Trigger를 반복하지 않음
- Capture 한 번당 Trigger는 정확히 한 번만 인정
- Pre-trigger 512개가 채워지기 전 Trigger는 인정하지 않음
- Software Trigger ARM 이후 첫 Observation에서는 Edge Trigger만 금지하고
  `previous_sample` 기준값을 만듦
- Pattern Mode는 `previous_match=0`에서 시작하므로 첫 Observation이
  Pattern과 일치하면 Trigger될 수 있음

공식 기능 비교용 Trigger 설정은 다음 값으로 고정한다.

| Test | Mode | Channel | Pattern | Mask |
|---|---|---:|---:|---:|
| Rising | Rising Edge | 0 | 사용 안 함 | 사용 안 함 |
| Falling | Falling Edge | 0 | 사용 안 함 | 사용 안 함 |
| Pattern | Masked Pattern | 사용 안 함 | `0xA0` | `0xF0` |

## 6. Software 실행 순서

```text
Platform / UART / AXI GPIO / AXI Timer 초기화
→ Ring Buffer와 Trigger 상태 초기화
→ AXI GPIO Read 결과를 Ring Buffer에 Circular Write
→ 512개 Pre-trigger Observation 확보
→ Software Trigger ARM
→ Edge Mode: ARM 후 첫 Observation으로 기준값 초기화, Edge Trigger 금지
→ Pattern Mode: 첫 Observation부터 match 진입 조건 판정
→ Trigger 대기 중에도 AXI GPIO Read와 Circular Overwrite 계속
→ Rising / Falling / Masked Pattern 판정
→ Trigger Observation을 Logical Index 512로 저장
→ 추가 Observation 511개 저장
→ Polling 중지
→ Ring Buffer를 시간순 0~1023으로 재정렬
→ UART Hex 또는 CSV 출력
```

최초 512개를 채운 뒤 Buffer 내용을 고정하면 안 된다. Trigger가 발생할 때까지
계속 Circular Overwrite하여 항상 Trigger 직전의 최신 Observation 512개를
보존해야 한다.

UART 출력은 Capture가 끝난 뒤 수행한다. UART 전송시간을 Polling 속도나
Capture 속도에 포함하지 않는다.

## 7. CPU UART 출력 및 정규화 데이터 형식

CPU Polling 결과는 UART로 전송한다. EdgeScope-Lite도 UART를 사용하지만
ILA는 JTAG/Vivado에서 Capture를 Export한다. 따라서 전송속도는 비교하지 않고,
세 방식의 결과를 다음 논리 형식으로만 정규화한다.

```text
Logical Index: 0~1023
Trigger Index: 512
Sample Value : 8-bit
Order        : Oldest → Newest
```

### 필수 Hex Mode

```text
CPU_POLLING_REFERENCE
TIMER_HZ=100000000
OBSERVATIONS=1024
TRIGGER_INDEX=512
ELAPSED_TICKS=<실측값>
OBS_PER_SEC=<계산값>
0000: 14
0001: 16
...
0512: 9E  <TRIGGER>
...
1023: 04
CAPTURE_END
```

### 선택 CSV Mode

```text
index,value_hex,is_trigger,ch7,ch6,ch5,ch4,ch3,ch2,ch1,ch0
0,14,0,0,0,0,1,0,1,0,0
...
512,9E,1,1,0,0,1,1,1,1,0
```

UART 설정은 `9,600 baud, 8 data bits, no parity, 1 stop bit`로 통일한다.
ILA Export CSV도 최종 비교 단계에서 위 Column으로 변환한다.

## 8. Polling 속도 측정

AXI Timer를 사용해 다음 전체 Analyzer Loop를 측정한다.

```text
volatile AXI GPIO Read
→ Ring Buffer Write
→ previous / match 상태 갱신
→ 선택된 Trigger 조건 판정
→ Write Pointer 갱신
```

UART Dump와 Capture 시작 전 1회성 설정만 측정에서 제외한다. AXI GPIO Read만
따로 측정한 수치는 선택 보조값으로 기록할 수 있지만 공식 CPU Polling
처리량으로 사용하지 않는다.

Software Build 조건:

| 항목 | 동결값 |
|---|---|
| Vitis Build | Release |
| Compiler Optimization | `-O2` |
| Instruction Cache | Disabled |
| Data Cache | Disabled |
| GPIO Access | `volatile` Memory-mapped Read |

처리량은 Trigger Mode별로 따로 측정한다.

| Benchmark | Trigger 설정 | 고정 입력 | 기대 |
|---|---|---:|---|
| B-RISE | Rising, CH0 | `0x00` | Trigger 없음 |
| B-FALL | Falling, CH0 | `0x00` | Trigger 없음 |
| B-PATTERN | Pattern=`0xA0`, Mask=`0xF0` | `0x00` | Trigger 없음 |

각 Benchmark는 Stable/Nonmatching 입력을 사용해 10,000 Iteration이 끝나기
전에 Capture가 종료되지 않게 한다.

필수 측정 횟수:

```text
N = 10,000 Analyzer Loop Iterations
```

계산식:

```text
elapsed_seconds = elapsed_ticks / 100,000,000
observations_per_second = N × 100,000,000 / elapsed_ticks
average_period = elapsed_seconds / N
```

각 Mode를 최소 3회 측정하고 다음 값을 제출한다.

- Rising 평균 Observations/s 및 Period
- Falling 평균 Observations/s 및 Period
- Masked Pattern 평균 Observations/s 및 Period
- 세 Mode 평균 중 최저 Observations/s

발표의 CPU Polling 대표 처리량은 세 Mode 평균 중 가장 낮은 값으로 고정한다.

결과 단위는 `Observations/s`로 기록한다. 이를 `MS/s`로 바꿔 표현하려면
측정값을 근거로 계산하고, Hardware Sample Rate와 동일하다고 표현하지 않는다.

## 9. 공통 기능 시험

### 정상 동작 시험

| ID | 입력 조건 | 기대 결과 |
|---|---|---|
| P-01 | `0x00 → 0x01`, CH0 Rising | Trigger 1회 |
| P-02 | `0x01 → 0x00`, CH0 Falling | Trigger 1회 |
| P-03 | `mask=0xF0`, `pattern=0xA0`, `0x95 → 0xA5` | Trigger 1회 |
| P-04 | `0x95 → 0xA5`, 이후 `0xA5` 10 ms 유지 | Trigger Count=1 유지 |
| P-05 | `mask=0x00`, 100 ms 관찰 | Trigger Count=0, 정상 Timeout |

정상 시험에서는 각 입력 상태를 충분히 오래 유지해 CPU Polling도 검출할 수
있도록 한다. 권장 유지시간은 최소 10 ms다.

P-05는 Trigger가 발생하지 않는 것이 정상 결과다. 다음 조건 중 먼저 도달한
시점에 시험을 종료한다.

```text
Timeout       = 100 ms = 10,000,000 Timer Ticks
Observation   = 100,000 Iterations
Expected      = Trigger Count 0
```

### 짧은 Pulse Stress 시험

CH0 Rising Pulse를 다음 폭으로 입력하고 각 조건을 10회 반복한다.

| Pulse Width | 100 MHz Clock 기준 | 기록값 |
|---:|---:|---|
| 10 ns | 1 Clock | 검출 횟수 / 10 |
| 100 ns | 10 Clocks | 검출 횟수 / 10 |
| 1 µs | 100 Clocks | 검출 횟수 / 10 |
| 10 µs | 1,000 Clocks | 검출 횟수 / 10 |
| 100 µs | 10,000 Clocks | 검출 횟수 / 10 |
| 1 ms | 100,000 Clocks | 검출 횟수 / 10 |

각 Pulse 사이에는 최소 10 ms 간격을 둔다. 10회 모두 매 시험 Software를
다시 ARM하고 Pre-fill 완료를 확인한 뒤 Test Control에 `START`를 준다.
준비 전에 발생한 Pulse는 검출률 분모 10회에 포함하지 않는다.

CPU Polling이 짧은 Pulse를 놓치는 것은 실패한 구현이 아니라 비교 실험의
주요 결과다. 검출값을 수정하거나 예상값으로 대체하지 않는다.

## 10. Resource 및 Timing Report 조건

Resource 비교용 Build에는 Debug ILA를 넣지 않는다.

Implementation 완료 후 다음 Report를 저장한다.

- Report Utilization
- Report Utilization - Hierarchical
- Report Timing Summary
- DRC Report

기록할 항목:

| 지표 | 기록값 |
|---|---:|
| Slice LUTs | TBD |
| LUT as Logic | TBD |
| LUT as Memory | TBD |
| Slice Registers | TBD |
| BRAM36 | TBD |
| BRAM18 | TBD |
| DSP48E1 | TBD |
| WNS | TBD |
| TNS | TBD |

세 비교군은 동일한 Base SoC를 유지한다. 최종 보고서에는 전체 자원과 함께
가능하면 다음 순증가량도 기록한다.

```text
CPU Polling 순증가량 =
Resource(Base SoC + AXI GPIO) - Resource(Base SoC)
```

CPU Polling은 100 MHz 등간격 Capture와 기능적으로 동등하지 않고, 4 KiB
Software Ring Buffer도 기존 128 KiB Local Memory 안에 저장한다. 따라서
CPU Polling 자원값은 기능·성능 Baseline과 전체 시스템 비용 참고치로만
사용한다.

다음 절감률은 계산하지 않는다.

```text
금지: EdgeScope-Lite 대비 CPU Polling 자원 절감률
금지: ILA 대비 CPU Polling 자원 절감률
```

프로젝트의 공식 Analyzer 자원 절감률은 동일 Base SoC를 각각 차감한
`EdgeScope-Lite Custom vs Vivado ILA` 사이에서만 계산한다.

## 11. 공정한 비교를 위한 금지사항

- CPU Polling Build에 ILA를 넣고 그 자원을 CPU Polling 자원으로 제출하지 않음
- 다른 FPGA Part, Clock 또는 합성 전략 사용 금지
- Polling 결과를 `100 MS/s`라고 표기 금지
- UART Dump 시간을 Polling 측정시간에 포함 금지
- Trigger 전후 데이터가 틀렸는데 성공으로 기록 금지
- Test Pattern 또는 Pulse Width를 팀원별로 변경 금지
- 전체 자원과 순증가 자원을 혼용하지 않음
- CPU/UART와 ILA/JTAG의 전송속도를 직접 비교하지 않음
- CPU Polling을 Custom/ILA와 동급 100 MS/s Analyzer라고 표현하지 않음
- CPU Polling을 포함한 공식 자원 절감률을 계산하지 않음
- Simulation 결과를 실제 보드 측정값으로 표기하지 않음

## 12. 팀원 A 제출 산출물

권장 폴더 구조:

```text
comparison/cpu_polling/
├── hw/
│   ├── block_design.tcl
│   └── constraints.xdc
├── sw/
│   └── cpu_polling_reference.c
├── reports/
│   ├── utilization.rpt
│   ├── hierarchical_utilization.rpt
│   ├── timing_summary.rpt
│   └── drc.rpt
├── results/
│   ├── polling_speed.txt
│   ├── trigger_tests.csv
│   ├── pulse_detection.csv
│   └── uart_capture.log
└── README.md
```

필수 제출 항목:

- Vivado Block Design 또는 재현 가능한 Tcl
- XDC
- Vitis C Source
- XSA
- Utilization 및 Timing Report
- Polling 속도 3회 측정값
- Trigger 기능 시험 결과
- Pulse 폭별 검출률
- UART Capture Log
- Base SoC Commit ID
- Test Pattern Generator Commit ID 및 SHA-256
- Vitis Build Mode, Compiler Flag, Cache 설정

## 13. 완료 판정 Checklist

- [ ] Basys 3 / XC7A35T / Vivado 2024.2 사용
- [ ] 100 MHz Clock 및 10 ns Constraint 사용
- [ ] AXI GPIO 8-bit Input 사용
- [ ] `divider=1`, `channel_mask=0xFF`에 대응하는 전체 8-bit Read 사용
- [ ] 공통 Generator Commit/SHA-256 및 START 절차 일치
- [ ] 1,024개 Polling Observation 저장
- [ ] Pre 512 + Trigger 포함 Post 512 구현
- [ ] Trigger 대기 중 Circular Overwrite 유지
- [ ] Trigger Logical Index 512 유지
- [ ] Rising/Falling/Masked Pattern 의미 일치
- [ ] ARM 후 첫 Observation에서는 Edge Trigger만 금지
- [ ] Pattern 첫 Observation은 `match && !previous_match` 규칙 적용
- [ ] 세 Trigger Mode의 전체 Analyzer Loop 처리량을 각각 3회 측정
- [ ] UART Hex Log 저장
- [ ] 5개 정상 기능 시험 수행
- [ ] Pulse 폭별 검출률 기록
- [ ] Implementation Utilization/Timing Report 저장
- [ ] Resource 측정 Build에서 ILA 제거
- [ ] CPU 결과로 Custom/ILA 자원 절감률을 계산하지 않음
- [ ] 미검증 항목을 PASS로 표시하지 않음

## 14. 팀원 A에게 전달할 요약

> CPU Polling 비교군은 Basys 3, MicroBlaze V, 100 MHz, 8-bit Probe,
> 1,024 Observation, Trigger Index 512 조건으로 구현합니다. AXI GPIO를
> 반복 Read하고 Rising/Falling/Masked Pattern을 Software로 판정합니다.
> Trigger 직전 512개와 Trigger Observation을 포함한 이후 512개를 Software
> Ring Buffer에 보존하며 Trigger 대기 중에도 최신 512개를 계속 Circular
> Overwrite합니다. AXI Timer로 GPIO Read, Buffer Write, 상태 갱신과 Trigger
> 판정을 포함한 전체 Loop 처리량을 세 Trigger Mode별로 측정하고 가장 낮은
> 값을 대표값으로 사용하며, 결과를 100 MS/s라고 표현하지 않습니다.
> Resource 측정 Build에는 ILA와 EdgeScope Custom IP를 넣지 않고,
> 동일 Generator와 START 절차에 대한 UART Log, Trigger Test, Pulse 폭별
> 검출률, Utilization 및 Timing Report를 제출합니다. CPU Polling은 기능·성능
> Baseline으로만 사용하며 공식 자원 절감률은 Custom과 ILA 사이에서 계산합니다.
