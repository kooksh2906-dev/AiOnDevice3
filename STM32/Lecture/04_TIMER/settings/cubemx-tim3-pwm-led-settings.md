# TIM3 PWM LED Duty 제어 설정

## 1. 실습 목적

TIM3 Channel 1에서 100 Hz PWM을 출력하고 Capture/Compare 값을 변화시켜 PA6에 연결된 LED의 평균 밝기 변화를 확인합니다.

## 2. System Clock과 APB1 Timer Clock

| 항목 | 설정 |
|---|---:|
| SYSCLK/HCLK | 100 MHz |
| APB1 Prescaler | 2 |
| PCLK1 | 50 MHz |
| TIMPRE | Reset 기준 |
| TIM3 Clock | 100 MHz |

TIM3은 APB1 Timer입니다. APB1 Prescaler가 2이므로 기본 TIMPRE 조건에서 TIM3 Clock은 PCLK1의 2배인 100 MHz가 됩니다. PCLK1 값만 사용하여 계산하면 PWM 주파수가 절반으로 잘못 계산됩니다.

## 3. CubeMX TIM3 Parameter

| 항목 | 설정 |
|---|---:|
| Clock Source | Internal Clock |
| Channel 1 | PWM Generation CH1 |
| Prescaler | `1000 - 1` |
| Counter Mode | Up |
| Counter Period | `1000 - 1` |
| Internal Clock Division | No Division |
| Auto-reload Preload | Disable |
| PWM Mode | PWM mode 1 |
| Pulse | 500 |
| Output Compare Preload | Enable |
| Fast Mode | Disable |
| CH Polarity | High |

### 주파수와 Duty 계산

```text
TIM3CLK = 100 MHz
CK_CNT  = 100 MHz / (999 + 1) = 100 kHz
f_PWM   = 100 kHz / (999 + 1) = 100 Hz
Duty    = 500 / (999 + 1) × 100 = 50 %
```

## 4. GPIO Alternate Function

| 항목 | 설정 |
|---|---|
| GPIO | PA6 |
| Alternate Function | AF2 TIM3 |
| Timer Channel | TIM3_CH1 |
| Output Type | Push-Pull |
| Pull | No Pull |

PWM Signal은 Timer 내부에서 생성되지만 실제 Pin으로 출력하려면 GPIO가 해당 Timer Channel의 Alternate Function으로 설정되어야 합니다. Channel 1을 시작했더라도 PA6이 AF2 TIM3_CH1으로 연결되지 않으면 Pin에서 PWM을 관찰할 수 없습니다.

## 5. HAL 초기화·시작 흐름

| 단계 | 생성·사용 함수 | 역할 |
|---|---|---|
| Time Base 초기화 | `HAL_TIM_PWM_Init()` | Prescaler, Period, Counter Mode 등을 초기화합니다. |
| Clock Source | `HAL_TIM_ConfigClockSource()` | Internal Clock Source를 구성합니다. |
| PWM Channel | `HAL_TIM_PWM_ConfigChannel()` | PWM Mode, Pulse, Polarity 및 Fast Mode를 구성합니다. |
| GPIO 연결 | `HAL_TIM_MspPostInit()` | PA6을 TIM3_CH1 Alternate Function으로 구성합니다. |
| 출력 시작 | `HAL_TIM_PWM_Start(&htim3, TIM_CHANNEL_1)` | Counter와 Channel 1 PWM 출력을 시작합니다. |
| Duty 변경 | `__HAL_TIM_SET_COMPARE(&htim3, TIM_CHANNEL_1, value)` | 실행 중 CCR1 값을 변경합니다. |

## 6. 주요 Register 확인

| Register | 확인 항목 |
|---|---|
| `RCC_APB1ENR` | `TIM3EN`으로 Peripheral Clock 활성화 |
| `TIM3_PSC` | 999, Counter Clock을 100 kHz로 분주 |
| `TIM3_ARR` | 999, PWM Period를 1,000 Count로 설정 |
| `TIM3_CNT` | 현재 PWM 주기 내 Count |
| `TIM3_CCMR1` | `OC1M=PWM mode 1`, `OC1PE=1` |
| `TIM3_CCER` | `CC1E` Output Enable, `CC1P=0` Active High |
| `TIM3_CCR1` | Channel 1 Compare 값과 Duty Ratio 결정 |
| `TIM3_CR1` | `CEN`, Counter Mode 및 ARR Preload 제어 |
| `TIM3_EGR` | `UG`로 Preload 값을 Active Register에 반영 가능 |

## 7. 수업 화면의 Channel 불일치

수업 CubeMX 화면과 Start 함수는 TIM3 Channel 1을 사용하지만, 반복문 화면에는 다음과 같이 `CCR3`를 변경한 코드가 남아 있습니다.

```c
HAL_TIM_PWM_Start(&htim3, TIM_CHANNEL_1);
TIM3->CCR3 = i;
```

PWM 출력 Channel 1의 Duty를 바꾸려면 `CCR1`을 변경해야 합니다. 이 기록은 복원본에 그대로 보존하고, 정정본에서는 Channel 인자와 CCR 선택을 일치시키는 HAL Macro를 사용합니다.

```c
__HAL_TIM_SET_COMPARE(&htim3, TIM_CHANNEL_1, compare);
```

## 8. 확인 순서

1. RCC에서 PCLK1과 실제 TIM3 Clock의 2배 규칙을 확인합니다.
2. PSC, ARR 및 Pulse로 100 Hz·50%가 계산되는지 확인합니다.
3. CubeMX Channel과 GPIO Alternate Function이 모두 TIM3_CH1인지 확인합니다.
4. `MX_TIM3_Init()` 이후 `HAL_TIM_PWM_Start()`가 호출되는지 확인합니다.
5. Runtime에 변경하는 CCR 번호가 시작한 Channel과 일치하는지 확인합니다.
6. Logic Analyzer/Oscilloscope로 Frequency와 Duty를 확인한 뒤 LED 밝기와 비교합니다.

실물 보드와 계측기 재검증은 이번 백업 과정에서 수행하지 않았습니다.

