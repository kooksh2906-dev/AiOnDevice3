# 08. Passive Piezo Buzzer

STM32F411RE의 `PB6/TIM4_CH1` PWM 출력으로 수동 피에조 부저의 음높이와 재생 시간을 제어한 학습 기록입니다. TIM4의 Prescaler를 바꾸어 PWM 주파수를 음계에 대응시키고, Compare 값을 0 또는 약 50% Duty로 변경하여 무음과 발음을 제어했습니다.

수업에서는 강사님이 제공한 도·미·솔 출력 함수로 기본 동작을 확인한 뒤, 음계·박자 매크로와 공통 재생 함수를 사용하여 LG 세탁기 종료음 형태의 멜로디로 확장했습니다. 메일 기록에는 주파수와 PWM 계산 및 멜로디 확장 과정에서 AI의 도움을 받았다는 설명이 함께 남아 있습니다.

## 1. 실제 실습 구성

| 구분 | 설정·연결 | 역할 |
|---|---|---|
| Board | NUCLEO-F411RE | TIM4 PWM 생성 |
| PWM 출력 | PB6 / AF2 / TIM4_CH1 | 수동 부저 구동 신호 |
| 부저 연결 | PB6 → Buzzer `+`, Buzzer `-` → GND | PWM 전압으로 압전 소자 진동 |
| Timer Mode | Internal Clock, PWM Generation CH1 | 주기적인 Square Wave 출력 |
| Counter | Up-counting | `0`부터 `ARR`까지 반복 계수 |
| USART2 | PA2/PA3 | 원본 Pinout에 설정되어 있으나 부저 코드에서는 사용하지 않음 |

부저 모듈의 정격 전압과 구동 전류는 실물 사양을 확인해야 합니다. GPIO 허용 전류보다 큰 구동 전류가 필요한 부저를 사용할 때에는 Transistor Driver와 보호 회로를 추가해야 합니다.

## 2. 수동 부저와 능동 부저

능동 부저는 내부 발진 회로가 있어 정격 전압을 인가하면 고정된 음을 냅니다. 반면 수동 피에조 부저는 외부에서 주기 신호를 공급해야 하며, PWM 주파수에 따라 음높이가 달라집니다.

이번 실습에서 `TIM4_CH1`은 음을 만드는 주기 신호를 출력합니다. Duty는 약 50%로 유지하고 PSC를 변경하여 주파수를 바꾸므로, 각 음계는 Timer 분주 설정으로 표현됩니다.

## 3. TIM4 PWM 설정과 계산

원본 CubeMX 화면에서 확인한 설정은 다음과 같습니다.

```text
TIM4 Clock Source : Internal Clock
Channel 1        : PWM Generation CH1
Prescaler        : 1999
Counter Period   : 999
Pulse            : 499
PWM Mode         : PWM mode 1
Polarity         : High
```

PWM 주파수는 다음 식으로 계산합니다.

```text
f_CNT = TIM4CLK / (PSC + 1)
f_PWM = TIM4CLK / ((PSC + 1) × (ARR + 1))
Duty  = CCR1 / (ARR + 1) × 100
```

원본 음계 값은 `TIM4CLK=100 MHz`, `ARR=999`일 때의 계산과 일치합니다. 예를 들어 `NOTE_A4=226`이면 다음과 같습니다.

```text
f_PWM = 100,000,000 / ((226 + 1) × (999 + 1))
      ≈ 440.53 Hz
```

`CCR1=500`, `ARR=999`이면 High 구간은 500 Count이므로 Duty는 약 50%입니다. 원본 CubeMX 초기 Pulse는 499로 표시되어 있지만 실행 코드에서는 `CCR1=500`을 사용합니다.

STM32F411RE에서 APB Prescaler가 1이 아니면 해당 APB Timer Clock은 일반적으로 `2 × PCLK`가 됩니다. 이번 Clock 설정은 APB1=50 MHz, TIM4CLK=100 MHz에 해당합니다.

## 4. 실제 프로그램 흐름

