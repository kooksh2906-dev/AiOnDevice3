# EdgeScope-Lite A/B/C 비교 시연 영상 시나리오

## 1. 영상의 핵심 메시지

같은 Basys3, 같은 100 MHz 시스템 클럭, 같은 8채널 Test Pattern
Generator를 사용해 다음 세 방식을 비교한다.

| 비교군 | 방식 | 영상에서 보여줄 핵심 |
|---|---|---|
| A | CPU Polling | 구현은 단순하지만 짧은 Pulse를 놓침 |
| B | EdgeScope-Lite | 전용 FPGA 하드웨어가 100 MHz로 독립 캡처 |
| C | Vivado ILA | Xilinx 표준 Debug IP를 사용한 기준 결과 |

영상의 결론은 다음 한 문장으로 정리한다.

> CPU Polling의 한계를 확인하고, EdgeScope-Lite가 Vivado ILA와 같은
> 100 MHz 동기 캡처를 수행하면서도 독립적인 임베디드 분석기로 동작함을
> 검증했다.

권장 영상 길이는 약 **6분 30초**다.

---

## 2. 촬영 전 준비

### 하드웨어

- Basys3 USB 케이블 연결
- 전원 스위치 ON
- JTAG와 UART 장치가 모두 인식되는지 확인
- 보드가 잘 보이는 짧은 외부 카메라 화면 준비

### 화면

- 화면 녹화 해상도: 1920×1080
- 브라우저 배율: 90% 또는 전체 비교 패널이 보이는 수준
- 터미널 글자 크기: 16 pt 이상
- 개인 경로, 알림, 불필요한 창은 미리 정리
- Vivado 전체 Build는 촬영 중 실행하지 않는다. 이미 생성된 Bitstream과
  Report를 사용한다.

### GUI 실행

프로젝트 루트에서 실행한다.

```bash
git clone https://github.com/yoon3226/EdgeScope-Lite-SoC.git
cd EdgeScope-Lite-SoC
python3 scripts/cpu_polling_gui.py
```

브라우저가 자동으로 열리지 않으면 다음 주소를 연다.

```text
http://127.0.0.1:8765
```

전체 화면 구도는
[`edgescope_abc_gui_preview.png`](edgescope_abc_gui_preview.png)를 참고한다.

### 비교군별 프로그램 명령

A:

```bash
vivado -mode batch \
  -source comparison/cpu_polling/vitis/program_bitstream.tcl
```

B:

```bash
vivado -mode batch \
  -source comparison/edgescope_lite/vitis/program_bitstream.tcl
```

C:

```bash
vivado -mode batch \
  -source comparison/vivado_ila/vitis/program_bitstream.tcl
```

C에는 반드시 ELF가 삽입된
`comparison/vivado_ila/vitis_artifacts/vivado_ila_app.bit`을 사용한다.
`comparison/vivado_ila/hw/vivado_ila_reference.bit`은 소프트웨어가 들어 있지
않은 하드웨어 Bitstream이므로 단독 시연에 사용하지 않는다.

비교군을 다시 프로그램하면 UART 연결이 끊길 수 있다. GUI에서 포트를
새로고침하고 다시 연결한다.

### 프로그램 전환과 GUI 탭의 관계

GUI 상단의 `A · CPU Polling`, `B · EdgeScope-Lite`, `C · Vivado ILA`
탭은 **표시·명령 대상을 선택할 뿐 FPGA를 다시 프로그램하지 않는다.**
비교군을 바꿀 때는 반드시 다음 순서를 지킨다.

1. 위의 해당 `program_bitstream.tcl`을 터미널에서 실행하고 PASS를 확인
2. GUI에서 UART 포트를 새로고침하고 다시 `연결`
3. 상단 상태와 UART Activity에서 해당 READY marker 확인
4. 해당 탭을 선택한 뒤 캡처 버튼 실행

