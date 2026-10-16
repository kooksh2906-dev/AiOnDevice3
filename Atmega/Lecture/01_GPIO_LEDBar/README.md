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

## 방향 표기 주의

코드의 Left/Right는 비트가 MSB 또는 LSB 방향으로 이동한다는 의미입니다. LED Bar의 물리적인 좌우 방향은 PD0~PD7의 실제 배선 순서에 따라 반대로 보일 수 있습니다.
