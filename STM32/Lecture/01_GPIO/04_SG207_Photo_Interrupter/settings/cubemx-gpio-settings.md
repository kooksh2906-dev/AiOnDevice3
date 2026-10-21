# STM32CubeMX GPIO 설정

## 1. 원본 화면에서 확인한 설정

| Signal | STM32F411RE Pin | CubeMX Mode | 확인 근거 |
|---|---|---|---|
| SG-207 Collector Output | PC4 | `GPIO_Input` | CubeMX Pinout 화면 |

보관 화면에는 PC13 EXTI, PA5 GPIO Output 및 USART2 Pin도 함께 표시되지만 SG-207 입력 실습에서 직접 사용하는 Pin은 PC4입니다.

## 2. 실습 회로

```text
VDD -- 220 Ω -- SG-207 Anode
GND ----------- SG-207 Cathode

VDD -- 10 kΩ --+-- PC4
                |
                +-- SG-207 Collector
GND ---------------- SG-207 Emitter
```

- Slit에 빛이 통과하면 포토트랜지스터가 도통되어 PC4가 Low가 됩니다.
- Slit의 빛이 차단되면 포토트랜지스터가 Off되고 10 kΩ Pull-up으로 PC4가 High가 됩니다.
- PC4 Pull-up 전압은 Digital Input 전압 조건을 만족해야 합니다. STM32F411xC/xE 자료에서 PC4는 Digital Mode의 `FT` I/O로 분류됩니다.

## 3. 재현 시 CubeMX 기준

| 항목 | 설정 |
|---|---|
| Pin | PC4 |
| Mode | GPIO Input |
| Pull-up/Pull-down | No Pull - 외부 10 kΩ Pull-up 사용 |
| EXTI/NVIC | 사용하지 않음 |

원본 Pinout 화면에는 Pull 설정이 표시되지 않으므로 `No Pull`은 보관된 외부 Pull-up 회로를 기준으로 한 재현 설정입니다.

## 4. 관련 Register와 HAL 함수

- `GPIOC_MODER.MODER4 = 00`: PC4 Input Mode
- `GPIOC_PUPDR.PUPDR4 = 00`: No Pull 재현 설정
- `GPIOC_IDR.IDR4`: PC4의 현재 입력 Level
- `HAL_GPIO_ReadPin(GPIOC, GPIO_PIN_4)`: `GPIOC_IDR`에서 PC4 상태를 읽어 `GPIO_PIN_RESET` 또는 `GPIO_PIN_SET`으로 반환

## 5. 보관 범위

- 확인됨: PC4 `GPIO_Input`, `uint8_t data`, `HAL_GPIO_ReadPin()` Polling, 200 ms Delay, Debugger의 0/1 변화
- 확인되지 않음: 원본 `.ioc`, GPIO Pull 세부 설정, 실습 전원 VDD의 정확한 값