| 비교군 | 확인할 READY marker | Live 화면 표시 |
|---|---|---|
| A | `CPU_POLLING_REFERENCE_READY` | 상단 `LIVE · A · CPU Polling`, Capture Metrics `LIVE UART` |
| B | `EDGESCOPE_LITE_REFERENCE_READY` | 상단 `LIVE · B · EdgeScope-Lite`, Capture Metrics `LIVE UART` |
| C | `VIVADO_ILA_REFERENCE_READY` | 상단 `LIVE · C · Vivado ILA`; 캡처 성공 후 `MEASURED · VIVADO ILA JTAG CSV` |

C 탭의 캡처 요청은 현재 GUI에서 `program:false`로 실행된다. 즉, C 버튼은
Bitstream을 바꾸지 않고 이미 프로그램된 C Bootable Bitstream의 ILA만
ARM한다. A나 B Bitstream이 올라간 상태에서 C 버튼을 누르면 안 된다.

### 버튼과 Evidence 표시 확인

- A/B Live에서는 `Rising`, `Falling`, `Pattern`, `Pattern Hold`,
  `Benchmark`, `Pulse Stress`, `Zero Mask`가 기존 UART 단일 문자 명령을
  전송한다.
- C Live에서는 `Rising`, `Falling`, `Pattern`, `Pattern Hold`만 자동 JTAG
  캡처를 시작한다. GUI는 ILA의 `ARMED` marker를 받은 뒤에만 UART
  `r/f/p/h`를 보낸다.
- C Live의 `Benchmark`는 새 자극을 보내지 않고 `100.00 MS/s` sample
  clock 카드를 다시 보여준다.
- C Live의 `Pulse Stress`와 `Zero Mask`는 ARM 없는 자극을 막기 위해
  차단되며, 전용 ILA re-arm 절차가 필요하다는 안내만 표시한다.
- `데모 모드`에서는 어떤 하드웨어 명령도 보내지 않는다. A는 저장된 UART
  기록, B/C는 `DEMO · SYNTHETIC` 미리보기를 표시한다.
- 파일로 불러온 C CSV는 `IMPORTED · VIVADO ILA CSV`이며 자동 JTAG 실측의
  `MEASURED`와 구분한다.

---

## 3. 본편 촬영 시나리오

### 0:00–0:20 — 제목과 목표

화면:

- Basys3 보드 3초
- A/B/C 통합 GUI 전체 화면
- 제목 자막

자막:

```text
EdgeScope-Lite
CPU Polling vs Custom Hardware vs Vivado ILA
```

내레이션:

> 이번 영상에서는 FPGA 내부 8채널 신호를 관측하는 세 가지 방식을
> 비교합니다. A는 CPU Polling, B는 직접 제작한 EdgeScope-Lite,
> C는 Xilinx Vivado ILA입니다.

---

### 0:20–0:50 — 공통 비교 조건

화면:

- GUI 상단의 A/B/C 탭을 차례로 가리킨다.
- 파형의 8개 채널과 Trigger 512 위치를 확대한다.

자막:

```text
Common Conditions
100 MHz · 8 Channels · 1,024 Samples · Trigger Index 512
```

내레이션:

> 세 비교군은 모두 같은 Basys3와 같은 Test Pattern Generator를
> 사용합니다. 캡처 길이는 1,024개이며, Trigger 이전 512개와 Trigger를
> 포함한 이후 512개가 보이도록 조건을 통일했습니다.

---

### 0:50–2:00 — A: CPU Polling

촬영 전 A Bitstream을 프로그램하고 UART를 다시 연결한다.

화면 조작:

1. `A · CPU Polling` 탭 선택
2. UART 포트 선택 후 `연결`
3. `Rising 캡처`
4. Trigger index 512와 CH0의 0→1 변화를 확대
5. `Benchmark`
6. `Pulse Stress`

반드시 보여줄 값:

- 대표 처리량 약 `1.67 MS/s`
- 10 ns Pulse: `0/10`
- 100 ns Pulse: `0/10`
- 1 µs 이상 Pulse: `10/10`

