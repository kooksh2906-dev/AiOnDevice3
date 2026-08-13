# SoC Project Day 1 — 윤형욱 작업 정리

- 날짜: 2026-07-27
- 담당자: 윤형욱
- 담당 IP: Circular Trace Buffer
- 상태: Day 1 담당 범위 완료, 팀 통합 가능

> Day 1에는 공통명세를 동결하고 Circular Trace Buffer Core RTL을 구현했다.
> 또한 다음 단계의 AXI Wrapper, BRAM 연동, IP 패키징과 검증을 일부 선행해
> 팀원이 Vivado Block Design에 바로 연결할 수 있는 상태로 인계했다.
>
> 이 문서에는 Day 2에 수행한 전체 MicroBlaze SoC Block Design 및 XSA 분석
> 결과는 포함하지 않았다.

## 1. 담당 역할

- 8-bit 유효 Sample을 저장하는 Circular Trace Buffer 구현
- Trigger 전후 데이터를 1,024 × 32-bit BRAM에 저장
- BRAM Port A Capture Write 경로 구현
- Capture 상태, 주소, DONE IRQ 관리
- AXI4-Lite Register Wrapper 및 Vivado Catalog IP 패키징
- Wrap-around, Trigger 정렬, BRAM 주소 변환 검증

## 2. 공통명세 확정

팀원이 서로 다른 규격으로 구현하지 않도록 Frozen v2.1 공통명세를 확정했다.

| 항목 | 확정값 |
|---|---|
| System Clock | 100 MHz |
| Probe Width | 8-bit |
| Capture Memory | 1,024 × 32-bit |
| Core Address | 10-bit Word Address |
| CPU BRAM Address | 32-bit Byte Address |
| Pre-trigger | Trigger 이전 Valid Sample 512개 |
| Post-trigger | Trigger Sample 포함 512개 |
| Trigger Logical Index | 512 |
| BRAM Port A | Circular Trace Buffer Write |
| BRAM Port B | MicroBlaze + AXI BRAM Controller Read |

Trigger를 안전하게 받기 위한 공통 제어 순서도 다음과 같이 동결했다.

```text
Trigger Clear
→ Buffer Abort/Clear
→ Buffer ARM
→ Sampler Enable
→ PRE_READY 확인
→ Trigger Clear/ARM
→ DONE 확인
```

## 3. Circular Buffer Core RTL 구현

AXI를 제외한 독립 Core RTL부터 구현했다.

```text
IDLE → PREFILL → ARMED → POST_CAPTURE → DONE
```

핵심 동작은 다음과 같다.

- `sample_valid_i=1`인 유효 Sample만 BRAM에 기록
- PREFILL 동안 512개 Valid Sample 저장
- PREFILL 중 들어온 Trigger는 무시
- ARMED 상태에서 Trigger와 정렬된 현재 Sample을 Post Sample #1로 저장
- Trigger 이후 Valid Sample 511개를 추가 저장한 뒤 DONE
- DONE 이후 BRAM Write 중지 및 IRQ 유지
- `START_ADDR=(LAST_WRITE_ADDR+1) mod 1024`
- CPU는 START_ADDR부터 1,024개를 순환해 읽으면 시간순 데이터를 얻음

BRAM에 저장되는 한 Word의 형식은 다음과 같다.

```text
BRAM Word[31:8] = 24'h000000
BRAM Word[7:0]  = sample_data_i[7:0]
```

## 4. AXI Register 및 IRQ 구현

다음 Register Map을 구현하고 공통 C Header와 일치시켰다.

| Offset | Register | Access | 기능 |
|---:|---|---|---|
| `0x00` | CONTROL | W1P | ARM, CLEAR_DONE, ABORT |
| `0x04` | STATUS | RO | BUSY, PRE_READY, TRIGGERED, DONE |
| `0x08` | START_ADDR | RO | 시간순 첫 Sample의 물리 Word 주소 |
| `0x0C` | TRIGGER_ADDR | RO | Trigger Sample의 물리 Word 주소 |
| `0x10` | WRITE_ADDR | RO | 현재/마지막 Write 주소 |
| `0x14` | CAPTURE_INFO | RO | Depth 1024, Trigger Index 512 |

- AXI Data Width: 32-bit
- AXI Local Address Width: 6-bit
- CONTROL: Write-One-Pulse 방식
- IRQ: DONE과 동일한 Active-high Level 방식
- `CAPTURE_INFO` 기대값: `0x02000400`

## 5. BRAM 연결 및 주소 변환

- Core 내부 10-bit Word Index를 Packaged IP에서 32-bit Byte Address로 변환
- 변환식: `byte_address = word_index << 2`
- Capture BRAM 크기: 4,096 bytes
- BRAM Interface Metadata: `MEM_SIZE=4096`
- BRAM 형식: True Dual Port RAM, 1,024 × 32-bit
- Capture Buffer는 Port A를 사용하고 CPU는 DONE 이후 Port B를 통해 Read

## 6. 검증 결과

### Day 1 핵심 검증

| Test | 검증 내용 | 결과 |
|---|---|---|
| `tb_common_pkg` | 공통 상수, Width, Depth | PASS |
| `tb_circular_trace_buffer_basic` | Reset, ARM, Valid Gating, PREFILL | PASS |
| `tb_circular_trace_buffer_trigger` | Trigger 정렬, 512:512 구성 | PASS |
| `tb_circular_trace_buffer_control` | Abort, Clear, Re-arm, DONE/IRQ | PASS |
| C `_Static_assert` | Register Offset, Bit, Geometry | PASS |

