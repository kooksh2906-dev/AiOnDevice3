# SoC Project Day 2 — 윤형욱 작업 정리

- 날짜: 2026-07-28
- 담당자: 윤형욱
- 담당 IP: Circular Trace Buffer + Capture BRAM
- Day 2 역할: IP 연결 지원, Block Design 검수, 합성/XSA 결과 분석
- 상태: 하드웨어 구조 통합·합성/XSA 확인 완료, 런타임 검증 대기

> Day 2에는 새로운 RTL 기능을 추가하기보다 팀 통합을 지원하고 결과를
> 검수하는 작업을 진행했다.
>
> Circular Trace Buffer의 AXI 제어 경로, Capture BRAM Dual-Port 연결,
> Address Map, Clock/Reset, Interrupt 연결을 확인했다. 이후 팀의 Vivado
> `Validate Design` 통과와 합성 결과를 검토하고, 생성된 XSA에서 실제
> 하드웨어 구성을 다시 확인했다.
>
> `Validate Design`과 합성 통과는 구조 및 정적 연결이 정상이라는 의미다.
> 실제 Trigger, Capture, BRAM Read, UART 데이터의 기능 검증은 Vitis
> 프로그램과 FPGA 보드에서 추가로 수행해야 한다.

## 1. Day 2 담당 범위

### 윤형욱이 직접 수행한 작업

- Circular Trace Buffer IP 연결 방법 지원
- Capture BRAM Port A/Port B 사용 주체 설명
- BRAM Interface를 External Port로 만들지 않는다는 점 확인
- 팀의 MicroBlaze Block Design 연결 상태 검수
- AXI Timer 추가 후 Address Map 및 Interrupt 구성 검토
- `Validate Design` 통과 결과 확인
- 합성 Resource Utilization 검토
- XSA 내부 HWH, Address Map, BRAM 규격, Interrupt 연결 분석
- 다음 단계 Vitis/보드 검증 항목 정리

### 팀 전체 통합 결과

- Probe Sampler, Basic Trigger Engine, Circular Trace Buffer 연결
- MicroBlaze V, AXI Interconnect, AXI BRAM Controller 연결
- AXI Timer, AXI UART Lite, AXI Interrupt Controller 연결
- Capture BRAM True Dual Port 구성
- Vivado `Validate Design` PASS
- 합성 완료 및 Bitstream이 포함된 XSA Hardware Handoff 생성

## 2. Block Design 데이터 경로 검수

XSA의 Hardware Handoff 정보에서 다음 데이터 경로를 확인했다.

```text
probe_i[7:0]
    ↓
Probe Sampler
    ├─ sample_data[7:0] ──────┬─→ Basic Trigger Engine
    └─ sample_valid ──────────┴─→ Circular Trace Buffer

Basic Trigger Engine
    └─ trigger_pulse ───────────→ Circular Trace Buffer

Circular Trace Buffer
    └─ BRAM Port A Write ───────→ Capture BRAM

MicroBlaze + AXI BRAM Controller
    └─ BRAM Port B Read ────────→ Capture BRAM
```

확인 결과는 다음과 같다.

- Sampler의 `sample_data_o[7:0]`가 Trigger와 Buffer에 함께 연결됨
- Sampler의 `sample_valid_o`가 Trigger와 Buffer에 함께 연결됨
- Trigger의 `trigger_pulse_o`가 Buffer의 `trigger_pulse_i`에 연결됨
- Circular Trace Buffer가 Capture BRAM Port A를 사용함
- AXI BRAM Controller가 Capture BRAM Port B를 사용함
- Capture Write 경로와 CPU Read 경로가 하나의 True Dual-Port BRAM을 공유함

## 3. BRAM Port와 External Port 판단

Day 2 Block Design 검수 중 BRAM Port를 `Make External` 해야 하는지 확인했다.

결론은 다음과 같다.

| 연결 | 사용 주체 | 처리 |
|---|---|---|
| Capture BRAM Port A | Circular Trace Buffer Write | Block Design 내부 연결 |
| Capture BRAM Port B | AXI BRAM Controller Read | Block Design 내부 연결 |
| `rsta_busy`, `rstb_busy` | BRAM Reset Busy 상태 | 사용하지 않으면 미연결 가능 |

