# STM32CubeMX 설정 - HC-SR04 Input Capture

## 1. Pinout

| HC-SR04 | STM32F411RE | CubeMX Mode | 설명 |
|---|---|---|---|
| Trigger | PA5 | GPIO_Output | 10 us High Pulse 출력 |
| Echo | PA6 | TIM3_CH1, AF2 | Echo Rising/Falling Edge Input Capture |
| VCC | Module 사양에 맞는 전원 | Power | 공유 Guide의 Module은 3.3~5 V 사양 |
| GND | GND | Ground | Board와 공통 접지 |
| UART TX | PA2 | USART2_TX, AF7 | ST-LINK VCP/Tera Term 출력 |
| UART RX | PA3 | USART2_RX, AF7 | 기본 USART2 설정 유지 |

PA5 Trigger GPIO의 초기 출력은 Low로 설정합니다. Echo 전압은 실제 Module Version과 공급사 문서를 확인한 뒤 STM32 Pin 허용 전압에 맞춰 연결합니다.

## 2. RCC Clock Tree

수업 설정은 SYSCLK/HCLK 100 MHz, APB1 Prescaler 2, APB2 Prescaler 1입니다.

| Peripheral | Bus | PCLK | Timer Clock 규칙 | TIMxCLK |
|---|---|---:|---|---:|
| TIM3 | APB1 | 50 MHz | APB1 Prescaler가 1보다 크므로 기본 TIMPRE 조건에서 `2 x PCLK1` | 100 MHz |
| TIM11 | APB2 | 100 MHz | APB2 Prescaler가 1이므로 `PCLK2` | 100 MHz |

두 Timer 모두 `PSC=99`이므로 Counter Clock은 1 MHz이고 1 Count는 1 us입니다.

## 3. TIM11 - `delay_us()` Time Base

### Mode

- Activated: Enabled
- Channel 1: Disable
- One Pulse Mode: Disabled

### Parameter Settings

| 항목 | 설정 |
|---|---:|
| Prescaler | 99 |
| Counter Mode | Up |
| Counter Period | 65535 |
| Internal Clock Division | No Division |
| Auto-reload Preload | Disable |

```text
TIM11CLK = 100 MHz
f_CNT    = 100 MHz / (99 + 1) = 1 MHz
T_COUNT  = 1 us
```

TIM11은 `HAL_TIM_Base_Start(&htim11)`로 시작합니다. `delay_us()`는 `__HAL_TIM_SET_COUNTER()`로 CNT를 0으로 만든 뒤 `__HAL_TIM_GET_COUNTER()`가 요청 Count에 도달할 때까지 기다립니다. TIM11 Interrupt는 사용하지 않습니다.

## 4. TIM3 Channel 1 - Echo Input Capture

### Mode

- Clock Source: Internal Clock
- Channel 1: Input Capture direct mode
- Channel 2~4: Disable
- Slave Mode: Disable
- Trigger Source: Disable
- One Pulse Mode: Disabled

### Counter Settings

| 항목 | 설정 |
|---|---:|
| Prescaler | 99 |
| Counter Mode | Up |
| Counter Period | 65535 |
| Internal Clock Division | No Division |
| Auto-reload Preload | Disable |

### Input Capture Channel 1

| 항목 | 설정 | Register 의미 |
|---|---|---|
| Polarity Selection | Rising Edge | 초기 `CC1P=0`, `CC1NP=0` |
| IC Selection | Direct | `CC1S=01`, TI1을 IC1에 연결 |
| Prescaler Division Ratio | No division | `IC1PSC=00`, 모든 Edge Capture |
| Input Filter | 0 | `IC1F=0000`, Digital Filter 미사용 |

수업 코드에서는 첫 Rising Edge를 읽은 뒤 `__HAL_TIM_SET_CAPTUREPOLARITY()`로 Falling Edge를 선택하고, 두 번째 Capture 후 다시 Rising Edge로 복구합니다.