내레이션:

> 먼저 A는 MicroBlaze가 AXI GPIO를 반복해서 읽는 Software Polling
> 방식입니다. Rising Trigger는 정상적으로 검출되고 Logical Index
> 512에 배치됩니다.
>
> 하지만 실제 관측 속도는 약 1.67 MS/s입니다. Pulse Stress 결과,
> 10 ns와 100 ns Pulse는 모두 놓치고, 1 마이크로초 이상부터 안정적으로
> 검출합니다. CPU가 다음 값을 읽기 전에 Pulse가 사라지기 때문입니다.

강조 자막:

```text
CPU Polling limitation
10 ns: 0/10 · 100 ns: 0/10
```

---

### 2:00–3:15 — B: EdgeScope-Lite

화면 전환 전에 B Bitstream을 프로그램하고 UART를 다시 연결한다.

화면 조작:

1. `B · EdgeScope-Lite` 탭 선택
2. `Rising 캡처`
3. `Pattern 캡처`
4. 파형 우측의 `START`, `TRIGGER`, `WRITE` 주소 확인
5. `Benchmark`
6. 실보드 결과가 준비된 경우 `Pulse Stress`

반드시 보여줄 값:

- Sample rate `100.00 MS/s`
- Samples `1,024`
- Trigger index `512`
- Trigger 전후 시간 범위 약 `-5.12 µs ~ +5.11 µs`

내레이션:

> B는 이번 프로젝트에서 직접 구현한 EdgeScope-Lite입니다.
> Probe Sampler, Trigger Engine, Circular Trace Buffer가 FPGA
> 하드웨어에서 동작합니다.
>
> 샘플링과 Trigger 판단은 100 MHz에서 매 Clock 수행되며, CPU는 캡처가
> 끝난 뒤에만 BRAM을 읽습니다. 따라서 UART 전송이나 CPU 실행 속도가
> 실시간 캡처 성능에 영향을 주지 않습니다.
>
> 파형은 Trigger를 기준으로 시간순으로 재정렬되며, START, TRIGGER,
> WRITE 주소를 통해 Circular Buffer가 실제로 Wrap된 경우도 확인할 수
> 있습니다.

강조 자막:

```text
EdgeScope-Lite
100 MS/s hardware capture · CPU-independent
```

---

### 3:15–4:35 — C: Vivado ILA

화면 전환 전에 C Bootable Bitstream을 프로그램하고 UART를 다시 연결한다.

화면 조작:

1. `C · Vivado ILA` 탭 선택
2. `Rising 캡처`
3. 캡처 진행 상태를 기다린다.
4. 우측 `Capture Metrics` 제목 옆의
   `MEASURED · VIVADO ILA JTAG CSV` 표시 확인
5. Samples `1,024`, Sample rate `100.00 MS/s`, Trigger `512` 확인
6. `Pattern 캡처` 또는 `Pattern Hold`를 한 번 더 실행

내레이션:

> C는 비교 기준인 Vivado ILA입니다. GUI가 먼저 Hardware Manager를
> 통해 ILA Trigger를 설정하고 ARM합니다. `VIVADO_ILA_ARMED`가 확인된
> 뒤에만 UART로 Test Pattern Generator를 시작합니다.
>
> 캡처가 끝나면 JTAG로 1,024개 Sample을 가져와 CSV로 저장합니다.
> GUI는 Sample 누락과 중복, Trigger 개수, Trigger index 512를 검사한
> 뒤 조건을 모두 만족한 경우에만 MEASURED로 표시합니다.
>
> B와 C는 모두 100 MHz 동기 캡처이므로 같은 Trigger 위치와 같은 시간
> 범위의 파형을 확인할 수 있습니다.

강조 자막:

```text
Vivado ILA reference
ARM → UART stimulus → JTAG CSV → Integrity check
```

주의:

