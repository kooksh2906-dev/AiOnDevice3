# Timer/Counter - CTC, Overflow and PWM

ATmega128A의 8-bit Timer/Counter0과 16-bit Timer/Counter1을 레지스터로 직접 설정하여 CTC 출력, Normal Overflow 폴링, Fast PWM 및 비교값 변경을 학습한 실습입니다.

## 하드웨어 및 Clock 전제

- MCU: ATmega128A
- 시스템 Clock: 16 MHz 기준
- Timer0 출력: PB4/OC0
- Timer1 Channel A 출력: PB5/OC1A
- Timer0은 `ASSR.AS0 = 0`인 동기 동작을 전제로 하며 시스템 I/O Clock을 사용합니다.
- OC0와 OC1A 파형을 실제 핀에서 출력하려면 각각 `DDB4`, `DDB5`를 1로 설정해야 합니다.
- 실제 보드 Clock이 16 MHz와 다르면 주파수·주기·Pulse Width 계산 결과도 달라집니다.

## 버전 구성

| 버전 | 코딩 스타일 | 핵심 학습 내용 |
|---|---|---|
| VER1: Timer0 CTC Toggle Polling | 레지스터 직접 접근 + Flag Polling | OCR0 Compare Match마다 OC0 하드웨어 Toggle, OCF0 폴링·해제 |
| VER2: Timer0 Normal Overflow Polling | Counter Preload + SW Toggle | TCNT0=6에서 Overflow까지 250 Count, TOV0 폴링 후 PORTB 반전 |
| VER3: Timer0 Fast PWM Fixed | 고정 비교값 | 8-bit Fast PWM, 비반전 출력, OCR0=64 |
| VER4: Timer0 Fast PWM Sweep | 반복문 기반 비교값 변경 | OCR0를 0~255로 증가시키는 Duty Sweep 원형 보존 |
| VER5: Timer1 Fast PWM Fixed | 16-bit TOP/Compare 설정 | ICR1=4999로 50 Hz, OCR1A=1249로 25% Duty |
| VER6: Timer1 Fast PWM Steps | 순차 비교값 변경 | OCR1A 값에 따른 Pulse Width 단계 변경 |
| VER7: Improved Timer0 PWM Module | 함수·소스/헤더 분리 | 명시적 초기화, 16-bit 반복변수, 상승·하강 Sweep |
| VER8: Improved Timer1 PWM Module | 계산 함수·소스/헤더 분리 | 50 Hz 초기화, 마이크로초 단위 Pulse Width 설정 |

## 제어 흐름

### VER1 - Timer0 CTC Toggle

1. PB4/OC0를 출력으로 설정합니다.
2. `WGM01=1`, `WGM00=0`으로 CTC Mode를 선택합니다.
3. `COM01:0=01`로 Compare Match마다 OC0를 Toggle합니다.
4. `CS02:0=100`으로 64분주를 선택하고 `OCR0=124`를 설정합니다.
5. 하드웨어는 0.5 ms마다 Compare Match를 발생시키고, 두 번의 Toggle로 1 ms 주기의 1 kHz 파형을 만듭니다.
6. 메인 루프는 `OCF0`을 폴링한 뒤 해당 비트에 1을 써서 Flag를 지웁니다. OC0 파형 생성 자체는 하드웨어가 수행합니다.

### VER2 - Timer0 Normal Overflow

1. `CS02:0=101`로 128분주를 선택하고 `TCNT0=6`으로 시작합니다.
2. 6부터 255까지 250 Count 후 Overflow가 발생하며 `TOV0`가 1이 됩니다.
3. 소프트웨어가 PORTB를 반전하고 `TCNT0=6`을 다시 기록한 뒤 `TOV0`에 1을 써서 Flag를 지웁니다.
4. 명목상 Toggle 간격은 2 ms, 출력 주기는 4 ms, 주파수는 250 Hz입니다. 폴링·대입 명령 시간이 추가되므로 실제 파형에는 작은 오차가 생길 수 있습니다.

