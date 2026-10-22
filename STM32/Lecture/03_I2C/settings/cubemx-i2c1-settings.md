# STM32CubeMX I2C1 설정

2026년 5월 21일 학습 자료의 CubeMX 화면과 Pinout을 기준으로 정리했습니다. 화면에 직접 확인되는 설정과 일반적인 생성 결과를 구분합니다.

## 1. 확인된 Board 및 Peripheral

- MCU/Board: STM32F411RE / NUCLEO-F411RE
- Peripheral: I2C1
- I2C Mode: I2C
- I2C Speed Mode: Standard Mode
- I2C Clock Speed: 100000 Hz
- Clock No Stretch Mode: Disabled
- Primary Address Length: 7-bit
- Dual Address Acknowledged: Disabled
- Primary Slave Address: 0
- General Call Address Detection: Disabled

이번 실습에서 STM32는 Controller로 동작하므로 Own Address 0은 LCD Target 주소를 의미하지 않습니다. LCD Backpack의 Target Address `0x27`은 `HAL_I2C_Master_Transmit()` 호출에서 지정합니다.

## 2. Pin Mapping

| STM32F411RE Pin | Alternate Function | 연결 대상 |
|---|---|---|
| PB6 | I2C1_SCL | LCD Backpack SCL |
| PB7 | I2C1_SDA | LCD Backpack SDA |
| GND | - | LCD Backpack GND |
| Module 전원 | - | 사용한 Backpack/LCD Module 사양에 맞게 연결 |

CubeMX Pinout 화면에는 USART2_TX PA2와 USART2_RX PA3도 활성화되어 있습니다. 이는 기본 Serial 출력 환경으로 남아 있으며 I2C LCD Driver 자체에는 사용되지 않습니다.

## 3. GPIO 전기적 특성

I2C1 GPIO는 CubeMX가 Alternate Function Open-drain으로 생성합니다. SDA와 SCL이 High로 복귀하려면 Pull-up이 필요합니다. Backpack에 Pull-up이 실장되어 있는지 확인하고, 없거나 Bus Rise Time이 기준을 만족하지 않으면 외부 Pull-up을 구성해야 합니다.

## 4. 전송 방식

- Polling/Blocking API: `HAL_I2C_Master_Transmit()`
- Interrupt: 사용 흔적 없음
- DMA: 사용 흔적 없음
- NVIC I2C Event/Error IRQ: 이번 실습에서는 필수 아님

## 5. CubeIDE 생성 코드에서의 위치

`main.c`는 생성된 Peripheral Header와 초기화 함수를 다음 순서로 사용합니다.

```c
#include "i2c.h"
#include "usart.h"
#include "gpio.h"

MX_GPIO_Init();
MX_I2C1_Init();
MX_USART2_UART_Init();
```

사용자 작성 `i2c_lcd.h` Include와 LCD 출력 호출은 각각 `USER CODE BEGIN Includes`와 `USER CODE BEGIN 2`에 배치합니다.

## 6. 보관 한계

- 위 값은 원본 설정 화면에 확인되는 범위입니다.
- 원본 `.ioc`, 생성된 `i2c.c/.h`, `gpio.c/.h` 및 전체 Project는 현재 보관본에 포함되지 않았습니다.
- GitHub에는 설정을 설명하는 문서만 저장하며 CubeMX 화면 캡처는 Notion에서 보존합니다.
