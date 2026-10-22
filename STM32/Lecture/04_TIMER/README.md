# 04. Timer

STM32F411RE의 TIM11 Update Interrupt와 TIM3 PWM을 사용하여 주기 생성, Interrupt Callback 및 Duty Ratio 제어를 학습한 기록입니다. 수업 화면에 남은 CubeMX 설정과 코드를 기준으로 전체 CubeIDE 형식 `main.c`를 복원하고, RM0383과 UM1725를 통해 Clock 경로, 주요 Register 및 HAL API의 관계를 함께 정리했습니다.

## 1. 실제 학습 범위

- TIM11의 Internal Clock, Prescaler, Auto-reload Register를 설정하여 1초 주기의 Update Event를 생성했습니다.
- TIM11 Global Interrupt를 활성화하고 `HAL_TIM_PeriodElapsedCallback()`에서 Nucleo 보드의 LD2를 토글했습니다.
- LED 점멸과 Oscilloscope 측정을 통해 계산한 Timer 주기를 확인하는 흐름을 학습했습니다.
- TIM3 Channel 1을 PWM Mode 1로 설정하고 PWM 출력의 주파수와 Duty Ratio를 계산했습니다.
- Capture/Compare Register 값을 변화시켜 PA6에 연결한 LED의 밝기가 달라지는 현상을 확인했습니다.
- MG996R의 50 Hz 각도 제어는 PWM의 후속 HW 응용이므로 별도 MG996R 항목에서 정리합니다.

## 2. STM32F411 Timer Clock을 먼저 계산해야 하는 이유

Timer의 PSC와 ARR만 보아서는 실제 주기를 알 수 없습니다. 먼저 해당 Timer가 APB1과 APB2 중 어느 Bus에 연결되어 있고, RCC의 APB Prescaler와 `TIMPRE` 설정에 따라 `TIMxCLK`가 얼마인지 확인해야 합니다.

이번 수업의 System Clock 설정은 다음과 같습니다.

| Clock | 설정값 |
|---|---:|
| SYSCLK/HCLK | 100 MHz |
| APB1 Prescaler | 2 |
| PCLK1 | 50 MHz |
| APB2 Prescaler | 1 |
| PCLK2 | 100 MHz |
| TIMPRE | Reset 기준 |

RM0383의 기본 Timer Clock 규칙에서 APB Prescaler가 1이면 Timer Clock은 해당 PCLK와 같고, 1이 아니면 Timer Clock은 PCLK의 2배입니다.

- TIM3은 APB1에 연결됩니다. PCLK1은 50 MHz이지만 APB1 Prescaler가 2이므로 `TIM3CLK = 2 × PCLK1 = 100 MHz`입니다.
- TIM11은 APB2에 연결됩니다. APB2 Prescaler가 1이므로 `TIM11CLK = PCLK2 = 100 MHz`입니다.

따라서 두 실습 모두 계산의 시작값은 100 MHz이지만, 같은 결과에 도달하는 Clock 경로는 서로 다릅니다.

## 3. Time Base 계산

Up-counter에서 Counter Clock과 Update 주기는 다음과 같이 계산합니다.

```text
f_CNT    = f_TIM / (PSC + 1)
f_UPDATE = f_TIM / ((PSC + 1) × (ARR + 1))
T_UPDATE = 1 / f_UPDATE
```

`PSC`와 `ARR`에는 분주비나 Count 횟수보다 1 작은 값을 기록하므로 식에 각각 `+1`이 들어갑니다.

### TIM11 1초 Update Interrupt

```text
f_TIM11  = 100,000,000 Hz
PSC      = 9,999
ARR      = 9,999

f_CNT    = 100,000,000 / 10,000 = 10,000 Hz
f_UPDATE = 10,000 / 10,000 = 1 Hz
T_UPDATE = 1 s
```

TIM11의 Counter는 0부터 ARR까지 증가한 뒤 0으로 돌아가며 Update Event를 만듭니다. Update Interrupt가 허용되어 있으면 `UIF` Flag와 IRQ 처리 흐름을 거쳐 HAL의 Period Elapsed Callback이 호출됩니다.

## 4. PWM 계산

Edge-aligned Up-counting PWM Mode 1에서 기본 주파수와 Duty Ratio는 다음과 같이 계산합니다.

```text
f_PWM = f_TIM / ((PSC + 1) × (ARR + 1))
Duty  = CCRx / (ARR + 1) × 100 [%]
```

### TIM3 LED PWM

