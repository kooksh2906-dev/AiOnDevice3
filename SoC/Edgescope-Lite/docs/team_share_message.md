# 팀 공유 메시지

아래 내용을 팀 채팅에 그대로 전달하면 됩니다.

---

EdgeScope-Lite Day 1 공통 명세 v2.1을 공유합니다.

- Probe/sample: 8-bit
- Clock: 100 MHz
- BRAM: 1,024 × 32-bit, word address 10-bit, CPU 영역 4 KiB
- Capture: trigger 이전 512개 + trigger 포함 이후 512개
- Trigger logical index: 512
- Trigger mode: Disabled/Rising/Falling/Pattern 중 하나
- Sampler, Trigger, Trace Buffer는 각각 독립 AXI4-Lite base address 사용
- Reset과 Port 이름, register offset은 첨부 명세를 기준으로 구현

특히 `trigger_pulse`는 같은 cycle의 `sample_data/sample_valid`와 정렬해야 합니다.
Buffer는 trigger가 발생한 현재 sample을 BRAM에 쓰고 그 주소를 trigger address로
저장합니다. Register나 Port를 개별적으로 변경하지 말고 변경이 필요하면 세 명이
합의한 뒤 공통 명세, SV package, C header를 함께 수정해 주세요.

통합 ARM 순서는 반드시 아래와 같이 맞춰 주세요.

```text
Trace Buffer ARM
→ Sampler Enable
→ TRACE_STATUS.PRE_READY=1 확인
→ Trigger Engine Clear/ARM
→ TRACE_STATUS.DONE=1 대기
```

Trigger Engine을 먼저 ARM하면 Buffer의 PREFILL 중 one-shot trigger가 소진되어
캡처가 완료되지 않을 수 있습니다.

공유 파일:

1. `docs/day1_common_spec.md` — 전 팀원 필수
2. `rtl/include/logic_analyzer_pkg.sv` — RTL 담당자
3. `sw/include/logic_analyzer_regs.h` — Vitis C 담당자

---