- C 실측에서는 `Rising`, `Falling`, `Pattern`, `Pattern Hold`를 사용한다.
- C의 `Pulse Stress`와 `Zero Mask`는 각 Trial마다 ILA를 다시 ARM하는
  전용 절차가 필요하므로 본 실측 장면에서는 누르지 않는다.
- 상태가 `DEMO · SYNTHETIC C PREVIEW`이면 실측 장면으로 사용하지 않는다.

---

### 4:35–5:35 — A/B/C 성능과 자원 비교

화면:

- 우측 `A/B/C Capture Comparison`
- 우측 `Implementation Comparison`
- 필요하면 브라우저를 약간 아래로 스크롤

중요: Bitstream을 바꾸고 UART를 다시 연결하면 GUI의 이전 Live UART
transcript는 초기화된다. 따라서 이 장면에서 세 Capture rate를 동시에
보여주려면 `데모 모드`로 전환하고, A는 저장된 UART 기록이며 B/C에는
`DEMO` 배지가 붙은 사양 기반 미리보기라고 명확히 설명한다. 세 Build의
`Implementation Comparison` 표는 데모 여부와 무관한 실제 Vivado Report
값이다. 현재 Live 데이터만 보여줄 경우에는 비어 있는 다른 비교군 값을
실측 결과처럼 설명하지 않는다.

화면에 표시할 표:

| 비교군 | LUT | FF | BRAM Tile | WNS |
|---|---:|---:|---:|---:|
| A | 2,782 | 2,560 | 32.0 | +0.939 ns |
| B | 3,205 | 3,046 | 33.0 | +0.832 ns |
| C | 3,726 | 4,230 | 32.5 | +1.262 ns |

내레이션:

> A는 전용 캡처 하드웨어가 없어 자원 사용량은 가장 작지만, 실제 관측
> 속도와 짧은 Pulse 검출에 한계가 있습니다.
>
> B와 C를 비교하면 EdgeScope-Lite는 Vivado ILA보다 LUT를 약 14퍼센트,
> Flip-Flop을 약 28퍼센트 적게 사용합니다. B는 전용 Capture BRAM 때문에
> C보다 BRAM Tile을 0.5 더 사용합니다.
>
> 세 설계 모두 100 MHz Timing Constraint를 만족했으며, Timing 실패
> Endpoint는 0개입니다.

주의:

- A는 기능적 Baseline이므로 A와 B의 단순 자원 차이를 “절감률”로
  표현하지 않는다.
- 공식 자원 절감 표현은 동일한 하드웨어 캡처 방식인 B와 C 사이에만
  사용한다.

---

### 5:35–6:15 — 결론

화면:

- 편집할 때 앞서 촬영한 A, B, C 실측 장면을 각각 1초씩 다시 삽입
- 마지막 화면은 앞서 별도로 저장한 B Live Rising 파형 또는 B PNG
- `PNG 저장`을 눌러 결과 저장 장면 표시

C Bitstream이 프로그램된 상태에서 단순히 B 탭만 선택해 B Live 화면처럼
보이게 하지 않는다. 마지막 B 파형을 GUI에서 새로 촬영하려면 B Bitstream을
다시 프로그램하고 UART READY를 확인한다. 재프로그램 시간을 줄이려면 B
구간에서 `PNG 저장`으로 확보한 이미지를 마지막 장면에 재사용한다.

내레이션:

> A CPU Polling은 간단하지만 짧은 이벤트를 놓쳤습니다. C Vivado ILA는
> 강력한 기준 도구지만 JTAG와 Vivado Hardware Manager가 필요합니다.
>
> B EdgeScope-Lite는 100 MHz 전용 하드웨어 캡처를 수행하고, CPU와
> 독립적으로 Trigger 전후 데이터를 저장합니다. 또한 UART 기반 독립
> Viewer를 사용할 수 있어 임베디드 환경에 통합하기 쉽습니다.
>
> 따라서 이번 프로젝트에서는 CPU Polling의 한계를 해결하면서 Vivado
> ILA와 비교 가능한 Custom Logic Analyzer를 구현했습니다.

