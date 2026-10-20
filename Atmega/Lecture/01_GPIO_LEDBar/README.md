# GPIO - 8-bit LED Array Bar

PORTD에 연결된 8비트 LED Array Bar를 제어하며 GPIO 출력 레지스터, 비트 연산, 배열, 포인터와 구조체, 소스·헤더 파일 분리를 학습한 실습입니다.

## 제어 흐름

1. `DDRD`를 `0xFF`로 설정해 PORTD 전체를 출력 모드로 구성합니다.
2. 출력 패턴을 계산하거나 배열에서 읽습니다.
3. `PORTD`에 8비트 값을 기록합니다.
4. Blocking Delay 후 다음 패턴을 출력합니다.

## 버전 구성

| 버전 | 구분 기준 | 핵심 내용 |
|---|---|---|
| VER1: Direct Register | DDRD·PORTD 직접 접근 | 레지스터에 8비트 값을 직접 기록 |
| VER2: Function & Macro | 매크로·함수·포인터 | GPIO 출력과 대칭 패턴 계산을 함수로 분리 |
| VER3: Array Pattern | 배열 기반 제어 | LED 패턴을 Lookup Table로 관리 |
| VER4: Struct & Module | 구조체·파일 분리 | PORT 주소와 핀 번호를 구조체로 묶고 led.c/.h로 모듈화 |
| VER4 Improved: Explicit DDR | 하드웨어 의존성 명시 | DDR과 PORT 주소를 구조체에 각각 저장 |
| VER5: Additional Patterns | 기능 확장 실습 | 좌·우 비트 이동 및 짝수·홀수 패턴을 함수로 구현 |

## 파일 구조

- `VER1_Direct_Register/main.c`
- `VER2_Function_Macro/main.c`
- `VER3_Array_Pattern/main.c`
- `VER4_Struct_Module/main.c`
- `VER4_Struct_Module/led.c`
- `VER4_Struct_Module/led.h`
- `VER4_Improved_Explicit_DDR/main.c`
- `VER4_Improved_Explicit_DDR/led.c`
- `VER4_Improved_Explicit_DDR/led.h`
- `VER5_Additional_Patterns/main.c`
- `settings/register-hw-settings.md`

## ATmega128A 데이터시트 재검토

- Port D는 PD0~PD7로 구성된 8-bit 양방향 GPIO이므로 `DDRD = 0xFF`와 `PORTD` 8-bit 패턴 출력 방식이 데이터시트와 일치합니다.
- Register Summary에서 PORTD와 DDRD의 데이터 공간 주소는 각각 `$32`, `$31`입니다(I/O 주소 `$12`, `$11`). 따라서 원본 VER4의 `*(led->port - 1)`은 ATmega128A에서는 성립합니다.
- 이 포인터 연산은 장치별 레지스터 배치에 의존하므로 다른 MCU에 일반화할 수 없습니다. 구조체에 `ddr` 주소를 직접 저장하는 `VER4_Improved_Explicit_DDR`를 권장 개선판으로 유지합니다.
- PD0~PD7은 TWI, 외부 인터럽트, USART1, Timer 입력과 겸용됩니다. 해당 주변기능을 활성화하지 않고 Port D 전체를 GPIO로 사용하는 실습 환경을 전제로 합니다.
- `PORTD` 전체 대입은 8개 핀을 모두 갱신하므로 LED Bar가 Port D 전체를 사용하는 구성에 적합합니다.

## 방향 및 점등 논리 주의

- 코드의 Left/Right는 비트가 MSB 또는 LSB 방향으로 이동한다는 의미입니다. LED Bar의 물리적인 좌우 방향은 PD0~PD7의 실제 배선 순서에 따라 반대로 보일 수 있습니다.
- 출력 High에서 LED가 켜지는지 꺼지는지는 MCU가 아니라 외부 Active-High/Active-Low 결선에 따라 결정됩니다.

## 검증 범위

- ATmega128A Datasheet Rev. 8151H-AVR-02/11의 General Digital I/O, Port D, Register Summary를 대조했습니다.
- 이번 재검토에서는 코드 동작 원리와 레지스터 설정을 검증했으며 AVR-GCC 재빌드와 실물 보드 재검증은 수행하지 않았습니다.