### 4.1 PWM 시작

CubeMX가 생성한 `MX_TIM4_Init()` 이후 PWM 출력을 시작합니다.

```c
HAL_TIM_PWM_Start(&htim4, TIM_CHANNEL_1);
```

### 4.2 음계 변경

원본은 `ARR=999`를 유지하고 Prescaler를 변경합니다.

```c
TIM4->PSC = psc;
HAL_Delay(duration_ms);
```

`TIM4_PSC`는 Preload Register이므로 새 값은 Update Event에서 실제 Prescaler Buffer로 반영됩니다. 원본은 다음 Counter Update에 맡기고, 개선본은 `TIM_EGR.UG`에 해당하는 Update Event를 명시적으로 발생시킵니다.

### 4.3 음 분리와 정지

```c
TIM4->CCR1 = 0U;
HAL_Delay(20U);
TIM4->CCR1 = 500U;
```

`CCR1=0`이면 PWM Mode 1에서 High 구간이 없어 부저가 정지합니다. 음 사이 20 ms 무음 구간을 두어 연속된 음을 분리합니다.

## 5. 버전 구성

| 버전 | 성격 | 내용 |
|---|---|---|
| `VER1_Reconstructed_Original_TIM4_PWM` | 실제 수업 화면 복원본 | 강사님 도·미·솔 함수, PSC 음계 매크로, `Buzzer_Play()`와 세탁기 종료음 재생 흐름을 보존했습니다. |
| `VER2_Improved_Frequency_Table_Module` | 별도 개선본 | 음계를 Hz로 표현하고 Timer Clock·ARR로 PSC를 계산하며, Note 구조체 배열과 공통 재생 API로 멜로디를 관리합니다. |

두 버전 모두 STM32CubeMX/CubeIDE 생성 형식의 전체 `main.c`를 사용합니다. 사용자 Header는 `USER CODE Includes`, 초기 PWM 시작과 Module 초기화는 `USER CODE 2`, Main Loop의 재생 호출은 `USER CODE 3`에 배치했습니다.

## 6. 원본 코드에서 확인할 점

### 6.1 `Buzzer_Sol()`의 PSC 값

원본 화면에서는 `Buzzer_Mi()`와 `Buzzer_Sol()`이 모두 `PSC=304`를 사용합니다. 동일한 Timer Clock과 ARR에서 같은 PSC는 같은 주파수를 만들기 때문에 두 함수가 서로 다른 미·솔 음을 출력할 수 없습니다.

학습 흔적을 보존하기 위해 VER1에는 화면의 값을 그대로 남겼습니다. VER2에서는 미를 659 Hz, 솔을 784 Hz로 구분하고 PSC를 계산합니다.

### 6.2 Clock 설정에 종속된 음계 상수

`NOTE_A4=226`과 같은 값은 음계 주파수가 아니라 특정 `TIM4CLK`와 `ARR`에서만 유효한 PSC 값입니다. Clock Tree나 ARR가 달라지면 음정도 함께 바뀝니다. 개선본은 음계를 Hz로 표현하여 설정 의도를 코드에서 바로 확인할 수 있게 했습니다.

### 6.3 Prescaler 갱신 시점

PSC에 쓴 값은 즉시 분주 회로에 적용되지 않고 Update Event에서 Buffer로 전달됩니다. 원본처럼 직접 `TIM4->PSC`에 값을 쓰면 음 전환 시점이 Counter Update에 의존합니다. 개선본은 출력 Compare를 먼저 0으로 만들고 PSC·CNT를 설정한 뒤 Update Event를 발생시켜 전환 순서를 명확히 했습니다.

### 6.4 Blocking 재생

원본과 개선본 모두 한 음의 길이를 `HAL_Delay()`로 유지합니다. 멜로디를 재생하는 동안 Main Context의 다른 처리는 지연됩니다. 이번 정리는 실제 수업의 Blocking 구조를 유지하며, 별도의 Non-blocking Sequencer를 실제 학습 결과처럼 추가하지 않습니다.

