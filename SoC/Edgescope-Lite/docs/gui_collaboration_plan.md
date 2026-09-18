# GUI 공동작업 계획

> 상태: **Proposed — Stage 1 팀 승인 전**
>
> 실제 담당자: **TBD**
>
> 목표: **UART Protocol v1 + Chrome Web Serial Dashboard**

## 1. 목적과 범위

이 문서는 EdgeScope-Lite의 현재 UART 최종 시연을
**9,600 baud Compact Hex + Chrome Web Serial Dashboard**로 확장하기 위한
역할, 단계, 공통 규칙과 완료 조건을 정의한다.

목표는 Basys3의 Capture 결과를 처음 보는 사람도 다음 내용을 파형과 상태
카드로 바로 이해할 수 있게 하는 것이다.

- 8개 Digital Channel의 시간순 1,024 Sample
- Logical Index 512의 Trigger 위치
- Rising CH0, Falling CH1, Masked Pattern 조건
- Divider 1/8과 Sample 시간
- Circular 주소, Trigger Count, BRAM Freeze와 Checksum 검사 결과
- Timeout, Retry와 Serial 연결 상태

현재 사람이 읽는 최종 시연 프로그램은 그대로 기준 동작으로 유지한다.
이 문서의 Compact Hex 형식은 **Stage 1에서 승인할 초기 제안**이며, 승인
뒤 생성할 `docs/uart_protocol_v1.md`가 실제 Wire Format의 단일 기준이 된다.

## 2. 기준 문서와 변경 권한

| 구분 | 단일 기준 |
|---|---|
| Frozen Hardware/Trace 규격 | [day1_common_spec.md](day1_common_spec.md) |
| 현재 보드 시연 동작 | [Vitis Final Demo](../sw/vitis_app/README.md) |
| Git Branch와 PR 규칙 | [CONTRIBUTING.md](../CONTRIBUTING.md) |
| GUI 역할·단계·완료 조건 | 이 문서 |
| UART Wire Format | Stage 1 승인 뒤 만들 `docs/uart_protocol_v1.md` |

UART Protocol 변경은 Firmware, GUI, Protocol/QA 담당자가 모두 승인해야
한다. Frame Field를 변경하면 Firmware Formatter, Dashboard Parser,
Golden Fixture와 Protocol 문서를 같은 변경에서 함께 갱신한다.

UART Protocol 때문에 `sw/include/logic_analyzer_regs.h` 또는 RTL ABI를
변경하지 않는다. Hardware Register 변경이 필요한 경우 별도의 공용 사양
PR로 분리한다.

## 3. 권장 역할 분담

실제 담당자의 GitHub 이름은 Issue 생성 시 지정한다. 이름이 정해지기
전까지 다음 A/B/C 역할을 사용한다.

| 역할 | 소유 영역 | 주요 산출물 | 필수 검토 |
|---|---|---|---|
| A. Firmware | `sw/vitis_app/` | Compact Frame 출력, 상태 Event, Host Test | B와 C |
| B. Web GUI | `dashboard/src/app/`, `transport/`, `ui/` | Web Serial 연결, 화면, 8채널 파형 | A와 C |
| C. Protocol/QA | Protocol 문서, `dashboard/src/protocol/`, Test/Fixture | Parser, Golden Data, 보드 인수시험 | A와 B |

### A. Firmware 담당

소유 파일:

```text
sw/vitis_app/src/edge_scope_uart_protocol.c
sw/vitis_app/src/edge_scope_uart_protocol.h
sw/vitis_app/src/main.c
sw/vitis_app/src/UserConfig.cmake
sw/vitis_app/tests/test_edge_scope_uart_protocol.c
```

주요 작업:

1. Capture Metadata와 상태를 Machine-readable Frame으로 출력한다.
2. 세 Demo 모두 START_ADDR 기준 시간순 1,024 Sample을 전송한다.
3. Frame CRC16과 별도의 1,024-byte Capture Sample FNV32를 계산한다.
4. 기존 `s`와 `f`, 재동기화용 `?` 단일 Byte 입력을 처리한다.
5. Compact Export는 기존 `full_dump`와 독립적으로 세 Demo 모두에서
   CLEAR 전에 수행한다.
6. Compact Frame을 항상 출력하고 기존 1,024줄 Text Dump는 끈다.
   사람용 요약과 Trigger 주변 Window는 유지한다.
7. 기존 `edge_scope_lite_control.*`, Frozen Register Header와 RTL은
   원칙적으로 수정하지 않는다.

### B. Web GUI 담당

권장 소유 구조:

