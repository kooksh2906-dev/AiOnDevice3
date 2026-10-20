# Register & Hardware Settings

## GPIO 설정

| 대상 | 레지스터/비트 | 설정 | 의미 |
|---|---|---|---|
| LED Bar | `DDRD[7:0]` | `1` | PD0~PD7 출력 |
| LED Bar | `PORTD[7:0]` | 8-bit 패턴 | LED 출력값 |
| Button ON/Left | `DDRG2` / `PING2` | `DDRG2 = 0` | PG2 입력 및 값 판독 |
| Button OFF/Right | `DDRG3` / `PING3` | `DDRG3 = 0` | PG3 입력 및 값 판독 |
| Button Toggle/Off | `DDRG4` / `PING4` | `DDRG4 = 0` | PG4 입력 및 값 판독 |

## DDRx, PORTx, PINx 관계

- `DDxn = 1`: 해당 핀을 출력으로 설정합니다.
- `DDxn = 0`: 해당 핀을 입력으로 설정합니다.
- 입력 모드에서 `PORTxn = 1`: 내부 Pull-up을 활성화합니다(`SFIOR.PUD = 0` 전제).
- 입력 모드에서 `PORTxn = 0`: 내부 Pull-up을 끄고 High-Impedance 입력으로 둡니다.
- `PINxn`: 핀에 실제로 들어온 논리값을 읽습니다.

본 실습은 외부 10 kOhm Pull-up 저항을 전제로 하므로 Button 모듈은 `PORTG` 내부 Pull-up을 켜지 않습니다.

데이터시트에 따르면 Reset 직후 `PORTG`와 `DDRG`의 초기값은 모두 0입니다. 따라서 원본 실습처럼 Reset 직후 실행하는 단독 프로그램에서는 외부 Pull-up 입력 조건이 성립합니다. 개선 버전은 이전 코드가 `PORTG`를 변경했을 가능성까지 고려하여 해당 `PORTG` 비트를 명시적으로 0으로 지웁니다.

## Port G 겸용 기능 주의

| GPIO | 겸용 기능 | 버튼 입력 사용 조건 |
|---|---|---|
| PG2 | ALE(외부 메모리 Address Latch Enable) | 외부 메모리 인터페이스 비활성 |
| PG3 | TOSC2(Timer0 RTC Oscillator) | `ASSR.AS0 = 0` |
| PG4 | TOSC1(Timer0 RTC Oscillator) | `ASSR.AS0 = 0` |

- ATmega103 호환 모드에서는 Port G를 일반 GPIO로 사용할 수 없습니다.
- `PING`는 DDR 방향과 무관하게 실제 핀 값을 읽지만, 핀 입력은 내부 Synchronizer를 거쳐 짧은 전파 지연이 생깁니다.

## Active-Low 입력

| 버튼 상태 | PG 핀 전압 | `PING & mask` | 코드 판정 |
|---|---:|---:|---|
| 놓음 | High | 0이 아님 | Released |
| 누름 | Low | 0 | Pressed |

## 회전 연산

- Rotate-Left: `(value >> 7) | (value << 1)`
- Rotate-Right: `(value >> 1) | (value << 7)`

`uint8_t`에 다시 저장되면서 8-bit 범위를 벗어난 상위 비트는 제거됩니다. 개선 버전에서는 의도를 드러내기 위해 결과를 `uint8_t`로 명시 변환합니다.

## Timing

- VER2: 버튼을 누른 동안 200 ms 간격으로 LED 비트를 이동합니다.
- VER3: 상태 전이 감지 후 50 ms를 기다리지만 입력을 재확인하지 않습니다.
- VER4: 상태 변화 감지 후 50 ms를 기다린 뒤 입력을 다시 읽어 안정된 변화만 이벤트로 확정합니다.
- 모든 지연은 `_delay_ms()`를 사용하는 Blocking Delay이며, 정확한 시간 계산에는 올바른 `F_CPU` 빌드 설정이 필요합니다.