```text
f_TIM3 = 100,000,000 Hz
PSC    = 999
ARR    = 999
CCR1   = 500

f_CNT  = 100,000 Hz
f_PWM  = 100 Hz
Duty   = 50 %
```

PWM Mode 1의 Up-counting에서는 일반적으로 `CNT < CCRx`인 동안 Channel Reference가 Active가 됩니다. 따라서 CCR이 커질수록 한 주기에서 High 구간이 길어지고 LED의 평균 밝기가 증가합니다.

## 5. 버전 구성

| 버전 | 성격 | 내용 |
|---|---|---|
| `01_TIM11_Base_Timer_Interrupt/VER1_Reconstructed_Lecture_LED_Toggle` | 수업 화면 기반 복원본 | 1 Hz Update Interrupt를 시작하고 TIM11 Callback에서 LD2를 토글합니다. |
| `02_TIM3_PWM_LED_Duty_Control/VER1_Reconstructed_Lecture_CCR3_Mismatch` | 수업 화면 기반 복원본 | TIM3 Channel 1을 시작하지만 반복문에서 `TIM3->CCR3`를 변경한 화면의 불일치를 그대로 보존합니다. |
| `02_TIM3_PWM_LED_Duty_Control/VER2_Corrected_TIM3_CH1_Duty_Control` | 별도 정정본 | 시작 Channel과 Compare Register를 Channel 1로 일치시키고 `__HAL_TIM_SET_COMPARE()`로 Duty를 변경합니다. |

수업 화면에서 TIM3 PWM Channel 1과 PA6 출력이 설정되어 있으므로 Runtime Compare 값도 CCR1에 기록해야 합니다. 복원본을 지우지 않고 정정본을 분리하여 실제 학습 흔적과 수정 근거를 함께 보존했습니다.

## 6. CubeMX·HAL·Register 연결

| CubeMX/HAL | 주요 Register·Bit | 의미 |
|---|---|---|
| TIM11 Activated | `RCC_APB2ENR.TIM11EN` | TIM11 Peripheral Clock을 공급합니다. |
| TIM3 Internal Clock | `RCC_APB1ENR.TIM3EN`, 내부 `CK_INT` | TIM3 Peripheral Clock과 내부 Clock Source를 사용합니다. |
| Prescaler | `TIMx_PSC` | `TIMxCLK`를 `PSC+1`로 나눠 Counter Clock을 만듭니다. |
| Counter Period | `TIMx_ARR` | Up-counter의 Top 값을 정하고 Overflow/Update 주기를 결정합니다. |
| `HAL_TIM_Base_Start_IT()` | `TIMx_DIER.UIE`, `TIMx_CR1.CEN` | Update Interrupt를 허용하고 Counter를 시작합니다. |
| Period Elapsed Callback | `TIMx_SR.UIF` 처리 이후 호출 | Update Event가 발생했음을 Application에 전달합니다. |
| PWM Mode 1 | `TIMx_CCMR1.OC1M` | Channel 1의 Output Compare 동작을 PWM Mode 1로 설정합니다. |
| Output Compare Preload | `TIMx_CCMR1.OC1PE` | CCR1의 새 값을 Update Event에 맞춰 반영하도록 Buffering합니다. |
| PWM Pulse | `TIMx_CCR1` | Counter와 비교되는 값으로 Duty Ratio를 결정합니다. |
| Polarity High | `TIMx_CCER.CC1P=0` | Channel 1의 Active Polarity를 High로 설정합니다. |
| `HAL_TIM_PWM_Start()` | `CC1E`, `CEN` 등 | 선택한 PWM Channel Output과 Counter를 활성화합니다. |
| `__HAL_TIM_SET_COMPARE()` | `TIMx_CCR1` | Channel에 맞는 Capture/Compare 값을 Runtime에 변경합니다. |

`PSC`는 Buffer Register이므로 새 값은 Update Event에서 Active Prescaler로 전달됩니다. `ARR`와 `CCRx`의 Preload 사용 여부도 값이 즉시 반영되는지 다음 Update Event에서 반영되는지를 결정합니다. 정적 초기 설정에서는 CubeMX와 HAL 초기화 흐름이 필요한 Update Generation을 처리하지만, 실행 중 주기나 Duty를 변경할 때는 Preload와 Update 시점을 함께 고려해야 합니다.

## 7. HAL 실행 흐름

### TIM11 Update Interrupt

