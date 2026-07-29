# EdgeScope-Lite Web Dashboard

역할 B가 소유하는 Mock-first Chrome Web Serial Dashboard입니다. 실제 보드가
없어도 Rising CH0, Falling CH1, Masked Pattern Capture를 재생하고, 8개
Digital Channel과 `SW[7:0]` Hex Bus를 1,024 Sample 파형으로 확인할 수
있습니다.

현재 `docs/uart_protocol_v1.md`는 아직 승인되지 않았습니다. 따라서 이
Dashboard는 제안 중인 Wire Format을 임의로 확정하거나 역할 C의 Parser,
CRC/FNV 검사, Capture Assembler를 대신 구현하지 않습니다. Live 수신
Byte는 `ProtocolBridge` 경계를 통해 검증된 Semantic Event가 된 뒤에만
파형에 반영됩니다.

## 실행

Node.js 20.19+, 22.12+ 또는 24+를 사용합니다.

```bash
cd dashboard
npm ci
npm run dev
```

Chrome에서 `http://127.0.0.1:4173`을 엽니다. Mock 사용 순서는 다음과
같습니다.

1. `Mock fixture`와 Demo/Scenario를 선택합니다.
2. `연결`을 누릅니다.
3. `WAIT_START`에서 `Capture 시작 (s)`을 누릅니다.
4. `GO`에서만 표시되는 Trigger 조작 안내를 확인합니다.
5. `WAIT_FREEZE`에서 `Freeze 완료 (f)`을 누릅니다.
6. 검증된 Capture가 파형과 Validation 카드에 표시되는지 확인합니다.

Scenario에서 Timeout 또는 `검증 거부 · CRC 모의`를 선택하면 역할 C
Parser 없이도 Capture 거부 Event가 발생했을 때 이전 정상 파형을 유지하는
UI 동작을 확인할 수 있습니다. 이 Scenario는 손상된 Wire Byte를 Parser에
통과시키는 Protocol 시험이 아닙니다.

## 화면 기능

- 8개 Digital Channel의 High/Low step waveform
- `SW[7:0]` Hex Bus run
- Logical Index 512 Trigger Marker
- 전체 `[0,1024)`와 Trigger 확대 `[448,576)` 전환
- Divider 1/8, 10 ns/80 ns Sample 시간과 Trigger 조건
- START/TRIGGER/WRITE Circular 주소와 Trigger Count
- Frame CRC, 1,024-byte Sample FNV, Length, DATA Sequence, BRAM Freeze 결과
- Firmware State, Transaction, Attempt와 상태 기반 `s`/`f` Command gating
- 최대 200개 Event의 Raw Protocol Log
- Timeout, 손상 Capture, 연결 해제 중에도 마지막 검증 파형 유지

Trigger 선은 Sample 중심이 아니라 index 512의 시작 경계에 놓입니다.
따라서 `[511] → [512]` 전이와 `t=0`이 정확히 같은 x 좌표에 표시됩니다.

## Web Serial

`Chrome Web Serial`을 선택한 뒤 `연결`을 누르면 사용자 동작 안에서 Port
선택 창을 요청하고 다음 설정으로 Port를 엽니다.

```text
9,600 baud
8 data bits
1 stop bit
parity none
flow control none
```

`s`, `f`, `?`는 CR/LF가 없는 정확한 단일 Byte로 전송됩니다. 최초 연결과
같은 페이지 Session의 재연결 모두 Reader를 먼저 시작한 뒤 `?`를 자동
전송해 현재 HELLO/STATE를 요청합니다. Web Serial은 데스크톱 Chrome의
Secure Context(HTTPS 또는 localhost)에서 사용해야 하며, 다른 Serial
Terminal과 Port를 동시에 열 수 없습니다.

## 역할 C Parser 연결점

역할 B의 데이터 경계는 다음과 같습니다.

```text
Mock/Web Serial Transport
          │ raw Uint8Array
          ▼
ProtocolBridge (역할 C 구현)
          │ 검증된 DashboardEvent
          ▼
DashboardStore → Canvas / 상태 카드 / Raw Log
```

[`src/app/protocolBridge.ts`](src/app/protocolBridge.ts)의
`ProtocolBridge`를 역할 C 구현으로 주입합니다. 단일 Composition Root인
[`src/entry.ts`](src/entry.ts)에서 기본 `PendingProtocolBridge`를 역할 C의
구현으로 교체하면 됩니다. Side-effect가 없는 `bootstrapDashboard()`는
[`src/main.ts`](src/main.ts)에 분리돼 있어 중복 UI를 먼저 생성하지 않습니다.
기본 Pending 구현은 Live Byte를 Raw Log에만 남기며 파형을 변경하지
않습니다.

역할 C 구현은 다음 조건을 만족한 뒤에만 `capture` Event를 내보내야 합니다.

- META 1개, DATA 16개, END 1개가 같은 Transaction에 속함
- 1,024개 Sample이 START_ADDR 기준 시간순으로 완성됨
- CRC, FNV, Hex, Length, Offset, 누락, 중복, 순서 검증 통과
- 새 HELLO, Transaction 변경, Timeout 또는 연결 해제 때 미완성 Capture 폐기

`SAMPLE_FNV32`는 시간순 1,024 Sample Byte의 Hash입니다. Firmware의 BRAM
Freeze 검사용 `trace_checksum_read()`는 1,024개의 32-bit Word, 즉 4,096
Byte를 Hash하므로 같은 값으로 표시하거나 비교하면 안 됩니다.

## 검사

```bash
npm run lint
npm test
npm run build
```

역할 B 단위시험은 소유 경계를 지키기 위해 `src/**/*.test.ts`에
co-locate했습니다. `dashboard/tests/`, `dashboard/tests/fixtures/`,
`dashboard/src/protocol/`은 역할 C가 Golden Fixture와 Protocol QA를
추가할 공간으로 남겨 둡니다.

현재 자동시험은 다음을 확인합니다.

- 세 Demo의 1,024 Sample과 index 511→512 Trigger 조건
- Capture Model/주소/검증 오류 거부
- 오류, Timeout, Disconnect 뒤 마지막 정상 Capture 유지
- `WAIT_START`의 `s`, `WAIT_FREEZE`의 `f`, `GO` 안내 gating
- `[448,576)` Trigger 확대와 정확한 x 경계
- Mock 정상/Timeout/CRC 거부 Event/재연결 Workflow
- Web Serial 9,600 8N1, 정확한 단일 Byte Command와 종료 순서

실제 `@ESL1` Chunk 분할/CRC/FNV/누락/중복/순서 시험과 Basys3 인수시험은
Protocol v1 승인 및 역할 A/C 구현 병합 뒤 수행합니다.
