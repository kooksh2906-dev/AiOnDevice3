# CubeMX Settings — DHT11 Single-bus Polling

## 1. System Clock

수업 Project의 Clock 조건입니다.

| 항목 | 값 |
|---|---:|
| SYSCLK/HCLK | 100 MHz |
| APB1 Prescaler | 2 |
| APB2 Prescaler | 1 |
| TIM11 Clock | 100 MHz |

TIM11은 APB2에 연결되며 이번 설정에서 PCLK2와 같은 100 MHz를 입력받습니다.

## 2. TIM11

CubeMX 수업 화면에서 확인한 설정입니다.

| Parameter | Value | 의미 |
|---|---:|---|
| Peripheral | TIM11 Activated | Base Timer 사용 |
| Channel 1 | Disable | Capture/Compare Pin 미사용 |
| Prescaler | 99 | 100 MHz / 100 = 1 MHz |
| Counter Mode | Up | 1 us마다 CNT 증가 |
| Counter Period | 65535 | 16-bit 최대값 |
| Internal Clock Division | No Division | 추가 CKD 분주 없음 |
| Auto-reload Preload | Disable | ARR 고정 사용 |
| NVIC | Disable | Counter Polling이므로 Interrupt 불필요 |

```text
f_CNT = 100,000,000 / (99 + 1) = 1,000,000 Hz
1 Count = 1 us
```

`HAL_TIM_Base_Start()` 후 `__HAL_TIM_SET_COUNTER()`와 `__HAL_TIM_GET_COUNTER()`로 시간을 측정합니다.

## 3. DHT11 DATA GPIO

| 항목 | 설정 |
|---|---|
| Pin | PC4 |
| 초기 Mode | GPIO Input 권장 |
| Pull | No Pull |
| 외부 회로 | DATA-VDD 사이 5 kΩ Pull-up |
| Runtime Output | GPIO Output Push-Pull, High Speed |
| Runtime Input | GPIO Input, No Pull |

CubeMX에서 PC4를 초기 Input으로 설정하고, Driver가 Start 신호를 만들 때 `HAL_GPIO_Init()`으로 Output으로 바꾼 뒤 Sensor 응답 전에 다시 Input으로 전환합니다. 외부 Pull-up이 없는 Bare Sensor 구성에서는 DATA 선이 안정된 High Idle 상태를 유지하지 못합니다.

## 4. USART2와 printf Retargeting

| 항목 | 설정 |
|---|---|
| USART | USART2 Asynchronous |
| TX/RX | PA2/PA3 |
| 용도 | 온도·습도 및 오류 상태 Terminal 출력 |

`__io_putchar()` 또는 `fputc()`를 `HAL_UART_Transmit()`으로 연결합니다. 사용자 함수 정의는 `main.c`의 `USER CODE BEGIN 4`에 둡니다.

## 5. DHT11 배선

| DHT11 Pin | 연결 |
|---|---|
| 1 VDD | 3.3 V 또는 5 V, 사용 Module 사양 확인 |
| 2 DATA | PC4, VDD와 5 kΩ Pull-up |
| 3 NC | 연결하지 않음 |
| 4 GND | STM32 GND |

VDD-GND 사이에 100 nF Bypass Capacitor를 Sensor 가까이에 배치할 수 있습니다. Cable 길이가 길어지면 Pull-up 값과 신호 품질을 다시 검토해야 합니다.

## 6. 현재 보관 범위

- TIM11 CubeMX 화면, PC4 Pinout, Driver 화면과 Debugging 결과를 기준으로 설정을 복원했습니다.
- 원본 `.ioc`, 생성된 Peripheral 파일 및 전체 CubeIDE Project는 포함하지 않았습니다.
- 실물 Board 재현 시 TIM11 Clock이 실제로 100 MHz인지 Clock Tree에서 다시 확인해야 합니다.