```text
dashboard/
├── index.html
├── package.json
├── README.md
├── src/
│   ├── main.ts
│   ├── styles.css
│   ├── app/
│   ├── transport/
│   │   ├── mockTransport.ts
│   │   └── webSerialTransport.ts
│   └── ui/
│       ├── waveformCanvas.ts
│       ├── demoPanel.ts
│       ├── validationPanel.ts
│       └── rawLog.ts
└── tests/
```

주요 작업:

1. Mock/Live Transport를 같은 Interface로 구현한다.
2. Connect/Disconnect와 상태에 맞는 `s`/`f` 전송 버튼을 구현한다.
   재연결 뒤에는 `?`를 보내 현재 대기 상태를 다시 받는다.
3. 8개 Digital Channel과 `SW[7:0]` Hex Bus를 Canvas에 그린다.
4. Index 512 Trigger Marker와 Trigger 주변 확대 보기를 제공한다.
5. Demo 상태, Divider, 주소, Count, Freeze와 Checksum 결과를 표시한다.
6. 손상 Frame과 Timeout이 이전 정상 파형을 덮어쓰지 않게 한다.
7. Firmware의 안정성 검사가 끝난 `GO` 상태에서만 Trigger 조작을 안내한다.

### C. Protocol/QA 담당

소유 파일:

```text
docs/uart_protocol_v1.md
docs/gui_test_plan.md
dashboard/src/protocol/
dashboard/tests/
dashboard/tests/fixtures/
```

주요 작업:

1. Protocol Parser와 Capture Assembler를 구현한다.
2. Rising/Falling/Pattern/Timeout Golden Fixture를 만든다.
3. 임의 Byte Chunk, CRLF 분할과 여러 Frame 동시 수신을 시험한다.
4. Hex, CRC, Length, Offset, 순서와 중복 오류를 시험한다.
5. 실제 Basys3 인수시험과 발표 체크리스트를 관리한다.

### 2명일 때

B와 C를 한 사람이 함께 맡는다. A는 Firmware와 실제 보드 출력을,
B/C는 Parser, GUI와 Mock Test를 담당하며 서로의 PR을 필수 검토한다.

## 4. 작업 의존 관계

```text
PR #2: Final Demo Baseline 병합
└── PR A: UART Protocol v1 승인
    ├── PR B: Firmware Compact Frame
    ├── PR C: Parser/Test/Golden Fixture
    └── PR D: Mock-first Web Dashboard

PR B + PR C + PR D 병합
└── PR E: Basys3 GUI Integration
```

PR B, C와 D는 승인된 Protocol 문서와 Capture Model을 기준으로 각자의
Branch에서 병렬 개발한다. C의 Parser PR을 먼저 병합하고, B는 UI를 Mock
Capture Model로 개발한 뒤 자신의 PR을 Ready로 바꾸기 전에 최신 `main`을
반영해 실제 Parser와 연결한다.

## 5. Issue, Branch와 PR 계획

| 순서 | Issue 제목 | Branch | 담당 | 선행 조건 |
|---:|---|---|---|---|
| 0 | `[Baseline] Merge final Vitis demo` | `agent/publish-final-demo` | A+C | 없음 |
| 1 | `[Protocol] Freeze ESL UART Protocol v1` | `docs/uart-protocol-v1` | C, A+B 검토 | 0 |
| 2 | `[Firmware] Emit compact capture frames` | `feature/firmware-protocol` | A | 1 |
| 3 | `[Dashboard] Build Web Serial waveform UI` | `feature/web-dashboard` | B | 1 |
| 4 | `[QA] Add parser and golden fixtures` | `feature/protocol-parser-fixtures` | C | 1 |
| 5 | `[Integration] Run Basys3 GUI acceptance` | `feature/gui-integration` | C, A+B 지원 | 2+3+4 |

각 담당자는 Protocol PR이 `main`에 병합된 뒤 자신의 작업 환경에서 다음과
같이 Branch를 만든다.

```bash
git switch main
git pull --ff-only
git switch -c feature/<name>
```

한 Branch는 한 목적만 가지며 `main`에 직접 Push하지 않는다. Draft PR에는
실행한 검사와 Mock 또는 보드 증거를 기록한다.

## 6. Stage별 진행 방법

### Stage 0 — Final Demo Baseline

완료 조건:

- Draft PR #2가 최신 `main`과 충돌 없이 병합 가능하다.
- Rising, Falling, Pattern의 기존 사람용 UART 시연이 기준 동작으로 남는다.
- XSA/Platform/BSP 선행 조건이 문서화돼 있다.

### Stage 1 — Protocol 계약

예상 시간: 2~3시간

