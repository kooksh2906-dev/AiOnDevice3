# EdgeScope-Lite Vitis Final Demo

Basys3의 `SW[7:0]`을 8-bit 상태 버스로 사용해 Rising, Falling, Masked
Pattern Capture를 하나의 프로그램에서 연속 시연하는 Vitis 2024.2
standalone 애플리케이션입니다.

## Hardware/Platform 전제조건

- CPU: `microblaze_riscv_0`
- Domain: `standalone_microblaze_riscv_0`
- Platform component name: `logic_analyzer_HW`
- AXI UARTLite: 9,600 baud, 8N1
- AXI Timer0 clock: 100 MHz
- Circular Trace Buffer IRQ: AXI INTC input 0
- Trace BRAM window: `0xC0000000`, 4 KiB
- Capture depth/index: 1,024 / 512

Vivado XSA, bitstream, Vitis platform export와 BSP는 생성물이라 이 저장소에
포함하지 않습니다. 각 개발자는 팀 Hardware Design에서
`logic_analyzer_HW` Platform을 생성해야 합니다.
따라서 이 저장소만 Clone해서는 Vitis Build를 완전히 재현할 수 없으며,
동일한 Hardware Design에서 Export한 XSA가 먼저 필요합니다.

## 구성

```text
vitis_app/
├── vitis-comp.json
└── src/
    ├── main.c
    ├── edge_scope_lite_control.c
    ├── edge_scope_lite_control.h
    ├── platform.c
    ├── platform.h
    ├── CMakeLists.txt
    ├── UserConfig.cmake
    ├── Hello_worldExample.cmake
    └── lscript.ld
```

`UserConfig.cmake`가 `../../include`를 Include하므로 레지스터 정의의 단일
기준은 [`../include/logic_analyzer_regs.h`](../include/logic_analyzer_regs.h)
입니다.

## Vitis에서 열기

1. 팀 Hardware Design의 XSA로 `logic_analyzer_HW` Platform을 생성합니다.
2. CPU/Domain 이름이 위 전제조건과 같은지 확인합니다.
3. Existing Application Component로 이 `sw/vitis_app/` 폴더를 추가합니다.
4. `logic_analyzer_SW`을 Build하고 Basys3에 Program/Run합니다.
5. Serial Terminal을 9,600 baud, 8N1로 연결합니다.

Sampler, Trigger, Trace Buffer, Timer와 INTC의 `xparameters.h` Instance가
현재 Hardware Design과 다르면
[`src/edge_scope_lite_control.c`](src/edge_scope_lite_control.c)의 호환
매크로를 먼저 확인하십시오.

## Demo 순서

| Demo | 초기값 | Trigger 조작 | 설정 |
|---|---:|---:|---|
| 1. Device Start | `0x00` | `0x00 -> 0x01` | Divider 1, Rising CH0 |
| 2. Enable Loss | `0x02` | `0x02 -> 0x00` | Divider 8, Falling CH1 |
| 3. Fault Entry | `0x25` | `0x25 -> 0xA5` | Divider 1, Pattern `A0/F0` |

각 Demo 시작 시 초기 SW를 맞추고 UART로 소문자 `s`를 전송합니다.
`[GO]` 뒤 Trigger 조작을 수행합니다.

Capture가 끝나면 프로그램이 One-shot 조건을 자동으로 다시 관측합니다.
안내에 따라 Before/After 값을 재현한 뒤 여러 값을 시험하고, 최종적으로
`SW[7:0]=0x3C`를 유지한 상태에서 소문자 `f`를 전송합니다.

## 자동 검증

- `DONE=1`, `TRIGGERED=1`, `BUSY=0`
- `DEPTH=1024`, `TRIGGER_INDEX=512`
- `(TRIGGER_ADDR - START_ADDR) & 0x3FF == 512`
- `START_ADDR == (WRITE_ADDR + 1) & 0x3FF`
- Logical 511 -> 512 Trigger 조건
- Capture별 Trigger Count 증가량 1
- DONE 뒤 Physical BRAM Snapshot과 시간순 Checksum 불변
- One-shot 조건 재현 뒤 Trigger Count 불변
- `CLEAR_DONE`, Trace IRQ 해제, Trigger/Sampler Clear
- 10초 동안 Trigger가 없을 때 Abort/Clear/Disable 후 같은 Demo 재시도

Demo 1과 2는 Logical 508~516만 출력하고, Demo 3은 시간순 전체
1,024 Sample을 UART로 출력합니다.

## 현재 범위와 Dashboard 후속 작업

이 Snapshot은 사람이 읽는 최종 UART 시연 프로그램입니다. Compact Hex
Frame과 Chrome Web Serial Dashboard는 아직 포함하지 않으며, Firmware
Protocol과 Web UI를 독립 PR로 병렬 개발한 뒤 통합합니다.

상세 역할, 작업 단계와 공통 규격 초기 제안은
[GUI 공동작업 계획](../../docs/gui_collaboration_plan.md)을 참고하십시오.
브랜치와 Pull Request의 일반 규칙은
[CONTRIBUTING.md](../../CONTRIBUTING.md)를 따릅니다.