마지막 자막:

```text
EdgeScope-Lite
100 MS/s · 8 Channels · 1,024 Samples
Custom Embedded Logic Analyzer
```

---

## 4. 보드 연결이 불안정할 때의 대체 시나리오

실제 B/C 캡처가 촬영 직전에 실패하면 GUI의 `데모 모드`로 화면 흐름을
설명할 수 있다. 이때 다음 원칙을 반드시 지킨다.

- `DEMO`, `SYNTHETIC`, `예상` 배지를 화면에서 자르지 않는다.
- A는 저장된 Basys3 UART 실측 결과임을 설명한다.
- B/C 파형과 Pulse 결과는 설계 사양에 따른 미리보기라고 설명한다.
- Vivado Implementation 자원과 Timing 값은 실제 Build Report 결과라고
  구분한다.
- “B/C 실측 완료”라고 말하지 않는다.

대체 내레이션:

> 현재 화면의 A는 저장된 Basys3 UART 실측 결과입니다. B와 C는 보드
> 연결 없이 GUI 흐름을 확인하기 위한 Synthetic Preview입니다.
> 자원과 Timing 표는 실제 Vivado Implementation Report에서 읽은
> 결과이며, B/C Trigger 실측은 JTAG와 UART 연결 후 같은 화면에
> MEASURED로 표시됩니다.

대체 영상에서는 제목에도 다음 문구를 넣는다.

```text
GUI PREVIEW / HARDWARE CAPTURE DEMONSTRATION FLOW
```

---

## 5. 촬영 중 자주 발생하는 문제

### UART 포트가 보이지 않음

1. Basys3 USB 연결과 전원을 확인한다.
2. GUI에서 새로고침 버튼을 누른다.
3. `pyserial` 설치 여부를 확인한다.

```bash
python3 -m pip install pyserial
```

### Bitstream 변경 후 GUI가 응답하지 않음

Bitstream 프로그램 과정에서 UART가 끊긴 것이다.

1. GUI에서 UART 포트 새로고침
2. 같은 포트 다시 선택
3. `연결`
4. 필요하면 Basys3 Reset

### C 캡처가 ARM 단계에서 실패함

- Basys3 JTAG 연결 확인
- 다른 Vivado Hardware Manager 창 종료
- C Bootable Bitstream과 C LTX가 같은 Build인지 확인
- `hw_server`가 기존 세션에 점유되지 않았는지 확인

다시 프로그램할 때는 다음 스크립트를 사용한다.

```bash
vivado -mode batch \
  -source comparison/vivado_ila/vitis/program_bitstream.tcl
```

### 영상 중 긴 대기 시간이 발생함

Vivado 합성·Implementation은 영상에서 재실행하지 않는다. 다음 증거만
보여준다.

- GUI의 Implementation Comparison
- `comparison/*/reports/utilization.rpt`
- `comparison/*/reports/timing_summary.rpt`
- 생성된 Bitstream, ELF, XSA, LTX 파일

---

## 6. 최종 촬영 체크리스트

- [ ] 영상 제목에 A/B/C 비교 방식 표시
- [ ] 공통 조건 100 MHz·8채널·1,024 Sample·Trigger 512 설명
- [ ] A의 1.67 MS/s와 짧은 Pulse 누락 표시
- [ ] B의 100 MS/s, Circular Buffer 주소와 파형 표시
- [ ] C의 ILA ARM 및 `MEASURED · VIVADO ILA JTAG CSV` 표시
- [ ] B/C가 같은 100 MHz 동기 캡처임을 설명
- [ ] A/B/C Implementation 표 표시
- [ ] B가 C 대비 LUT 14%, FF 28% 절감이라고 정확히 설명
- [ ] DEMO 결과를 실측이라고 표현하지 않음
- [ ] 마지막에 EdgeScope-Lite의 목적과 장점 한 문장으로 정리
