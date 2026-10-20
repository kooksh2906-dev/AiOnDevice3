# Register & Hardware Settings

## 출력 핀

| Timer 채널 | 핀 | DDR 설정 | 기능 |
|---|---|---|---|
| Timer0 OC0 | PB4 | `DDB4 = 1` | Compare/PWM 파형 출력 |
| Timer1 OC1A | PB5 | `DDB5 = 1` | Channel A Compare/PWM 파형 출력 |

`COM` 비트가 일반 PORT 기능을 Timer 출력으로 Override하더라도 출력 Driver 방향은 DDRB가 결정하므로 해당 DDR 비트를 반드시 1로 설정해야 합니다.

## Timer0 주요 레지스터

| 레지스터 | 주요 비트/값 | 역할 |
|---|---|---|
| `TCCR0` | `WGM01:0` | Normal, Phase Correct PWM, CTC, Fast PWM 선택 |
| `TCCR0` | `COM01:0` | OC0 연결 및 Toggle/Clear/Set 동작 선택 |
| `TCCR0` | `CS02:0` | Clock Source 및 Prescaler 선택 |
| `TCNT0` | 8-bit Counter | 현재 Count 또는 Normal Mode Preload |
| `OCR0` | 8-bit Compare | CTC의 TOP 또는 PWM Compare 값 |
| `TIFR` | `OCF0`, `TOV0` | Compare Match·Overflow Flag, 1을 써서 해제 |
| `ASSR` | `AS0` | 0이면 I/O Clock 기반 동기 동작, 1이면 TOSC 기반 비동기 동작 |

### Timer0 Mode

| `WGM01` | `WGM00` | Mode | TOP |
|---:|---:|---|---|
| 0 | 0 | Normal | 0xFF |
| 0 | 1 | Phase Correct PWM | 0xFF |
| 1 | 0 | CTC | OCR0 |
| 1 | 1 | Fast PWM | 0xFF |

### Timer0 Prescaler

| `CS02:0` | Clock |
|---|---|
| 001 | No Prescaling |
| 010 | /8 |
| 011 | /32 |
| 100 | /64 |
| 101 | /128 |
| 110 | /256 |
| 111 | /1024 |

Timer0은 비동기 RTC 기능을 지원하므로 `/32`, `/128` 선택지가 포함됩니다. 본 실습에서는 `ASSR.AS0=0`으로 시스템 I/O Clock을 사용합니다.

## Timer1 주요 레지스터

| 레지스터 | 주요 비트/값 | 역할 |
|---|---|---|
| `TCCR1A` | `COM1A1:0`, `WGM11:0` | OC1A 출력 동작과 Mode 하위 비트 |
| `TCCR1B` | `WGM13:2`, `CS12:0` | Mode 상위 비트와 Prescaler |
| `TCCR1C` | `FOC1A/B/C` | 비-PWM Force Compare; PWM 실습에서는 0 유지 |
| `TCNT1` | 16-bit Counter | 현재 Count |
| `ICR1` | Mode 14 TOP | PWM 주기 결정 |
| `OCR1A` | Channel A Compare | OC1A High Pulse Width/Duty 결정 |

### Timer1 Mode 14

| `WGM13` | `WGM12` | `WGM11` | `WGM10` | Mode | TOP |
|---:|---:|---:|---:|---|---|
| 1 | 1 | 1 | 0 | Fast PWM Mode 14 | ICR1 |

`COM1A1:0=10`은 비반전 출력으로, BOTTOM에서 OC1A를 Set하고 Compare Match에서 Clear합니다.

### Timer1 Prescaler

| `CS12:0` | Clock |
|---|---|
| 001 | /1 |
| 010 | /8 |
| 011 | /64 |
| 100 | /256 |
| 101 | /1024 |
| 110 | 외부 T1 Falling Edge |
| 111 | 외부 T1 Rising Edge |

## 초기화 방식

- 원형 VER1~VER6의 `|=` 방식은 Reset 직후 관련 레지스터가 모두 0인 단독 실습에서 유효합니다.
- 재사용 가능한 개선판은 Mode와 Clock 비트를 명시적으로 대입하여 이전 설정의 영향을 제거합니다.
- Timer1 개선판은 Clock 선택 전 Mode·TOP·Compare를 먼저 설정하고 마지막에 Prescaler를 연결해 Counter를 시작합니다.
- ICR1을 TOP으로 쓰는 Mode 14에서는 ICR1이 Double Buffer가 아니므로 동작 중 TOP을 낮출 때 현재 TCNT1보다 작아지지 않도록 주의해야 합니다. 본 실습은 초기화 시 고정 TOP만 설정합니다.
