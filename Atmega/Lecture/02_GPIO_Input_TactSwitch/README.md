# GPIO Input - Tact Switch

PORTG의 Tact Switch 입력으로 PORTD의 8-bit LED Array Bar를 제어하며 GPIO 입력, Active-Low 결선, 비트 마스킹, 회전 연산, 디바운싱과 소스/헤더 모듈화를 학습한 실습입니다.

이 정리본은 기존 학습자료의 코드 흐름을 최대한 보존하되, 자료 속 설명 오류는 코드에 옮기지 않고 아래에 별도로 기록했습니다. 개선이 필요한 구현은 원본 계열과 섞지 않고 `VER4_Improved_Button_Module`로 분리했습니다.

## 하드웨어 전제

- MCU: ATmega128A
- LED Array Bar: PORTD(PD0~PD7), Active-High 기준
- Tact Switch: PORTG(PG2~PG4)
- 입력 결선: 외부 10 kOhm Pull-up, 버튼을 누르면 GND와 연결되는 Active-Low 방식
- 버튼 미입력: `PING` 해당 비트가 1
- 버튼 입력: `PING` 해당 비트가 0
- Port G는 5-bit 포트이므로 실제 GPIO는 PG0~PG4만 존재합니다.
- PG2/PG3/PG4는 각각 ALE/TOSC2/TOSC1 겸용 핀입니다. 외부 메모리 인터페이스와 Timer0 비동기 오실레이터 기능을 사용하지 않는 GPIO 실습 환경을 전제로 합니다.

## 버전 구성

| 버전 | 코딩 스타일 | 핵심 학습 내용 |
|---|---|---|
| VER1: Single Button Polling | 레지스터 직접 접근 | PG4 입력을 계속 읽어 LED 전체 ON/OFF |
| VER2: Three Button Rotate | 지역변수 + 비트 회전 | PG2/PG3으로 한 비트 좌/우 회전, PG4로 OFF |
| VER3: Struct Button Module | 구조체 + 소스/헤더 분리 | 버튼별 상태 보관, 눌림/해제 이벤트, 50 ms 지연 기반 디바운싱 |
| VER4: Improved Button Module | 타입 명확화 + 안정 상태 재확인 | 헤더 보호, 외부 Pull-up 설정 명시, 디바운싱 후 재샘플링, 초기 출력 명시 |

## 제어 흐름

### VER1

1. `DDRD = 0xFF`로 LED 포트를 출력으로 설정합니다.
2. `DDRG`의 4번 비트만 0으로 만들어 PG4를 입력으로 설정합니다.
3. `PING & (1 << 4)`로 PG4의 논리값을 읽습니다.
4. Active-Low 결선이므로 결과가 0일 때 버튼이 눌린 상태입니다.

### VER2

1. PG2, PG3, PG4를 입력으로 사용하고 `ledData`를 `0x01`로 시작합니다.
2. PG2 입력 시 `ledData = (ledData >> 7) | (ledData << 1)`로 8-bit Rotate-Left를 수행합니다.
3. PG3 입력 시 `ledData = (ledData >> 1) | (ledData << 7)`로 8-bit Rotate-Right를 수행합니다.
4. PG4 입력 시 LED 출력을 `0x00`으로 지웁니다.
5. 누르고 있는 동안 약 200 ms마다 반복 동작하는 Level Polling 방식입니다.

### VER3/VER4

각 버튼 객체가 레지스터 주소, 핀 번호, 이전 입력 상태를 보관합니다. `ButtonGetState()` 또는 `buttonGetEvent()`는 현재 상태와 이전 상태를 비교하여 눌림/해제 시점에만 이벤트를 반환합니다. 메인 함수는 원본 실습 의도에 맞춰 버튼을 뗄 때 LED ON/OFF/TOGGLE 동작을 실행합니다.

## 원자료 검토 중 바로잡은 설명

- `DDRG &= ~(1 << 4)`는 **DDRG 전체를 0으로 만드는 코드가 아닙니다.** 기존 값 중 4번 비트만 0으로 지우고 나머지 비트는 보존합니다.
- 버튼을 눌렀을 때는 스위치가 "닫힌" 상태이므로 PG 핀이 GND에 연결되어 Low가 입력됩니다.
- 회로 설명 첫 장의 `10 kOhm`이 Pull-up 저항값입니다. 후속 도식의 `10 Ohm` 표기는 오기로 판단하여 정리본에서는 10 kOhm으로 통일했습니다.
- C 조건식은 정수형의 종류와 무관하게 0을 거짓, 0이 아닌 값을 참으로 판단합니다. 이 코드의 입력 저장형은 `uint8_t`입니다.
- `main()`의 지역변수는 반복문마다 자동으로 다시 초기화되는 것이 아니라, 함수 실행 중 값을 유지하다 코드가 값을 바꿀 때 갱신됩니다.
- VER3의 50 ms 지연은 입력을 다시 확인하지 않으므로 완전한 디바운싱이라기보다 간단한 지연 처리입니다. VER4는 지연 후 핀을 다시 읽어 안정된 전이만 이벤트로 확정합니다.
- 데이터시트상 `PORTG`의 초기값은 0이므로 전원 Reset 직후 시작하는 VER1~VER3에서는 내부 Pull-up이 꺼져 있습니다. 다만 재사용 가능한 모듈은 이전 설정에 의존하지 않아야 하므로 VER4는 해당 `PORTG` 비트를 명시적으로 0으로 지웁니다.
- `PING` 판독에는 MCU 내부 동기화 지연이 있지만 기계식 버튼의 50~200 ms 시간 규모와 비교하면 실습 동작에 영향을 줄 수준은 아닙니다.

## 파일 구조

- `VER1_Single_Button_Polling/main.c`
- `VER2_Three_Button_Rotate/main.c`
- `VER3_Struct_Button_Module/main.c`
- `VER3_Struct_Button_Module/button.c`
- `VER3_Struct_Button_Module/button.h`
- `VER4_Improved_Button_Module/main.c`
- `VER4_Improved_Button_Module/button.c`
- `VER4_Improved_Button_Module/button.h`
- `settings/register-hw-settings.md`
- `LEARNING_ANALYSIS.md`

## 검증 범위

- 학습자료의 코드와 설명을 대조해 전사했습니다.
- ATmega128A 데이터시트의 `DDRx`, `PORTx`, `PINx` 동작과 Port G 레지스터 구성을 대조했습니다.
- 로컬 AVR-GCC 도구가 없어 실제 AVR 빌드와 보드 동작 검증은 아직 수행하지 않았습니다.