### 선행 확장 검증

| Test | 검증 내용 | 결과 |
|---|---|---|
| `tb_circular_trace_buffer_wrap` | 주소 0/1/1022/1023 경계 Wrap | PASS |
| `tb_circular_trace_buffer_axi` | W1P, WSTRB, AW/W 순서, Back-pressure | PASS |
| `tb_circular_trace_buffer_bram` | Packaged Top, Byte 변환, 1,024 Word Read | PASS |

최종 누적 결과는 SystemVerilog Test 7개와 C Header 검사 전체 PASS다.

## 7. Vivado IP 패키징 및 선행 합성

- VLNV: `user.org:user:circular_trace_buffer:1.0`
- AXI Interface: `s_axi`, AXI4-Lite Slave
- BRAM Interface: `BRAM_PORTA`, BRAM Master
- Interrupt Interface: Active-high Level
- IP Integrity Check: PASS
- Vivado Catalog Load: PASS
- Packaged IP Block Design Validation: PASS

### Custom IP Routed OOC 결과

| 항목 | 결과 |
|---|---:|
| Slice LUT | 73 |
| Slice Register | 90 |
| WNS | +4.978 ns |
| WHS | +0.170 ns |
| TNS / THS | 0.000 ns / 0.000 ns |
| Routed Nets | 140 / 140 |

위 Timing은 Circular Trace Buffer Custom IP의 100 MHz OOC 결과이며,
전체 MicroBlaze SoC Timing 결과는 아니다.

### Trace + BRAM 선행 Subsystem 합성

| 항목 | 결과 |
|---|---:|
| LUT | 338 |
| FF | 306 |
| RAMB36E1 | 1 |
| DSP | 0 |

## 8. 발견한 문제와 해결

### Trigger ARM Race

- 문제: Trigger Engine을 먼저 ARM하면 PREFILL 중 One-shot Trigger가 소진될 수 있음
- 해결: `Buffer ARM → PRE_READY 확인 → Trigger ARM` 순서로 동결
- 검증: PREFILL 및 512번째 경계 Trigger 무시 Test 추가

### BRAM Depth Propagation

- 문제: BRAM Interface 기본값 8,192 bytes가 BMG Depth를 2,048로 변경
- 해결: Port A/B `MEM_SIZE=4096`, Depth 1,024로 고정
- 검증: Tcl Assertion과 BRAM Test 추가

### IRQ Metadata

- 문제: `irq_o`가 일반 Scalar Port로만 등록됨
- 해결: IP-XACT Interrupt Master, Active-high Level로 등록

### AXI Corner Case

- 문제: Response Stall과 일부 AW/W Transaction Reset 검증 부족
- 해결: B/R Back-pressure, AW-only/W-only Reset Test 추가

## 9. 팀 인수인계 내용

- `ip_repo/circular_trace_buffer_1_0/`를 Vivado IP Repository에 등록
- Circular Trace Buffer `BRAM_PORTA`를 BMG Port A에 연결
- AXI BRAM Controller를 BMG Port B에 연결
- Trace CSR와 Capture BRAM에 각각 4 KiB 주소 영역 배정
- 모든 관련 IP를 동일한 100 MHz Clock/Reset 계통에 연결
- Software는 PRE_READY 확인 후 Trigger를 ARM
- DONE 이후 START_ADDR부터 Modulo 1024 방식으로 BRAM Read

## 10. 산출물

| 구분 | 위치 |
|---|---|
| 공통명세 | `docs/day1_common_spec.md` |
| Core RTL | `rtl/core/circular_trace_buffer_core.sv` |
| AXI Wrapper | `rtl/bus/circular_trace_buffer_axi.sv` |
| Packaged Top | `rtl/top/circular_trace_buffer_ip.sv` |
| Vivado Catalog IP | `ip_repo/circular_trace_buffer_1_0/` |
| C Register Header | `sw/include/logic_analyzer_regs.h` |
| Testbench | `sim/tb/` |
| 회귀 Script | `scripts/run_regression.sh` |
| Waveform 증거 | `artifacts/waves/` |
| IP Data Sheet | `docs/circular_trace_buffer_datasheet.md` |
| 검증 보고서 | `docs/verification_report.md` |
| 팀 인수인계서 | `docs/yoon_hyungwook_handoff.md` |
| 역할 필수 개념서 | `docs/yoon_hyungwook_essential_concepts.md` |

## 11. GitHub 공유

- Repository: [yoon3226/EdgeScope-Lite-SoC](https://github.com/yoon3226/EdgeScope-Lite-SoC)
- Branch: `main`
- Initial Commit: `4f178c0`
- Commit Message: `feat: add verified circular trace buffer IP`

## 12. Day 1 최종 결과

Circular Trace Buffer의 공통명세, Core RTL, 주소 계산, Trigger 전후 50:50
Capture 동작을 구현하고 검증했다. AXI Wrapper, BRAM Address Adapter,
Vivado IP 패키징과 일부 통합 검증도 선행해 Day 2 Block Design 연결을 지원할
수 있는 상태로 마무리했다.