### 6.5 반복 재생

원본 `main.c`는 `while (1)`에서 멜로디 함수를 계속 호출하므로 종료음이 반복됩니다. 개선본은 `melodyPlayed` 로컬 상태로 최초 한 번만 재생하여 실행 의도를 구분했습니다.

## 7. CubeMX·HAL·Register 연결

| CubeMX/HAL | 주요 Register | 의미 |
|---|---|---|
| TIM4 Internal Clock | `TIM4_SMCR.SMS=000` | 내부 Clock 기반 Counter |
| Prescaler | `TIM4_PSC` | Counter 입력 Clock 분주 |
| Counter Period | `TIM4_ARR` | PWM 한 주기의 Count 수 결정 |
| PWM Mode 1 | `TIM4_CCMR1.OC1M` | `CNT < CCR1` 동안 Active 출력 |
| Output Compare Preload | `TIM4_CCMR1.OC1PE` | CCR1 변경값의 Update 시점 관리 |
| Channel Enable | `TIM4_CCER.CC1E` | CH1 출력 활성화 |
| Polarity High | `TIM4_CCER.CC1P=0` | Active High 출력 |
| PB6 AF2 | `GPIOB_MODER`, `GPIOB_AFRL` | PB6을 TIM4_CH1에 연결 |
| `HAL_TIM_PWM_Start()` | `TIM4_CCER`, `TIM4_CR1` | PWM Channel과 Counter 시작 |
| `TIM4->CCR1` | `TIM4_CCR1` | Duty와 무음 상태 제어 |
| Update Event | `TIM4_EGR.UG` | PSC Preload 값을 Buffer에 반영 |

## 8. 핵심 학습 포인트

- 수동 피에조 부저는 GPIO On/Off가 아니라 일정한 주파수의 PWM 신호로 음을 생성합니다.
- Timer 입력 Clock, PSC와 ARR의 관계를 계산하여 원하는 음계의 주파수를 만들었습니다.
- ARR를 고정하고 PSC를 바꾸면 PWM 주파수가 변하며, CCR을 바꾸면 Duty와 출력 여부가 달라집니다.
- 음계별 반복 코드를 공통 함수로 묶고 음계·박자를 매크로 또는 구조체 배열로 표현했습니다.
- PSC가 Preload Register라는 점 때문에 Register Write와 실제 분주값 반영 시점을 구분해야 합니다.
- Blocking 멜로디 재생은 이해하기 쉽지만 다른 입력·출력 처리와 함께 사용할 때에는 Scheduling 구조를 별도로 고려해야 합니다.
- 강사님 제공 코드와 AI 도움을 받아 확장한 코드를 구분하여 실제 학습 과정과 코드 출처를 함께 보존했습니다.

## 9. 검증 범위

- 메일에 보관된 TIM4 Mode·Parameter·Pinout·배선, `buzzer.h/.c`와 `main.c` 화면을 서로 대조했습니다.
- STM32F411RE RM0383을 기준으로 APB Timer Clock, PSC·ARR·CCR1, PWM Mode 1과 Update Event 동작을 정적 검토했습니다.
- GitHub에는 코드와 설정 문서만 저장하고, 실제 CubeMX·IDE 화면은 Notion에 배치합니다.
- 두 버전의 C Source는 HAL Stub을 이용하여 문법·경고 검사를 수행합니다.
- 원본 `.ioc`, 생성된 `tim.c/.h`, `gpio.c/.h`, `usart.c/.h`와 전체 CubeIDE Project는 현재 보관본에 포함되지 않았습니다.
- 이번 정리 과정에서 CubeIDE 전체 재빌드와 실물 Board 재시험은 수행하지 않았습니다.

## 참고 문서

- STMicroelectronics, *RM0383: STM32F411xC/E Reference Manual*, Rev 3
- STMicroelectronics, *UM1725: Description of STM32F4 HAL and Low-layer Drivers*, Rev 8
- 메일 보관 자료, *[STM32 학습 기록] FW: LAB_BUZZER*
