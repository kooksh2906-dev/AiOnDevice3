# STM32CubeMX GPIO 설정

## 1. 8-bit 병렬 방식

| LCD Signal | STM32F411RE Pin | Mode |
|---|---|---|
| RS | PA5 | GPIO Output |
| E | PA7 | GPIO Output |
| DB0 | PC7 | GPIO Output |
| DB1 | PA9 | GPIO Output |
| DB2 | PA8 | GPIO Output |
| DB3 | PB10 | GPIO Output |
| DB4 | PB4 | GPIO Output |
| DB5 | PB5 | GPIO Output |
| DB6 | PB3 | GPIO Output |
| DB7 | PA10 | GPIO Output |

## 2. 4-bit 병렬 방식

| LCD Signal | STM32F411RE Pin | Mode |
|---|---|---|
| RS | PA5 | GPIO Output |
| E | PA7 | GPIO Output |
| DB4 | PB12 | GPIO Output |
| DB5 | PB13 | GPIO Output |
| DB6 | PB14 | GPIO Output |
| DB7 | PB15 | GPIO Output |

## 3. 공통 GPIO 설정

- GPIO Output Level: Low
- GPIO Mode: Output Push-Pull
- GPIO Pull-up/Pull-down: No Pull
- Maximum Output Speed: Low
- Project Structure: Advanced

CubeMX가 생성하는 MX_GPIO_Init()에서 GPIOA, GPIOB 및 8-bit 방식의 GPIOC Clock을 활성화하고 각 Pin을 Output으로 초기화해야 합니다.

## 4. LCD Module 연결

| LCD Pin | 연결 |
|---|---|
| VSS | GND |
| VDD | +5 V |
| V0(VEE) | 가변저항 Wiper |
| R/W | GND |
| A(LED+) | +5 V |
| K(LED-) | GND |

R/W를 GND에 고정했으므로 LCD는 Write-only로 동작합니다. Busy Flag를 읽는 대신 Driver의 Delay로 명령 실행 시간을 확보합니다.