따라서 BRAM Port A와 Port B는 FPGA 외부 핀으로 빼지 않는다.

XSA에서 확인된 실제 외부 Port는 다음뿐이다.

| External Port | 방향 | 용도 |
|---|---|---|
| `sys_clock` | Input | 100 MHz System Clock |
| `reset` | Input | Active-high System Reset |
| `probe_i_0[7:0]` | Input | 8-channel Digital Probe |
| `usb_uart_rxd` | Input | UART Receive |
| `usb_uart_txd` | Output | UART Transmit |

Circular Trace Buffer 자체의 Sample 데이터 출력 Port는 없으며, Capture 결과는
내부 BRAM에 저장한 뒤 MicroBlaze가 AXI BRAM Controller를 통해 읽는다.

## 4. Clock 및 Reset 검수

- Top-level `sys_clock`: 100 MHz
- MicroBlaze와 AXI Peripheral Clock: 100 MHz
- Probe Sampler AXI Clock: 100 MHz
- Basic Trigger Engine AXI Clock: 100 MHz
- Circular Trace Buffer AXI Clock: 100 MHz
- AXI BRAM Controller Clock: 100 MHz
- AXI Timer Clock: 100 MHz

Sampler, Trigger, Buffer가 동일한 Sample Clock 계통에서 동작하므로
`sample_data`, `sample_valid`, `trigger_pulse` 사이에 별도 CDC 회로가 필요하지
않는 구성임을 확인했다.

Reset은 Processor System Reset의 `peripheral_aresetn`을 통해 AXI Peripheral에
Active-low로 배포되는 구조다.

## 5. AXI Timer 및 Interrupt 연결

Capture가 완료되지 않을 때 Software가 무한 대기하지 않도록 AXI Timer가
Block Design에 추가됐다.

XSA에서 확인된 Interrupt 연결은 다음과 같다.

| Concat 입력 | Interrupt Source | 방식 |
|---:|---|---|
| `In0` | Circular Trace Buffer `irq_o` | Active-high Level |
| `In1` | AXI UART Lite `interrupt` | Rising Edge |
| `In2` | AXI Timer `interrupt` | Active-high Level |

세 Interrupt는 `xlconcat`을 거쳐 AXI Interrupt Controller로 전달되고,
최종적으로 MicroBlaze Interrupt 입력에 연결된다.

Software에서는 Timer를 Capture Timeout 기준으로 사용하고, Timeout 발생 시
Circular Trace Buffer의 ABORT 명령으로 복구하는 흐름을 사용할 수 있다.

## 6. Address Map 확정

Address Editor의 모든 Slave Segment가 할당됐고 `Unassigned=0`인 것을 확인했다.

| IP / Memory | Base Address | High Address | Range |
|---|---:|---:|---:|
| MicroBlaze Local Memory | `0x0000_0000` | `0x0001_FFFF` | 128 KiB |
| Circular Trace Buffer CSR | `0x0002_0000` | `0x0002_0FFF` | 4 KiB |
| AXI UART Lite | `0x4060_0000` | `0x4060_FFFF` | 64 KiB |
| AXI Interrupt Controller | `0x4120_0000` | `0x4120_FFFF` | 64 KiB |
| AXI Timer | `0x41C0_0000` | `0x41C0_FFFF` | 64 KiB |
| Probe Sampler | `0x44A0_0000` | `0x44A0_FFFF` | 64 KiB |
| Basic Trigger Engine | `0x44A1_0000` | `0x44A1_FFFF` | 64 KiB |
| Capture BRAM | `0xC000_0000` | `0xC000_0FFF` | 4 KiB |

검수 결과:

- Address Segment 사이의 겹침 없음
- Circular Trace Buffer CSR과 Capture BRAM 영역이 분리됨
- Capture BRAM 4 KiB는 `1,024 words × 4 bytes`와 일치함
- Software는 BRAM Word `i`를 `BRAM_BASE + i × 4`로 접근해야 함

## 7. Capture BRAM 규격 확인

XSA의 Block Memory Generator 설정을 직접 확인한 결과는 다음과 같다.

