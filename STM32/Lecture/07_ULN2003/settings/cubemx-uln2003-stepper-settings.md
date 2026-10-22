# CubeMX Settings — 28BYJ-48 + ULN2003

## 1. GPIO

수업 CubeMX Pinout과 코드에 확인되는 Pin Mapping입니다.

| Pin | User Label 권장값 | Mode | Output Type | Pull | Speed | Initial Level |
|---|---|---|---|---|---|---|
| PB1 | `STEPPER_IN1` | GPIO Output | Push-Pull | No pull | Low | Low |
| PB15 | `STEPPER_IN2` | GPIO Output | Push-Pull | No pull | Low | Low |
| PB14 | `STEPPER_IN3` | GPIO Output | Push-Pull | No pull | Low | Low |
| PB13 | `STEPPER_IN4` | GPIO Output | Push-Pull | No pull | Low | Low |

`Low speed`는 Step 신호가 수백 Hz 수준인 이 실습에 충분하며 불필요한 Edge Noise를 줄이는 데 유리합니다. 시작 시 네 상을 모두 Low로 두어 Cube 초기화 중 의도하지 않은 통전을 피합니다.

## 2. TIM10 Base Timer with Interrupt

강사님 참고 코드의 `100 MHz → PSC 99 → 1 MHz` 계산을 재현하는 설정입니다. 원본 `.ioc`가 없으므로 Prescaler와 Period의 CubeMX 화면 자체가 아니라 코드와 Clock 조건에서 복원한 값입니다.

| Parameter | Value | 의미 |
|---|---:|---|
| Clock Source | Internal Clock | APB2 Timer Clock 사용 |
| TIM10 input clock | 100 MHz | 수업 System Clock 기준 |
| Prescaler | 99 | 1 MHz Counter Clock, 1 us/count |
| Counter Mode | Up | ARR까지 증가 후 Update Event 발생 |
| Counter Period | 2499 예시 | 400 Hz, 2.5 ms/step |
| Auto-reload preload | Disable 또는 응용에 맞게 선택 | 속도 변경 시 반영 시점 확인 필요 |

### 주파수별 ARR

```text
ARR = (1,000,000 / desired_step_frequency) - 1
```

| Step Frequency | ARR |
|---:|---:|
| 1000 Hz | 999 |
| 800 Hz | 1249 |
| 600 Hz | 1665 |
| 400 Hz | 2499 |
| 200 Hz | 4999 |

## 3. NVIC

- `TIM1 update interrupt and TIM10 global interrupt`를 Enable합니다.
- STM32F411에서 TIM10은 `TIM1_UP_TIM10_IRQn`을 공유합니다.
- 생성된 `stm32f4xx_it.c`의 Handler가 `HAL_TIM_IRQHandler(&htim10)`을 호출해야 HAL의 `HAL_TIM_PeriodElapsedCallback()`까지 연결됩니다.
- Callback에서는 `htim->Instance == TIM10`을 확인하여 다른 Base Timer Event와 구분합니다.

## 4. 배선과 전원

| 연결 | 내용 |
|---|---|
| PB1/PB15/PB14/PB13 | ULN2003 Module IN1/IN2/IN3/IN4 |
| ULN2003 Motor Connector | 28BYJ-48 5-wire Connector |
| ULN2003 VCC | Motor용 5 V 전원 |
| ULN2003 GND | Motor 전원 GND와 STM32 GND 공통 |
| ULN2003 COM | Module Schematic에 따라 Clamp Diode 공통단을 Motor 전원에 연결 |

Motor 권선을 STM32 GPIO에 직접 연결하지 않습니다. USB/Board 5 V를 사용할 때도 Motor 기동·정지 전류와 전압 강하가 MCU Reset에 영향을 주지 않는지 확인하며, 필요한 경우 충분한 전류 용량의 외부 5 V 전원을 사용합니다.

## 5. 현재 보관 범위

- 실제 수업 Pinout, Header/Source 화면과 강사님 참고 코드에서 설정을 복원했습니다.
- USART2 PA2/PA3는 수업 Project에 함께 설정되어 있었으나 Stepper 구동 자체의 필수 Peripheral은 아닙니다.
- 원본 `.ioc`, 생성된 Peripheral 파일과 전체 CubeIDE Project는 아직 포함하지 않았습니다.
- CubeIDE 재생성 또는 실물 Board 검증 전에는 이 문서를 재현용 설정 안내로 사용하고, 실제 Project Clock Tree와 Pin Label을 다시 대조해야 합니다.