## 5. NVIC

- TIM3 global interrupt: Enabled
- Preemption Priority: 0
- Sub Priority: 0

Input Capture Interrupt를 사용하려면 TIM3 Global Interrupt가 활성화되어야 합니다. 생성된 `TIM3_IRQHandler()`가 `HAL_TIM_IRQHandler(&htim3)`를 호출하면 HAL이 CC1 Flag와 Source를 판별한 뒤 `HAL_TIM_IC_CaptureCallback()`을 호출합니다.

## 6. HAL 초기화와 시작 구분

CubeMX 생성 영역에서는 다음 함수가 주변장치 설정을 구성합니다.

```c
MX_GPIO_Init();
MX_USART2_UART_Init();
MX_TIM3_Init();
MX_TIM11_Init();
```

복원본의 `USER CODE BEGIN 2`에서는 다음처럼 Timer를 실제로 시작합니다.

```c
HAL_TIM_Base_Start(&htim11);
HAL_TIM_IC_Start_IT(&htim3, TIM_CHANNEL_1);
```

개선본은 TIM3 Capture Channel을 시작한 뒤 CC1 Interrupt를 측정할 때만 활성화합니다.

```c
HAL_TIM_IC_Start(&htim3, TIM_CHANNEL_1);
__HAL_TIM_DISABLE_IT(&htim3, TIM_IT_CC1);
```

## 7. Input Capture 관련 Register 흐름

1. `TIM3_CCMR1.CC1S=01`이 TI1을 IC1에 연결합니다.
2. `TIM3_CCER.CC1E=1`이 Capture를 허용합니다.
3. 초기 `CC1P=0`, `CC1NP=0`에서 Rising Edge를 선택합니다.
4. Edge가 들어오면 CNT가 CCR1에 Latch되고 `SR.CC1IF`가 설정됩니다.
5. `DIER.CC1IE=1`이면 TIM3 IRQ가 발생합니다.
6. HAL IRQ Handler가 Source와 Flag를 처리하고 Input Capture Callback을 호출합니다.
7. Callback은 `HAL_TIM_ReadCapturedValue()`로 CCR1을 읽습니다.
8. Polarity를 Falling으로 바꾸어 Echo 종료 Edge를 캡처합니다.

## 8. 측정 범위와 Counter Period

```text
ARR + 1             = 65,536 Count
Counter Period      = 65,536 us
Guide Out-range 기준 = 약 38,000 us
```

한 번의 정상 Echo Pulse는 한 Counter Period 안에 들어옵니다. 다만 Rising Edge가 Wrap 직전에 발생할 수 있으므로 두 Capture 값의 순서가 뒤집히는 경우를 처리해야 합니다.

```c
if (falling >= rising)
{
  pulse = falling - rising;
}
else
{
  pulse = ((ARR + 1U) - rising) + falling;
}
```

## 9. USART2 출력

`printf()`의 한 문자를 USART2 Blocking Transmit으로 보내도록 `__io_putchar()` 또는 `fputc()`를 재정의합니다. 함수 원형은 `USER CODE BEGIN PFP`, 함수 정의는 `USER CODE BEGIN 4`에 둡니다.

```c
PUTCHAR_PROTOTYPE
{
  HAL_UART_Transmit(&huart2, (uint8_t *)&ch, 1U, HAL_MAX_DELAY);
  return ch;
}
```

## 10. 현재 보관 범위

- 이 문서는 수업 캡처에서 확인한 CubeMX 설정을 기록한 것입니다.
- `.ioc`와 CubeMX가 생성한 전체 Project는 포함하지 않습니다.
- `tim.c/.h`, `gpio.c/.h`, `usart.c/.h` 및 IRQ Handler는 해당 설정으로 생성되는 파일로 전제합니다.
- 전체 Project를 다시 확보하면 이 설정 문서와 대조하여 재현 가능한 CubeIDE Project 단위로 추가할 수 있습니다.