| 항목 | 확인값 |
|---|---:|
| Memory Type | True Dual Port RAM |
| Port A Width / Depth | 32-bit / 1,024 |
| Port B Width / Depth | 32-bit / 1,024 |
| Interface Memory Size | 4,096 bytes |
| Port A 사용자 | Circular Trace Buffer |
| Port B 사용자 | AXI BRAM Controller |

이 결과로 Day 1 공통명세의 `1,024 × 32-bit`, `MEM_SIZE=4096`,
Dual-Port 연결이 팀의 최종 Hardware Handoff에도 유지됐음을 확인했다.

## 8. Validate Design 결과

- Vivado `Validate Design`: PASS
- AXI Slave Segment: 모두 Address 할당
- Sampler → Trigger/Buffer 데이터 경로: 연결 확인
- Trigger → Buffer Pulse 경로: 연결 확인
- Buffer/Controller → Dual-Port BRAM: 연결 확인
- Clock/Reset 계통: 연결 확인
- Circular Trace Buffer/UART/Timer Interrupt: 연결 확인

`Validate Design` 통과 후 Block Design 구조상 즉시 수정해야 할 연결 오류는
발견되지 않았다.

## 9. 합성 Resource Utilization

팀이 전달한 Vivado 합성 결과는 다음과 같다.

| Resource | Utilization | Available | Utilization % |
|---|---:|---:|---:|
| LUT | 2,933 | 20,800 | 14.10% |
| LUTRAM | 148 | 9,600 | 1.54% |
| FF | 2,802 | 41,600 | 6.74% |
| BRAM | 33 | 50 | 66.00% |
| IO | 12 | 106 | 11.32% |
| MMCM | 1 | 5 | 20.00% |

### 결과 해석

- LUT와 FF 사용률은 각각 약 14%, 7%로 여유가 충분함
- IO와 MMCM도 현재 구성에서 여유가 있음
- 가장 높은 자원은 BRAM 66%이며 17개가 남아 있음
- XSA HWH의 BRAM 구성값은 MicroBlaze 128 KiB Local Memory 32개와
  Capture BRAM 1개로, 합성 결과의 총 33개와 일치함
- Circular Trace Buffer가 BRAM 33개를 사용하는 것이 아니며 Capture
  Memory 자체는 36 Kb BRAM 1개임
- 이후 ILA를 크게 추가하면 BRAM 사용량이 증가할 수 있으므로 추가 합성 시
  다시 확인해야 함

현재 결과만으로는 FPGA 용량 초과 문제는 없다.

## 10. XSA Hardware Handoff 분석

전달받은 파일:

```text
/home/user4/Downloads/Logic Analyzer/edgescope_lite_bd_wrapper.xsa
```

XSA에서 확인된 주요 정보는 다음과 같다.

| 항목 | 확인 결과 |
|---|---|
| Vivado Version | 2024.2 |
| Board | Digilent Basys 3 |
| FPGA Part | `xc7a35tcpg236-1` |
| Hardware Handoff | HWH 포함 |
| FPGA Programming File | BIT 포함 |
| Memory Map | 모든 주요 AXI Peripheral 포함 |
| Custom IP | Sampler, Trigger, Circular Trace Buffer 포함 |
| Catalog IP | AXI BRAM Controller, AXI Timer 포함 |
| XSA ZIP Integrity | PASS |
| SHA-256 | `bfb3a91593e0059a4ce8fdc884eef5b91953bb00c889e6dc7ef32b6b6e643d19` |

XSA 내부에 HWH, BIT, MMI가 포함돼 있어 Vitis Platform 생성과 FPGA
Programming에 사용할 수 있는 Hardware Handoff 형태임을 확인했다.

단, XSA에는 상세 Timing Report와 보드에서 실행한 기능 시험 결과가 포함되지
않으므로 XSA 존재만으로 전체 기능과 Timing Closure가 검증됐다고 판단하지
않는다.

## 11. Day 2에서 확인한 핵심 결정