### VER3/VER4 - Timer0 Fast PWM

- `WGM01:0=11`: TOP이 0xFF인 Fast PWM
- `COM01:0=10`: Compare Match에서 OC0 Clear, BOTTOM에서 Set하는 비반전 출력
- `CS02:0=100`: 64분주
- PWM 주파수: 약 976.56 Hz
- `OCR0=64`: `(64+1)/256`, 약 25.39% Duty
- 원형 VER4의 `uint8_t i < 256`은 `i`가 255 다음 0으로 되돌아가므로 종료되지 않습니다. 지속적인 Sawtooth Sweep처럼 동작하지만 종료 가능한 반복문으로 읽히기 쉬워, VER7에서는 16-bit 반복변수와 상승·하강 함수를 사용합니다.

### VER5/VER6 - Timer1 Fast PWM

- `WGM13:0=1110`: ICR1을 TOP으로 사용하는 Mode 14 Fast PWM
- `COM1A1:0=10`: OC1A 비반전 출력
- `CS12:0=011`: 64분주
- `ICR1=4999`: 5,000 Count × 4 us = 20 ms, 즉 50 Hz
- `OCR1A=1249`: 1,250 Count × 4 us = 5 ms, 즉 25% Duty
- VER6의 630, 254, 120은 각각 약 2.524 ms, 1.020 ms, 0.484 ms의 High Pulse를 만듭니다. 별도 구동 대상이 명시되지 않았으므로 특정 Servo 각도로 단정하지 않고 Pulse Width 변경 실습으로 기록합니다.

## 원형 코드와 개선판의 구분

- VER1~VER6은 강의자료의 직접 레지스터 설정 흐름과 값 사용 방식을 유지합니다.
- 원형의 `TCCRn |= ...`는 Reset 직후 모든 관련 비트가 0이라는 조건에서는 동작하지만, 이전 설정이 남은 재사용 환경에서는 원하지 않는 Mode 비트가 유지될 수 있습니다.
- VER7/VER8은 `TCCRn = ...`로 필요한 비트를 명시하고, Timer1은 Clock 선택 비트를 마지막에 설정하여 구성이 끝난 뒤 Counter를 시작합니다.
- VER7은 원형 VER4의 종료되지 않는 8-bit 반복 조건을 수정하고 상승·하강 Sweep을 함수로 분리합니다.
- VER8은 16 MHz·64분주 조건에서 마이크로초 값을 Timer Count로 변환하고 500~2500 us 범위로 제한합니다.

## 파일 구조

- `VER1_Timer0_CTC_Toggle_Polling/main.c`
- `VER2_Timer0_Normal_Overflow_Polling/main.c`
- `VER3_Timer0_Fast_PWM_Fixed/main.c`
- `VER4_Timer0_Fast_PWM_Sweep/main.c`
- `VER5_Timer1_Fast_PWM_Fixed/main.c`
- `VER6_Timer1_Fast_PWM_Steps/main.c`
- `VER7_Improved_Timer0_PWM_Module/main.c`, `pwm0.c`, `pwm0.h`
- `VER8_Improved_Timer1_PWM_Module/main.c`, `pwm1.c`, `pwm1.h`
- `settings/register-hw-settings.md`
- `settings/timing-calculations.md`
- `LEARNING_ANALYSIS.md`

## 검증 범위

- 학습자료의 회로·표·소스 이미지를 전사하고 ATmega128A Datasheet Rev. 8151H-AVR-02/11의 Timer/Counter0·1 설명과 대조했습니다.
- 16 MHz Clock을 기준으로 CTC, Overflow, Fast PWM 주기와 Duty/Pulse Width를 다시 계산했습니다.
- 호스트 C 문법 검사로 모든 파일을 확인했습니다. VER4 원형의 `uint8_t < 256` 조건에서는 의도대로 항상 참이라는 경고가 발생하며, 개선판에서는 제거했습니다.
- AVR-GCC 빌드, 오실로스코프 측정 및 실물 보드 동작 검증은 수행하지 않았습니다.
