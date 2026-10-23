# CubeMX Settings - ADC1 and SZH-EK056 Joystick

이 문서는 수업 캡처에서 확인한 Polling, Interrupt 및 DMA 설정을 재현하기 위한 기록입니다. 원본 `.ioc`가 없으므로 실제 Project를 다시 만들 때 Clock Tree와 Pin 충돌을 함께 확인해야 합니다.

## 공통 Board와 Clock

- Board: NUCLEO-F411RE
- SYSCLK: 100 MHz
- PCLK2: 100 MHz
- ADC Prescaler: PCLK2 / 4
- ADCCLK: 25 MHz
- Resolution: 12 bits
- Data Alignment: Right
- Trigger: Software Start
- External Trigger Edge: None
- USART2: PA2/PA3, ST-LINK Virtual COM Port
- Linker: `Use float with printf from newlib-nano (-u _printf_float)` Enable

## Joystick 연결

| 기능 | STM32 Pin | ADC Channel | Sequence |
|---|---|---|---|
| X축 | PA7 | ADC1_IN7 | Rank 1, `adcValue[0]` |
| Y축 | PA6 | ADC1_IN6 | Rank 2, `adcValue[1]` |
| 전원 | 3.3 V | - | ADC 허용 입력 범위 유지 |
| GND | GND | - | 공통 기준 전압 |

Z축 눌림 Switch는 실제 수업 코드에서 사용하지 않았으므로 설정하지 않습니다. 모듈 Connector의 물리적 Pin 순서는 정식 데이터시트로 확인되지 않았으므로 실물 Silkscreen을 기준으로 연결합니다.

## 1. Polling

### ADC1 Parameter Settings

- Scan Conversion Mode: Disabled
- Continuous Conversion Mode: Disabled
- Discontinuous Conversion Mode: Disabled
- DMA Continuous Requests: Disabled
- EOC Selection: End of Single Conversion
- Number of Conversion: 1
- Rank 1: Channel 7
- Sampling Time: 3 cycles

### 실행 흐름

```c
HAL_ADC_Start(&hadc1);
HAL_ADC_PollForConversion(&hadc1, 500U);
adcValue = HAL_ADC_GetValue(&hadc1);
```

## 2. Interrupt

### ADC1 Parameter Settings

- Scan Conversion Mode: Disabled
- Continuous Conversion Mode: Enabled
- Number of Conversion: 1
- Rank 1: Channel 7
- Sampling Time: 3 cycles

### NVIC

- ADC1 global interrupt: Enabled

### 실행 흐름

```c
HAL_ADC_Start_IT(&hadc1);
```

ADC 변환 완료 시 `ADC_IRQHandler()`와 HAL IRQ Handler를 거쳐 `HAL_ADC_ConvCpltCallback()`이 호출됩니다. 사용자 Callback 정의는 `main.c`의 `USER CODE BEGIN 4`에 둡니다.

## 3. Two-channel Circular DMA

### ADC1 Parameter Settings

- Scan Conversion Mode: Enabled
- Continuous Conversion Mode: Enabled
- DMA Continuous Requests: Enabled
- EOC Selection: End of Single Conversion
- Number of Conversion: 2
- Rank 1: Channel 7, Sampling Time 480 cycles
- Rank 2: Channel 6, Sampling Time 480 cycles

### DMA2 Stream 0

- Request: ADC1
- Direction: Peripheral to Memory
- Mode: Circular
- Peripheral Increment: Disabled
- Memory Increment: Enabled
- Peripheral Data Width: Half Word
- Memory Data Width: Half Word
- Priority: Low
- FIFO: Disabled

### Initialization Order

```c
MX_GPIO_Init();
MX_DMA_Init();
MX_USART2_UART_Init();
MX_ADC1_Init();
```

DMA Interrupt를 사용할 경우 DMA NVIC가 ADC 시작 전에 초기화되어야 합니다. 수업 복원본은 배열의 Raw 값을 Foreground에서 출력하므로 별도 DMA Callback을 정의하지 않습니다.

## Register 연결

| 설정 | 주요 Register Bit |
|---|---|
| ADC Clock /4 | `ADC_CCR.ADCPRE` |
| 12-bit | `ADC_CR1.RES = 00` |
| Scan Mode | `ADC_CR1.SCAN` |
| Continuous Mode | `ADC_CR2.CONT` |
| DMA Enable/Continuous Request | `ADC_CR2.DMA`, `ADC_CR2.DDS` |
| Rank와 Sequence Length | `ADC_SQR1`, `ADC_SQR3` |
| Channel 6/7 Sampling | `ADC_SMPR2.SMP6`, `ADC_SMPR2.SMP7` |
| DMA Circular/Increment/Width | `DMA_SxCR.CIRC`, `MINC`, `PSIZE`, `MSIZE` |

## 재현 시 확인 사항

- PA6/PA7가 다른 Peripheral Alternate Function과 충돌하지 않는지 확인합니다.
- Joystick을 3.3 V로 구동하고 X/Y 출력이 `VREF-~VREF+` 범위를 벗어나지 않는지 확인합니다.
- `-u _printf_float`가 없으면 `%f` 전압 출력이 정상적으로 Link되지 않거나 출력되지 않을 수 있습니다.
- Rank 순서를 바꾸면 DMA 배열의 X/Y Index도 함께 바뀝니다.
- Sampling Time을 줄일 때에는 Source Impedance와 변환 안정성을 실물에서 다시 확인합니다.

