# TIM11 Base Timer Interrupt 설정

## 1. 실습 목적

TIM11의 Internal Clock을 분주하여 1초마다 Update Interrupt를 발생시키고, Callback에서 Nucleo-F411RE의 LD2를 토글합니다. LED와 Oscilloscope는 계산한 주기를 확인하기 위한 관찰 수단입니다.

## 2. System Clock

| 항목 | 설정 |
|---|---:|
| HSE | Bypass Clock Source |
| PLLM / PLLN / PLLP | 4 / 100 / 2 |
| SYSCLK | 100 MHz |
| AHB Prescaler | 1 |
| APB1 Prescaler | 2 |
| APB2 Prescaler | 1 |
| PCLK2 | 100 MHz |
| TIM11 Clock | 100 MHz |

TIM11은 APB2 Timer입니다. 이번 설정은 APB2 Prescaler가 1이므로 TIM11 Clock은 PCLK2와 같은 100 MHz입니다.

## 3. CubeMX TIM11 Parameter

| 항목 | 설정 |
|---|---:|
| Peripheral | TIM11 |
| Activated | Enabled |
| Channel 1 | Disable |
| Clock Source | Internal Clock |
| Prescaler | `10000 - 1` |
| Counter Mode | Up |
| Counter Period | `10000 - 1` |
| Internal Clock Division | No Division |
| Auto-reload Preload | Disable |

### 주기 계산

```text
TIM11CLK = 100 MHz
CK_CNT   = 100 MHz / (9999 + 1) = 10 kHz
Update   = 10 kHz / (9999 + 1) = 1 Hz
Period   = 1 s
```

## 4. NVIC

| 항목 | 설정 |
|---|---|
| TIM1 trigger and commutation interrupts and TIM11 global interrupt | Enabled |
| Preemption Priority | 0 |
| Sub Priority | 0 |

STM32F411에서 TIM11은 `TIM1_TRG_COM_TIM11_IRQn`을 공유합니다. CubeMX가 생성하는 IRQ Handler와 MSP 초기화가 NVIC를 연결하고, `HAL_TIM_Base_Start_IT()`가 TIM11의 Update Interrupt Enable과 Counter Start를 수행합니다.

## 5. GPIO 확인 출력

| 항목 | 설정 |
|---|---|
| 출력 | Nucleo LD2 |
| GPIO | PA5 |
| 동작 | Period Elapsed Callback에서 Toggle |

## 6. CubeMX 생성 코드와 사용자 코드의 경계

- 생성 영역: `MX_TIM11_Init()`, `htim11.Init.Prescaler`, `htim11.Init.Period`, NVIC/MSP 및 IRQ Handler
- `USER CODE 2`: `HAL_TIM_Base_Start_IT(&htim11)`
- `USER CODE 4`: `HAL_TIM_PeriodElapsedCallback()`

## 7. 주요 Register 확인

| Register | 확인 항목 |
|---|---|
| `RCC_APB2ENR` | `TIM11EN`으로 Peripheral Clock 활성화 |
| `TIM11_PSC` | 9999, Counter Clock을 10 kHz로 분주 |
| `TIM11_ARR` | 9999, 10,000 Count마다 Update Event |
| `TIM11_CNT` | 0부터 ARR까지 증가하는 현재 Count |
| `TIM11_DIER` | `UIE`로 Update Interrupt 허용 |
| `TIM11_SR` | `UIF`로 Update Event 상태 확인 |
| `TIM11_EGR` | `UG`로 Software Update Event 생성 가능 |
| `TIM11_CR1` | `CEN`으로 Counter 시작, `ARPE`로 ARR Preload 선택 |

`PSC`에 기록한 값은 Update Event에서 Active Prescaler로 반영됩니다. Auto-reload Preload를 Disable하면 ARR의 Preload Buffer를 사용하지 않지만, 실행 중 값을 변경할 때는 Update 시점과 Counter 상태를 함께 확인해야 합니다.

## 8. 확인 순서

1. Clock Configuration에서 PCLK2와 TIM11 Clock을 확인합니다.
2. PSC와 ARR에 실제 분주값보다 1 작은 값이 입력되었는지 확인합니다.
3. NVIC의 TIM11 공용 IRQ가 Enabled인지 확인합니다.
4. `MX_TIM11_Init()` 호출 이후 `HAL_TIM_Base_Start_IT()`가 실행되는지 확인합니다.
5. Callback에서 `htim->Instance == TIM11` 조건을 확인합니다.
6. LD2 Toggle 또는 Oscilloscope로 1초 Update 주기를 확인합니다.

실물 보드와 Oscilloscope 재검증은 이번 백업 과정에서 수행하지 않았습니다.

