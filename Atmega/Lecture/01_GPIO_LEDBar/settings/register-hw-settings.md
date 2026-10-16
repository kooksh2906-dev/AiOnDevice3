# Register & Hardware Settings

## MCU와 Peripheral

- MCU: ATmega128A
- Peripheral: GPIO
- 사용 포트: PORTD
- 데이터 폭: 8-bit
- 외부 하드웨어: 8-bit LED Array Bar

## 주요 레지스터

| 레지스터 | 설정·사용 | 의미 |
|---|---|---|
| DDRD | `0xFF` | PD7~PD0 전체를 출력으로 설정 |
| PORTD | 8비트 패턴 기록 | 각 GPIO 핀의 High/Low 출력 결정 |

## 비트와 LED의 대응

- `PORTD[7:0]`의 각 비트가 LED Array Bar의 8개 입력에 대응합니다.
- `1 << i`는 선택한 비트 하나를 High로 설정하는 패턴을 만듭니다.
- OR 연산은 여러 LED 비트를 하나의 출력 패턴으로 결합합니다.
- 실제 LED 점등 논리는 보드 결선의 Active-High/Active-Low 구성에 따라 반전될 수 있습니다.

## Timing

- 출력 패턴 사이의 시간 간격은 `_delay_ms()`로 만듭니다.
- `_delay_ms()`는 Blocking Delay이므로 대기 중에는 다음 제어 코드를 수행하지 않습니다.
- 정확한 지연 계산을 위해 빌드 환경에 올바른 `F_CPU` 설정이 필요합니다.

## VER4 주소 접근

`led.port`에 `&PORTD`를 저장하고 `*(led->port - 1)`로 DDRD에 접근합니다. 이 코드는 ATmega128A에서 해당 PORT와 DDR 레지스터가 인접한 주소에 배치된 점을 이용합니다. 다른 MCU나 다른 레지스터 배치에 그대로 일반화할 수 없습니다.