1. 아래 초기 Frame 제안과 Field 의미를 A/B/C가 검토한다.
2. CRC와 Capture Checksum의 정확한 Byte 범위를 고정한다.
3. 정상/오류 Golden Fixture를 문서와 함께 만든다.
4. 세 담당자가 승인한 작은 문서 PR을 먼저 병합한다.

Protocol Gate:

- Version, Frame 종류, Field 폭과 숫자 진법이 고정돼 있다.
- DATA Frame 수, Offset, Length와 Sample 순서가 고정돼 있다.
- Timeout, Error와 알 수 없는 사람용 Log 처리 규칙이 고정돼 있다.
- Capture 재시도마다 바뀌는 Transaction ID 규칙이 고정돼 있다.
- `s`/`f` 단일 Byte 명령과 허용 상태가 고정돼 있다.
- 재연결 동기화용 `?` 명령과 STATE 재출력 규칙이 고정돼 있다.
- v1은 전송 재개/재전송을 지원하지 않는 것으로 시작한다.

### Stage 2 — Firmware와 Mock Dashboard 병렬 구현

예상 시간: 각각 5~10시간, 병렬 진행

Firmware 완료 조건:

- Capture마다 META 1개, DATA 16개, END 1개가 출력된다.
- DATA Offset은 `0000`부터 `03C0`까지 연속이다.
- 복원 Sample 수는 정확히 1,024개다.
- 모든 Capture 관련 Frame에 같은 Transaction ID가 있고 Retry 때 바뀐다.
- 기존 Capture 자동 검사와 `s`/`f` 동작이 유지된다.
- Vitis `-Wall -Wextra -Werror` Build가 통과한다.
- Host CRC 표준 Vector `"123456789" -> 0x29B1`이 통과한다.
- `sample[i] = i & 0xFF` 1,024-byte FNV Vector가 `0x840389C5`다.

Dashboard/Parser 완료 조건:

- 실제 보드 없이 Fixture로 세 Demo를 모두 재생할 수 있다.
- Serial Byte가 임의 위치에서 나뉘어도 Frame을 복원한다.
- 1,024 Sample과 8채널 파형, Trigger Marker를 표시한다.
- CRC, FNV, Length, 누락, 중복과 순서 오류를 구분해 표시한다.
- `npm test`, `npm run build`와 선택한 Lint가 통과한다.
- 1366×768 발표 화면에서 핵심 파형과 PASS 상태를 확인할 수 있다.

### Stage 3 — 실제 Basys3 통합

예상 시간: 4~6시간

1. 다른 Serial Terminal을 모두 종료한다.
2. Dashboard를 Local Development Server에서 실행한다.
3. Vivado/XSA와 BSP에서 AXI UARTLite가 9,600 baud인지 확인한다.
4. Connect 버튼으로 9,600 baud, 8N1 Port를 연다.
5. `GO` Event 뒤 Rising, Falling, Pattern Trigger 조작을 차례로 수행한다.
6. Timeout 뒤 Firmware 자동 복구와 새 `s`를 통한 Retry를 확인한다.
7. Idle 상태에서 USB Serial 연결 해제와 재연결을 시험한다.
8. 전송 중 연결이 끊기면 미완성 Capture를 폐기하고 Demo를 재실행한다.
9. Raw Protocol Log, GUI Screenshot과 화면 녹화를 남긴다.

