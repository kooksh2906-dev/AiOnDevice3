# Register & Hardware Settings

## MCU와 Peripheral

- MCU: ATmega128A
- Peripheral: GPIO
- 사용 포트: PORTD
- 데이터 폭: 8-bit
- 외부 하드웨어: 8-bit LED Array Bar

## 주요 레지스터

| 레지스터 | 데이터 공간 주소 | I/O 주소 | 설정·사용 | 의미 |
|---|---:|---:|---|---|
| PORTD | `$32` | `$12` | 8비트 패턴 기록 | 각 GPIO 핀의 High/Low 출력 결정 |
| DDRD | `$31` | `$11` | `0xFF` 또는 비트별 1 설정 | 해당 PD 핀을 출력으로 설정 |
| PIND | `$30` | `$10` | 입력값 판독 | 이 출력 실습에서는 직접 사용하지 않음 |

## 비트와 LED의 대응

- `PORTD[7:0]`의 각 비트가 LED Array Bar의 8개 입력에 대응합니다.
- `1U << i`는 선택한 비트 하나를 High로 설정하는 패턴을 만듭니다.
- OR 연산은 여러 LED 비트를 하나의 출력 패턴으로 결합합니다.
- 실제 LED의 물리적 좌우 순서는 PD0~PD7의 배선 순서에 따라 달라질 수 있습니다.
- 점등 논리는 Active-High/Active-Low 결선에 따라 반전될 수 있습니다.

## Port D 겸용 기능

| 핀 | 겸용 기능 |
|---|---|
| PD7 / PD6 | T2 / T1 Timer Counter Clock Input |
| PD5 | XCK1 USART1 External Clock |
| PD4 | ICP1 Timer1 Input Capture |
| PD3 / PD2 | INT3-TXD1 / INT2-RXD1 |
| PD1 / PD0 | INT1-SDA / INT0-SCL |

본 실습은 위 주변기능을 활성화하지 않고 PD0~PD7을 일반 GPIO 출력으로 사용하는 환경을 전제로 합니다.

## Timing

- 출력 패턴 사이의 시간 간격은 `_delay_ms()`로 만듭니다.
- `_delay_ms()`는 Blocking Delay이므로 대기 중에는 다음 제어 코드를 수행하지 않습니다.
- 정확한 지연 계산을 위해 빌드 환경에 올바른 `F_CPU` 설정이 필요합니다.

## VER4 주소 접근

원본 학습 버전은 `led.port`에 `&PORTD`를 저장하고 `*(led->port - 1)`로 DDRD에 접근합니다. ATmega128A의 데이터 공간에서 PORTD `$32`와 DDRD `$31`이 인접하므로 이 장치에서는 성립하지만, 다른 MCU나 레지스터 배치에 그대로 일반화할 수 없습니다.

## VER4 개선안

개선 버전은 구조체에 `ddr`과 `port` 주소를 각각 저장합니다. 포인터를 통한 메모리 맵 레지스터 접근 방식은 유지하면서도, 코드가 어떤 레지스터를 제어하는지 명시적으로 드러냅니다.

