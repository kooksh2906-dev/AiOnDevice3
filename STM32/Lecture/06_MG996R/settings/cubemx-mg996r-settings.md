# STM32CubeMX Settings - MG996R Servo Motor

수업 자료의 CubeMX 화면과 코드에서 확인한 설정입니다. 전체 `.ioc`가 확보되지 않았으므로 화면에서 확인되지 않는 항목은 기본값으로 단정하지 않습니다.

## 1. Clock 기준

| 항목 | 값 |
|---|---:|
| SYSCLK | 100 MHz |
| APB1 Peripheral Clock | 50 MHz |
| APB1 Timer Clock | 100 MHz |
| TIM3 Counter Clock | 100 kHz |
| Counter Tick | 10 us |

APB1 Prescaler가 1이 아니므로 STM32F411 Timer Clock 규칙에 따라 TIM3CLK는 PCLK1의 2배인 100 MHz입니다.

## 2. TIM3

### Mode

- Clock Source: Internal Clock
- Channel 1: PWM Generation CH1
- PWM Output Pin: PA6, AF2 TIM3_CH1

### Parameter Settings

| 항목 | CubeMX 값 | 결과 |
|---|---:|---|
| Prescaler | `1000-1` | 100 kHz, 10 us/Count |
| Counter Mode | Up | 0부터 ARR까지 증가 |
| Counter Period | `2000-1` | 20 ms, 50 Hz Frame |
| Clock Division | No Division | 추가 분주 없음 |
| Auto-reload Preload | Disable | 수업 화면 보존 |
| PWM Mode | PWM mode 1 | CNT < CCR1에서 Active |
| Pulse | 100 | 초기 1.0 ms Pulse |
| Output Compare Preload | Enable | CCR1 Shadow 반영 |
| Fast Mode | Disable | 일반 PWM 동작 |
| CH Polarity | High | Active High Pulse |

## 3. USART2

- Mode: Asynchronous
- RX Interrupt 방식으로 1 Byte 명령 수신
- USART2 Global Interrupt: Enabled
- `HAL_UART_Receive_IT(&huart2, &rxData, 1)`로 최초 수신 등록
- `HAL_UART_RxCpltCallback()`에서 `huart->Instance == USART2` 확인

이번 MG996R 페이지에는 USART2 Baud Rate 화면이 남아 있지 않습니다. 전체 Project를 복원할 때에는 기존 UART 실습 설정과 실제 Terminal 설정을 대조하여 확정해야 합니다.

## 4. Wiring

| MG996R Wire | 연결 |
|---|---|
| Orange | PA6 / TIM3_CH1 PWM |
| Red | 외부 5~6 V 전원 VCC |
| Brown | 외부 전원 GND 및 STM32 GND |

TowerPro 공식 사양의 Stall 전류는 1.4 A입니다. 전원은 Servo의 순간 부하 전류를 감당할 수 있어야 하며, Motor 전류 경로를 STM32 GPIO 또는 3.3 V Rail에 연결하지 않습니다. PWM Signal 기준을 공유하기 위해 외부 전원과 Board의 GND를 공통으로 연결합니다.

## 5. 재현 시 확인 사항

1. PA6이 AF2 TIM3_CH1으로 지정되어 있는지 확인합니다.
2. Clock Tree에서 TIM3CLK가 실제로 100 MHz인지 확인합니다.
3. PSC 999와 ARR 1999로 20 ms Frame이 만들어지는지 계산합니다.
4. Motor를 연결하기 전에 Oscilloscope 또는 Logic Analyzer로 PWM 주기와 Pulse Width를 확인합니다.
5. 중심 Pulse 1.5 ms부터 시작하고 실제 기계적 Stop 전에 최소·최대 Pulse를 보정합니다.
6. 외부 전원의 정격 전류, 공통 GND 및 전원 극성을 확인합니다.
7. UART Baud Rate와 Terminal 설정을 동일하게 맞춥니다.