Web Serial의 Port 선택은 사용자의 버튼 동작에서 요청해야 하며 Secure
Context에서 실행한다. 구현 기준은
[Chrome Web Serial Guide](https://developer.chrome.com/docs/capabilities/serial)와
[Web Serial Draft](https://wicg.github.io/serial/)를 참고한다.

### Stage 4 — 인수시험과 시연

모든 Merge Gate를 통과한 뒤 Integration PR을 Ready for review로 바꾼다.
보드 증거를 검토하고 최종 발표용 태그 또는 Release를 만든다.

## 7. Compact Hex Protocol 초기 제안

이 절은 아직 Frozen Wire Format이 아니다. Stage 1에서 변경할 수 있으며,
승인 결과는 `docs/uart_protocol_v1.md`로 이동한다.

### 공통 상수

| 항목 | 초기 제안 |
|---|---|
| UART | 9,600 baud, 8N1, Flow Control 없음, CRLF |
| Machine Prefix | `@ESL1,` |
| Capture Sample | START_ADDR 기준 시간순 BRAM Word `[7:0]` |
| Capture Depth | 1,024 Sample |
| Trigger Index | 512 (`0x0200`) |
| DATA Chunk | 64 Sample (`0x0040`) |
| DATA Frame 수 | Capture당 16개 |
| Sample Encoding | Byte당 대문자 Hex 2자리 |
| Frame Checksum | CRC-16/CCITT-FALSE |
| Capture Checksum | 시간순 1,024 Sample Byte의 FNV-1a 32-bit |
| Transaction ID | Capture Attempt마다 증가하는 32-bit, Hex 8자리 |
| 제어 입력 | 줄바꿈 없는 단일 Byte `s`, `f`, `?` |
| v1 재전송 | 미지원, 오류 시 새 Attempt로 Demo 재실행 |

64 Sample Chunk를 선택하면 한 DATA Line이 짧아져 Parser와 오류 진단이
단순해진다. Payload는 정확히 128개 대문자 Hex 문자다. DATA 16개만 약
2.8초가 필요하므로 META/END/STATE를 포함한 Machine Export 예산은
Capture당 약 3~4초로 잡고 실제 측정값을 Firmware PR에 기록한다.

### Frame 예시

```text
@ESL1,HELLO,<FW>,08,0400,0200,05F5E100*CCCC
@ESL1,STATE,<TXN>,<DEMO>,<ATTEMPT>,<STATE>,<CODE>*CCCC
@ESL1,META,<TXN>,<DEMO>,<MODE>,<DIV>,<CH>,<VALUE>,<MASK>,<STATUS>,<DEPTH>,<TRIG_INDEX>,<START>,<TRIG_ADDR>,<WRITE>,<COUNT_BEFORE>,<COUNT_AFTER>,<PASS_BITS>*CCCC
@ESL1,DATA,<TXN>,<SEQ>,<OFFSET>,<LENGTH>,<SAMPLE_HEX>*CCCC
@ESL1,END,<TXN>,0010,0400,<SAMPLE_FNV32>*CCCC
@ESL1,RESULT,<TXN>,<DEMO>,<PASS_OR_FAIL>,<PASS_BITS>*CCCC
@ESL1,ERROR,<TXN>,<DEMO>,<ERROR_CODE>*CCCC
```

모든 숫자는 고정 폭 대문자 Hex를 사용한다. `DATA`의 Offset과 Length는
Sample 단위다. Sequence는 `00`부터 `0F`, Offset은 `0000`, `0040`, ...,
`03C0` 순서이며 Length는 항상 `0040`이다. `<TXN>`은 Timeout Retry를
포함해 Capture Attempt가 시작될 때마다 바뀐다.

`CCCC`는 `@` 다음 Byte부터 `*` 직전 Byte까지의 ASCII에 적용한
CRC-16/CCITT-FALSE다. Parameter는 Poly `0x1021`, Init `0xFFFF`,
RefIn/RefOut `false`, XorOut `0x0000`이며 표준 Vector
`"123456789" -> 0x29B1`을 사용한다.

`SAMPLE_FNV32`는 전송 Payload인 시간순 1,024개 Sample Byte만 Hash한다.
현재 Firmware의 `trace_checksum_read()`는 BRAM의 1,024개 **32-bit Word**
전체, 즉 4,096 Byte를 Hash하므로 Freeze 검증용으로 계속 사용하되
`SAMPLE_FNV32`와 직접 비교하지 않는다. Protocol 구현은 시간순 Sample
Byte만 Hash하는 새 함수를 제공한다. FNV-1a Parameter는 Offset Basis
`0x811C9DC5`, Prime `0x01000193`이며 `sample[i] = i & 0xFF`인
1,024-byte Vector 결과는 `0x840389C5`다.

허용 State의 초기 제안:

```text
WAIT_START, PRE_READY, READY, GO, DONE,
WAIT_REPLAY_BEFORE, WAIT_REPLAY_AFTER, WAIT_FREEZE,
TX, TIMEOUT, RETRY, PASS, FAIL
```

기존 사람용 Log가 섞여도 Dashboard는 `@ESL1,`로 시작하지 않는 줄을
무시한다. Machine Frame 중간에는 사람용 문장이나 추가 개행을 넣지 않는다.
Dashboard Workflow는 사람용 문장을 해석하지 않고 위 STATE Event만
사용한다.

`s`는 `WAIT_START`에서만 허용한다. `f`는 Freeze/One-shot 재현이 끝나고
SW가 `0x3C`인 `WAIT_FREEZE`에서만 허용한다. `?`는 Firmware가 UART 입력을
기다리는 상태에서 HELLO와 현재 STATE를 다시 출력하며 상태를 변경하지
않는다. 세 명령 모두 CR/LF를 붙이지 않는다. Trigger 조작 안내는 `READY`가
아니라 Firmware가 안정성 검사를 끝낸 `GO` Event 뒤에 표시한다.

초기 v1의 `?`는 상태 재출력만 지원하며 Capture DATA 재전송은 지원하지
않는다. 누락, 손상, 중복 또는 역순 Frame은 해당 Transaction 전체를 실패
처리하며 새 `s`로 Demo를 다시 실행한다. Stage 1에서 범위를 늘리려면
Protocol Version과 일정을 함께 재검토한다.

## 8. 공통 시험 행렬

| 시험 | 입력 또는 조건 | Firmware/GUI 기대 결과 |
|---|---|---|
| Rising CH0 | `0x00 -> 0x01` | `[511].CH0=0`, `[512].CH0=1` |
| Falling CH1 | `0x02 -> 0x00` | Divider 8, `[511].CH1=1`, `[512].CH1=0` |
| Masked Pattern | `0x25 -> 0xA5` | `(511 & F0) != A0`, `(512 & F0) == A0` |
| One-shot | 조건 유지 또는 재진입 | Trigger Count 추가 증가 없음 |
| Timeout | `0x25` 유지 | 10초 뒤 Abort/Clear/Disable, 새 TXN과 `s`로 Retry |
| Chunk 분할 | 모든 Byte 경계의 Mock 분할 | Frame 정상 복원 |
| 손상 Frame | Hex/Length/CRC 변경 | Capture 완료 금지, 오류 표시 |
| 순서 오류 | DATA 누락·중복·역순 | 이전 정상 파형 유지, 오류 표시 |
| Idle 재연결 | Port 해제 후 다시 연결 | `?`로 HELLO/STATE 복원 |
| FPGA 재시작 | Frame 중간 새 HELLO | 이전 미완성 Capture 폐기 |

## 9. 공통 작업 규칙

1. Protocol, Firmware와 GUI는 각자의 소유 경로에서 작업한다.
2. 공용 Protocol 변경은 A/B/C의 승인을 받는다.
3. Dashboard는 완전히 검증된 END Frame 뒤에만 현재 파형을 교체한다.
4. 잘못된 Frame이나 Timeout은 이전 정상 파형을 지우지 않는다.
5. Transaction ID 또는 새 HELLO가 바뀌면 미완성 Capture를 폐기한다.
6. Serial Port는 Dashboard와 다른 Terminal이 동시에 열지 않는다.
7. GUI는 `GO` 전에는 Trigger용 Switch 변경을 요청하지 않는다.
8. XSA, BSP, ELF, bitstream, Build/cache와 개인 Device 경로는 GUI PR에
   포함하지 않는다.
9. 실제 Serial Port 이름, 계정, Token과 화면의 개인 경로를 기록하지 않는다.
10. 시연 영상은 화면 정보를 점검한 뒤 Release 또는 외부 공유 링크를 사용한다.
11. Sample 시간 표시는 Divider 1은 10 ns, Divider 8은 80 ns를 기준으로 한다.

## 10. 예상 일정

| 작업 | 예상 작업량 |
|---|---:|
| Protocol/Fixture 합의 | 2~3시간 |
| Firmware Protocol | 5~8시간 |
| Mock Dashboard/Parser | 6~10시간 |
| 실제 보드 통합 | 4~6시간 |
| 최종 QA와 시연 준비 | 2~3시간 |

총 작업량은 약 19~30인시다. 3명이 병렬로 진행하면 **약 2일의 팀 경과
시간**을 예상한다. 이 2일은 Codex의 코드 생성 시간만 뜻하지 않으며,
상호검토, 실제 Basys3 스위치 조작, USB 연결과 보드 인수시험을 포함한다.

- 3명 병렬: 약 1.5~2일
- 2명 병렬: 약 2~3일
- 1명 순차: 약 3~4일

## 11. 최종 완료 정의

- Rising, Falling, Pattern의 1,024 Sample 파형이 모두 표시된다.
- 모든 파형에서 Trigger Marker가 Logical Index 512에 있다.
- Divider, Sample 시간과 Trigger 조건이 올바르게 표시된다.
- Frame CRC와 Capture FNV가 모두 일치한다.
- AXI UARTLite Hardware/BSP 설정이 실제 9,600 baud로 확인된다.
- Timeout과 손상 Frame이 명확한 오류로 표시된다.
- Clear/Re-arm 뒤 세 Demo를 한 Session에서 연속 실행할 수 있다.
- Mock Test, Dashboard Build와 Vitis Build가 통과한다.
- 실제 Basys3 GUI 시연 증거와 검사 결과가 Integration PR에 첨부된다.
