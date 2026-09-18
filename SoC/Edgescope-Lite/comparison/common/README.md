# EdgeScope-Lite 비교군 공통 Source

Vivado ILA, CPU Polling, EdgeScope-Lite 비교군이 같은 환경과 입력 파형을
사용하도록 만드는 공통 Source다.

## 현재 완료 상태

| 단계 | 결과 |
|---:|---|
| 1 | 공통 Base SoC 생성 및 자동 명세 검사 완료 |
| 2 | Test Pattern Generator 구현·연결·시뮬레이션·합성 검증 완료 |

## 주요 파일

```text
comparison/common/
├── base_soc.tcl
├── add_test_pattern_generator.tcl
├── build_base_with_generator.tcl
├── synth_test_pattern_generator.tcl
├── rtl/
│   ├── test_pattern_generator.sv
│   └── test_pattern_generator_gpio_adapter.v
├── sim/
│   ├── run_generator_tb.sh
│   ├── tb_test_pattern_generator.sv
│   └── tb_test_pattern_generator_frozen.sv
└── generated/
    ├── base_soc_generated.tcl
    ├── base_soc_address_map.rpt
    ├── base_soc_with_generator_generated.tcl
    └── test_pattern_generator_utilization.rpt
```

## Generator Control Map

| 신호 | Bit | 기능 |
|---|---:|---|
| `control_i` | 0 | START_LEVEL |
| `control_i` | 4:1 | Test ID |
| `control_i` | 24:5 | Pulse Width, Clock 수 |
| `control_i` | 25 | CLEAR |
| `status_o` | 0 | BUSY |
| `status_o` | 1 | DONE, CLEAR 전까지 유지 |

## Test ID

| ID | 시험 | 파형 |
|---:|---|---|
| `0x0` | Safe / Benchmark | START 거부, Probe/Status 유지 |
| `0x1` | Rising | `0x00 → 0x01` |
| `0x2` | Falling | `0x01 → 0x00` |
| `0x3` | Pattern | `0x95 → 0xA5` |
| `0x4` | Pattern Hold | `0x95 → 0xA5`, 10 ms 유지 |
| `0x5` | No Trigger | `0x00`, 100 ms 유지 |
| `0x6` | Pulse Stress | `0x00 → 0x01 → 0x00` |
| `0x7~0xF` | Reserved | START 거부, Probe/Status 유지 |

ID `0x0`과 Reserved ID는 START를 무시하므로 RESET/CLEAR 직후의 안전값
`0x00`을 바꾸지 않는다. 이전 시험의 DONE 상태에서는 CLEAR 전까지 그 시험의
Post-event 값을 그대로 유지한다. ID `0x3`과 `0x4`의 파형은 동일하며,
결과 Log에서 Pattern 진입 시험과 Pattern 유지 시험을 구분하기 위한 별도 ID다.

`reset_n_i`는 100 MHz Clock에 동기식인 Active-low Reset이다.

## Source 동등성

```text
Common Git Commit: PENDING (현재 Source가 아직 Commit되지 않음)

test_pattern_generator.sv
SHA-256: 9f0a1b7f9a54ddc8f9eb3e093382af9eb6a6cdf8c9ab48ab4ce65d83e7eb5440

test_pattern_generator_gpio_adapter.v
SHA-256: 73fd657010c8109d5a1c7e5168d4ae4a4d576fc80e2ddd02978b087523249580
```

공식 비교 시험 전에 두 Source를 포함하는 공통 Commit을 만들고 위 PENDING을
실제 Commit ID로 바꾼다.

## 재현 명령

저장소 루트에서 실행한다.

```bash
bash comparison/common/sim/run_generator_tb.sh

/media/user4/data/tools/Vivado/2024.2/bin/vivado \
  -mode batch \
  -source comparison/common/build_base_with_generator.tcl

/media/user4/data/tools/Vivado/2024.2/bin/vivado \
  -mode batch \
  -source comparison/common/synth_test_pattern_generator.tcl
```

## 검증 결과

- Fast self-checking Regression: PASS
- Frozen 100 MHz Timing Regression: PASS
  - 공식 Pulse 폭 1, 10, 100, 1,000, 10,000, 100,000 Clock 모두 PASS
- Vivado Clean Rebuild 및 Validate Design: PASS
- Mixed-language Synthesis: Error 0, Critical Warning 0
- Generator 단독 참고 자원: LUT 111, Register 65, BRAM 0, DSP 0

`probe_test_o[7:0]`는 Step 2에서 의도적으로 연결하지 않았다. 각 비교군이
Step 3부터 동일 Net을 자신의 Capture 입력에 연결한다.

공식 자원값은 Generator 단독 합성값이 아니라 각 비교군의 전체
Implementation 결과와 동일 Base를 이용해 계산한다.
