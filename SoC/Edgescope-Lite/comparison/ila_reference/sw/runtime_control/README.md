# Step 6 Runtime Control Firmware

MicroBlaze RISC-V가 공통 Test Pattern Generator를 UART 명령으로 실행하도록
만든 최소 Bare-metal 펌웨어다. RV32I/ILP32 전용이며 libc를 사용하지 않는다.

## UART

- AXI UART Lite: `0x4060_0000`
- 9,600 baud, 8-N-1
- 명령 한 줄의 끝: CR 또는 LF
- 명령과 응답은 대소문자를 제외하고 ASCII다.

```text
PING
STATUS
CLEAR
RUN <id>
RUN <id> <pulse_width_cycles>
HELP
```

응답의 첫 단어는 항상 `OK` 또는 `ERR`다. 예:

```text
OK PONG
OK STATUS status=0x00000000 busy=0 done=0 control=0x00000000
OK RUN id=1 pulse=0x0000000A saw_busy=1 status=0x00000002
ERR RUN code=ID_RANGE
```

`RUN`은 매번 sticky DONE을 CLEAR한 뒤, START_LEVEL에 정확한 `0→1→0`
순서를 만들고 DONE을 제한된 횟수만큼 Polling한다. 두 번째 인자를 생략하면
Pulse Stress용 폭도 포함해 기본값 10 Clock을 쓴다.

## 빌드

```bash
comparison/ila_reference/sw/runtime_control/build.sh
```

기본 Toolchain은 Vitis 2024.2 설치 경로를 사용한다. 다른 설치를 쓸 때는
`EDGESCOPE_RISCV_TOOL_BIN`과 필요하면 `EDGESCOPE_RISCV_TOOL_PREFIX`를
지정한다.

성공 시 `build/edgescope_runtime_control.elf`와 함께 Disassembly,
ELF/Program Header, Symbol, Size, Map, SHA-256 및 검증 Manifest가
생성된다.