| 질문 | 결론 |
|---|---|
| Circular Trace Buffer에 별도 Sample 출력이 필요한가? | 필요 없음. 결과는 BRAM에 저장 |
| BRAM Port A/B를 External로 만들어야 하는가? | 아니오. 모두 Block Design 내부 연결 |
| CPU는 어느 Port를 사용하는가? | AXI BRAM Controller를 통해 Port B Read |
| Buffer는 어느 Port를 사용하는가? | Native BRAM Interface를 통해 Port A Write |
| Capture 데이터 주소 영역은? | `0xC000_0000`부터 4 KiB |
| Buffer Register 주소 영역은? | `0x0002_0000`부터 4 KiB |
| Capture Timeout 수단은? | AXI Timer Interrupt 또는 Timer Polling |
| 현재 구조 오류가 있는가? | Validate Design 및 XSA 구조 기준 즉시 수정 항목 없음 |

## 12. 아직 완료되지 않은 검증

Day 2 종료 시점에 다음 항목은 아직 실제 보드에서 검증되지 않았다.

- Vitis C Application Build 및 실행
- FPGA Program 후 UART 통신 확인
- Sampler Register Write/Read 확인
- Rising/Falling/Masked Pattern Trigger 실제 동작 확인
- Circular Trace Buffer의 DONE/IRQ 확인
- START_ADDR 기반 1,024 Sample 시간순 Read 확인
- Trigger 이전 512개 + Trigger 포함 이후 512개 데이터 비교
- AXI Timer Timeout 및 ABORT 복구 확인
- UART Hex/CSV 출력과 예상 데이터 일치 확인
- 세 Trigger Mode 연속 반복 시연
- 전체 구현 Timing Report 확인

추가로 XSA에는 Probe Sampler와 Basic Trigger Engine의 Custom Driver가
포함됐지만 Circular Trace Buffer 전용 Driver는 포함되지 않았다. Vitis
Application에서는 `sw/include/logic_analyzer_regs.h`와 XSA에서 생성되는
Base Address 정의를 함께 사용해야 한다.

## 13. 다음 단계 실행 순서

```text
XSA로 Vitis Platform 생성
→ UART 기본 출력 확인
→ AXI Peripheral ID/기본 Register Read
→ Sampler 설정
→ Buffer ARM
→ PRE_READY 확인
→ Trigger 설정 및 ARM
→ Timer 시작
→ DONE 또는 Timeout 대기
→ START_ADDR / TRIGGER_ADDR Read
→ Capture BRAM 1,024 Word 시간순 Read
→ UART로 결과 출력
→ 예상값과 비교
```

## 14. Day 2 산출물 및 근거

| 구분 | 위치 또는 근거 |
|---|---|
| Day 1 공통명세 | `docs/day1_common_spec.md` |
| Circular Trace Buffer 인수인계 | `docs/yoon_hyungwook_handoff.md` |
| BRAM 연결 문서 | `docs/bram_integration.md` |
| Register Header | `sw/include/logic_analyzer_regs.h` |
| Hardware Handoff XSA | `/home/user4/Downloads/Logic Analyzer/edgescope_lite_bd_wrapper.xsa` |
| Block Design 검수 | 팀 제공 Vivado Diagram |
| Address Map 검수 | 팀 제공 Address Editor |
| 합성 자원 검수 | 팀 제공 Resource Utilization Summary |

## 15. Day 2 최종 결과

Circular Trace Buffer를 포함한 팀 전체 MicroBlaze SoC의 Block Design 연결을
지원하고 검수했다. Capture BRAM이 `1,024 × 32-bit` True Dual-Port 구조로
유지됐고, Circular Trace Buffer의 Port A Write와 AXI BRAM Controller의
Port B Read가 올바르게 연결된 것을 XSA에서 확인했다.

AXI Timer와 3개 Interrupt 경로, 전체 Address Map, 100 MHz Clock/Reset 계통도
확인했으며 Vivado `Validate Design`은 통과했다. 합성 결과 FPGA 자원은 전체
구성을 수용할 수 있으나 BRAM 사용률이 66%로 가장 높아 이후 ILA 추가 시에는
재검토가 필요하다.

Day 2 종료 시점의 Hardware Handoff는 Vitis 통합을 시작할 수 있는 상태다.
다음 단계에서는 실제 보드에서 Trigger, Capture, 시간순 BRAM Read, UART 출력이
예상값과 일치하는지 기능 검증해야 한다.
