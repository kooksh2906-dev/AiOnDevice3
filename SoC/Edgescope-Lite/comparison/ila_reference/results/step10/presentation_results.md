# Step 10 발표용 결과 문안

패키지 표시: **검증된 Draft — Custom 전체 Routed 자료 대기**

## 한 문장 결론

> Vivado ILA 기준군은 Basys 3에서 100 MHz·8채널·1,024 Sample 조건으로
> Rising, Falling, Masked Pattern Trigger와 10 ns~1 ms 동기 Pulse
> 60/60회를 검출했고, 전체 Routed 기준 순증가 자원은 LUT
> +1,041, FF
> +1,775, RAMB18
> +1이었다.

## 슬라이드 1 — 기능 검증

- 제목: `VIVADO ILA REFERENCE — HARDWARE VERIFIED`
- 핵심 숫자: `1,024 Samples`, `Trigger Index 512`, `100 MHz`
- 증거: Rising `0x00→0x01`, Falling `0x01→0x00`,
  Pattern `0x95→0xA5`가 모두 Sample 512에서 Trigger
- 보조 문장: No-trigger 103 ms 동안 오검출과 Partial Capture 없음

## 슬라이드 2 — Pulse Stress

- 제목: `60 / 60 SYNCHRONIZED PULSES DETECTED`
- 범위: `10 ns, 100 ns, 1 µs, 10 µs, 100 µs, 1 ms`
- 조건: 각 폭 10회, FPGA Program 1회, Trigger Index 512 고정
- 표현 주의: `동기 Pulse 시험 결과`라고 명시

## 슬라이드 3 — 자원·Timing

- ILA Total: LUT `3,726`,
  FF `4,230`,
  RAMB36/18 `32/1`
- Common 대비 ILA Delta: LUT `+1,041`,
  FF `+1,775`,
  RAMB18 `+1`
- 100 MHz Timing: WNS `+1.544 ns`,
  TNS `0.000 ns`
- 공식 Custom-vs-ILA 절감률: `PENDING_CUSTOM`

## 말해도 되는 내용

- “ILA 기준군 자체의 기능·Pulse·자원·Timing 검증은 완료됐다.”
- “CPU Polling의 Routed 보고서는 참고 Total로 검증했다.”
- “공식 절감률은 기능적으로 동등한 Custom과 ILA 사이에서만 계산한다.”

## 아직 말하면 안 되는 내용

- “Custom이 ILA보다 몇 % 절감됐다.” — `PENDING_CUSTOM`
- “CPU Polling이 100 MS/s Logic Analyzer와 동급이다.”
- “WNS를 이용해 최대 동작 주파수를 계산했다.”
- “10 ns 비동기 Pulse를 항상 잡는다.”

## 시각 자료

- `ila_result_cards.svg`: 핵심 숫자 3개
- `ila_trigger_evidence.svg`: 실제 Capture의 Sample 511/512 전이
