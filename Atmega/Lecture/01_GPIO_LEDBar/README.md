# GPIO - 8-bit LED Array Bar

PORTD에 연결된 8비트 LED Array Bar를 제어하며 GPIO 출력 레지스터, 비트 연산, 배열, 포인터와 구조체, 소스·헤더 파일 분리를 학습한 실습입니다.

## 제어 흐름

1. `DDRD`를 `0xFF`로 설정해 PORTD 전체를 출력 모드로 구성합니다.
2. 출력 패턴을 계산하거나 배열에서 읽습니다.
3. `PORTD`에 8비트 값을 기록합니다.
4. 지연 후 다음 패턴을 출력합니다.

## 버전 구성

| 버전 | 구분 기준 | 핵심 내용 |
|---|---|---|
| VER1: Direct Register | DDRD·PORTD 직접 접근 | 레지스터에 8비트 값을 직접 기록 |
| VER2: Function & Macro | 매크로·함수·포인터 | GPIO 출력과 패턴 계산을 함수로 분리 |
| VER3: Array Pattern | 배열 기반 제어 | LED 패턴을 Lookup Table로 관리 |
| VER4: Struct & Module | 구조체·파일 분리 | 포트·핀 정보를 구조체로 묶고 led.c/.h로 모듈화 |

## 파일 구조

- `VER1_Direct_Register/main.c`
- `VER2_Function_Macro/main.c`
- `VER3_Array_Pattern/main.c`
- `VER4_Struct_Module/main.c`
- `VER4_Struct_Module/led.c`
- `VER4_Struct_Module/led.h`
- `settings/register-hw-settings.md`
