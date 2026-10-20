# FND - 1-digit 7-Segment Display

PORTC에 연결된 1자리 FND(7-Segment Display)에 숫자 패턴을 출력하며 GPIO 출력, Lookup Table, 배열 Index, 반복 카운터, 함수 분리 및 하드웨어 극성 처리를 학습한 실습입니다.

## 하드웨어 및 배선 전제

- MCU: ATmega128A
- FND 연결 Port: PORTC(PC0~PC7)
- Bit-Segment 대응: `PC0=A`, `PC1=B`, `PC2=C`, `PC3=D`, `PC4=E`, `PC5=F`, `PC6=G`, `PC7=DP`
- 원형 코드의 숫자 패턴은 Segment bit가 1일 때 켜지는 Active-High, 즉 Common Cathode 또는 동등한 외부 구동 회로를 전제로 합니다.
- `DDRC=0xFF`로 Port C 전체를 출력으로 사용합니다.
- Port C는 외부 메모리 인터페이스가 활성화되면 A8~A15 Address Bus로 Override될 수 있으므로 본 실습은 `MCUCR.SRE=0`인 일반 GPIO 환경을 전제로 합니다.
- ATmega103 호환 모드에서 Port C는 출력 전용이지만 본 실습은 출력만 사용하므로 핵심 출력 동작과 충돌하지 않습니다. 다만 다른 실습에서 입력으로 재사용할 때는 호환 모드 설정을 확인해야 합니다.

## 원자료 Segment 패턴

| 숫자 | DP G F E D C B A | 16진수 | 비고 |
|---:|---|---:|---|
| 0 | `0011 1111` | `0x3F` | A~F ON |
| 1 | `0000 0110` | `0x06` | B, C ON |
| 2 | `0101 1011` | `0x5B` | A, B, D, E, G ON |
| 3 | `0100 1111` | `0x4F` | A, B, C, D, G ON |
| 4 | `0110 0110` | `0x66` | B, C, F, G ON |
| 5 | `0110 1101` | `0x6D` | A, C, D, F, G ON |
| 6 | `0111 1101` | `0x7D` | A, C, D, E, F, G ON |
| 7 | `0010 0111` | `0x27` | A, B, C에 F를 더한 원자료 글꼴 |
| 8 | `0111 1111` | `0x7F` | A~G ON |
| 9 | `0110 0111` | `0x67` | A, B, C, F, G의 Open-bottom 글꼴 |

`0x27`과 `0x67`은 각각 일반적인 `0x07`, `0x6F`와 다르지만 제공된 표와 원형 코드가 서로 일치합니다. 따라서 오류로 단정하지 않고 원자료의 표시 글꼴로 보존합니다.

## 버전 구성

| 버전 | 코딩 스타일 | 핵심 학습 내용 |
|---|---|---|
| VER1: Original Direct Lookup | 원자료 직접 제어 | 지역 배열과 `count++ % 10`으로 0~9 반복 출력 |
| VER2: Improved Bounded Counter | 타입·범위 개선 | `uint8_t` 카운터를 0~9로 명시적으로 제한, `static const` Lookup Table |
| VER3: Function & Pattern Practice | 함수·매크로 | 초기화·숫자 출력·Clear·증가/감소 Count 함수 분리 |
| VER4: Configurable FND Module | 구조체·소스/헤더 분리 | Port 주소, Common Cathode/Anode, 원본/표준 글꼴, DP 출력을 선택 가능하게 구성 |

## 원형 코드 분석

1. `DDRC=0xFF`로 PC0~PC7 전체를 출력으로 설정합니다.
2. `fndNumber[]`에 숫자 0~9의 Segment 패턴을 저장합니다.
3. `count++ % 10`으로 배열 Index를 0~9 범위로 만들고 `PORTC`에 출력합니다.
4. `_delay_ms(500)`으로 숫자를 0.5초마다 변경합니다.

원형의 `int count`는 AVR-GCC에서 일반적으로 16-bit Signed Integer입니다. 약 0.5초마다 증가하므로 장시간 실행 시 약 4시간 33분 뒤 Signed Overflow 가능성이 있으며, C 언어에서 Signed Overflow는 정의되지 않은 동작입니다. VER1은 학습 원형을 보존하고 VER2 이후에서는 0~9 범위의 `uint8_t` 카운터로 수정합니다.

## 개선 방향

- VER2는 출력 모양을 바꾸지 않고 카운터 범위와 Lookup Table의 변경 가능성만 명확히 합니다.
- VER3는 원자료 글꼴을 유지하면서 `fndCountUp()`과 `fndCountDown()`을 추가합니다.
- VER4는 외부 FND 극성에 따라 출력 Pattern을 반전하고, 원자료 글꼴과 일반적인 표준 글꼴을 선택할 수 있게 합니다.
- `fndDisplayDigitWithPoint()`는 PC7/DP bit를 함께 제어합니다.

## 파일 구조

- `VER1_Original_Direct_Lookup/main.c`
- `VER2_Improved_Bounded_Counter/main.c`
- `VER3_Function_Pattern_Practice/main.c`
- `VER4_Configurable_FND_Module/main.c`
- `VER4_Configurable_FND_Module/fnd.c`
- `VER4_Configurable_FND_Module/fnd.h`
- `settings/register-hw-settings.md`
- `settings/segment-patterns.md`
- `LEARNING_ANALYSIS.md`

## 검증 범위

- 제공된 FND Segment 표와 원형 소스의 10개 Pattern이 모두 일치하는지 확인했습니다.
- ATmega128A Datasheet Rev. 8151H-AVR-02/11의 Port C GPIO, Reset 초기값, ATmega103 호환 모드 및 외부 메모리 Address Bus 겸용 조건을 대조했습니다.
- 5개 C 소스의 호스트 C 문법 검사를 경고 없이 완료했습니다.
- AVR-GCC 빌드와 Common Cathode/Anode 실물 FND 동작 검증은 수행하지 않았습니다.