1. CubeMX 생성 코드가 `MX_TIM11_Init()`에서 Prescaler와 Period를 설정합니다.
2. MSP 초기화가 TIM11 Clock과 `TIM1_TRG_COM_TIM11_IRQn`을 준비합니다.
3. `HAL_TIM_Base_Start_IT(&htim11)`가 Update Interrupt와 Counter를 활성화합니다.
4. Overflow 시 `UIF`가 설정되고 공용 IRQ Handler에서 HAL IRQ Handler로 전달됩니다.
5. HAL이 Flag를 처리한 뒤 `HAL_TIM_PeriodElapsedCallback()`을 호출합니다.
6. Callback은 `htim->Instance == TIM11`인지 확인하고 LD2를 토글합니다.

### TIM3 PWM

1. CubeMX 생성 코드가 `MX_TIM3_Init()`에서 Time Base와 PWM Channel 1을 설정합니다.
2. `HAL_TIM_PWM_ConfigChannel()`에 대응하는 초기화 코드가 Mode, Pulse, Polarity와 Preload를 구성합니다.
3. `HAL_TIM_MspPostInit()`이 PA6을 TIM3_CH1 Alternate Function으로 연결합니다.
4. `HAL_TIM_PWM_Start(&htim3, TIM_CHANNEL_1)`이 Channel Output을 시작합니다.
5. Main Loop에서 CCR1을 변경하면 다음 PWM 주기의 Duty Ratio가 달라집니다.

## 8. 코드 배치 원칙

- `tim.h`는 CubeMX 생성 Header이므로 일반 Include 영역에 유지합니다.
- `MX_TIM11_Init()`, `MX_TIM3_Init()`은 CubeMX 생성 호출이므로 USER CODE 영역 밖에 유지합니다.
- `HAL_TIM_Base_Start_IT()`, `HAL_TIM_PWM_Start()`는 주변장치 시작 호출이므로 `USER CODE BEGIN 2`에 배치합니다.
- Duty 변경 반복문은 Main Loop 로직이므로 `USER CODE BEGIN 3`에 배치합니다.
- `HAL_TIM_PeriodElapsedCallback()`은 사용자 Callback 재정의이므로 `USER CODE BEGIN 4`에 배치합니다.

## 9. 핵심 학습 포인트

- Timer 설정은 PSC와 ARR을 입력하기 전에 RCC Clock Tree와 APB Prescaler부터 확인해야 합니다.
- APB Prescaler가 1보다 크면 기본 TIMPRE 조건에서 Timer Clock이 PCLK의 2배가 될 수 있습니다.
- Up-counter는 0부터 ARR까지 포함하여 세므로 주기 계산에 `ARR+1`을 사용합니다.
- Update Event는 Counter Overflow뿐 아니라 Prescaler와 Preload 값을 Active Register에 반영하는 기준점이기도 합니다.
- Interrupt Callback에서는 전달된 Handle의 Instance를 확인하여 Timer를 구분합니다.
- PWM 주파수는 PSC·ARR이, Duty Ratio는 같은 Channel의 CCRx가 결정합니다.
- CubeMX Channel 설정, GPIO Alternate Function, HAL Channel 인자 및 CCR 번호가 모두 일치해야 합니다.
- HAL API를 사용하더라도 실제 동작을 PSC, ARR, CNT, DIER, SR, CCMR, CCER 및 CCR Register와 연결하여 설명할 수 있어야 합니다.

## 10. 검증 범위

- 수업 PDF의 CubeMX 설정, 계산 메모 및 코드 화면을 대조했습니다.
- STM32F411 Reference Manual RM0383 Rev 3과 STM32F4 HAL/LL User Manual UM1725 Rev 8을 기준으로 Clock, Register 및 HAL 동작을 정적 검토했습니다.
- GitHub에는 코드와 설정 문서만 보존하며 원본 수업 화면은 Notion에 배치합니다.
- 전체 CubeIDE 형식 `main.c`의 USER CODE 배치와 C 문법을 HAL Stub으로 확인합니다.
- 원본 `.ioc`, 생성된 `tim.c/.h`, Interrupt Handler 및 전체 CubeIDE Project는 현재 보관본에 포함되지 않았습니다.
- 이번 정리 과정에서는 CubeIDE 재빌드, Oscilloscope 재측정 및 실물 보드 재시험을 수행하지 않았습니다.

## 참고 문서

- STMicroelectronics, *RM0383: STM32F411xC/E Reference Manual*, Rev 3
- STMicroelectronics, *UM1725: Description of STM32F4 HAL and Low-layer Drivers*, Rev 8

