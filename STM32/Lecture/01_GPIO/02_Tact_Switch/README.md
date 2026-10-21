# GPIO Tact Switch - Polling / Debounce

## 1. 학습 개요

STM32F411RE의 GPIO 입력으로 Tact Switch 상태를 읽고, 입력 Level을 그대로 사용하는 Polling 방식에서 한 번의 눌림을 Event로 판정하는 Debounce 방식까지 확장합니다.

보관 자료에서는 Tact Switch Polling 원본 소스가 확인되지 않았습니다. 이후 EXTI 실습 기록에서 `PC13` 입력과 `PA5` Board LED 사용을 확인했으며, NUCLEO-F411RE 공식 회로도에서 PC13 User Button의 외부 Pull-down과 Active-High 연결을 추가로 확인했습니다. 따라서 이번 코드는 Board 회로를 기준으로 Polling 방식으로 복원했으며, 원본 코드로 표기하지 않았습니다.

## 2. 버전 구성

| 버전 | 성격 | 주요 내용 |
|---|---|---|
| `VER1_Reconstructed_Raw_Level_Polling` | 복원 기준본 | `HAL_GPIO_ReadPin()`으로 PC13을 반복 판독하고, 눌린 동안 PA5 LED를 켭니다. 입력 Level과 출력 Level의 직접 대응을 확인합니다. |
| `VER2_Reconstructed_Blocking_Debounce` | 복원·기초 개선 | 입력 변화가 감지되면 `HAL_Delay(20)` 후 다시 읽어 상태를 확정합니다. 확정된 Press Edge마다 LED를 한 번 Toggle합니다. |
| `VER3_Improved_NonBlocking_Button_Module` | 개선·모듈화 | `HAL_GetTick()`으로 입력이 일정 시간 유지되었는지 검사합니다. 대기하지 않고 안정 상태와 Press Event를 관리하며, Button 로직을 소스·헤더로 분리합니다. |

## 3. Active-High 입력

NUCLEO-F411RE의 PC13 User Button은 Board의 외부 Pull-down에 의해 평상시 `GPIO_PIN_RESET`으로 유지되고, Button을 누르면 VDD 방향으로 연결되어 `GPIO_PIN_SET`으로 해석합니다.

```c
if (HAL_GPIO_ReadPin(GPIOC, GPIO_PIN_13) == GPIO_PIN_SET)
{
    /* Pressed */
}
```

Active 상태는 회로 구성에 따라 달라집니다. 다른 Board나 외부 Switch를 사용할 때에는 회로와 Pull-up/Pull-down 설정을 먼저 확인해야 합니다.

## 4. HAL과 레지스터의 관계

| 학습 코드 | HAL/초기화 동작 | 관련 하드웨어 동작 |
|---|---|---|
| `MX_GPIO_Init()` | GPIO Clock 활성화 및 입력·출력 Pin 설정 | `GPIOx_MODER`, `GPIOx_PUPDR` 등 설정 |
| `HAL_GPIO_ReadPin(GPIOC, GPIO_PIN_13)` | PC13의 논리 Level 반환 | `GPIOC_IDR`의 Bit 13 판독 |
| `HAL_GPIO_WritePin()` | PA5 LED Set/Reset | `GPIOA_BSRR`에 Set/Reset Bit 기록 |
| `HAL_GPIO_TogglePin()` | PA5 출력 상태 반전 | 출력 상태를 읽어 대상 Bit 반전 |
| `HAL_GetTick()` | 현재 ms Tick 반환 | Non-Blocking Debounce의 경과 시간 계산 |

`GPIOx_MODER`에서 입력 모드는 `00`입니다. Board의 외부 Pull-down을 사용하므로 `GPIOx_PUPDR`는 No Pull(`00`)로 설정하며, 입력 Pin의 현재 값은 읽기 전용 `GPIOx_IDR`에 반영되고 `HAL_GPIO_ReadPin()`이 이를 판독합니다.

## 5. Polling, Edge, Debounce

- **Level Polling**은 현재 눌려 있는지를 계속 확인합니다. 누르고 있는 동안 같은 동작이 반복되어도 되는 LED 점등과 같은 제어에 적합합니다.
- **Edge 검출**은 안정 상태가 Released에서 Pressed로 바뀌는 순간만 Event로 만듭니다. 한 번 누를 때 한 번만 Toggle하거나 Count해야 할 때 필요합니다.
- **Debounce**는 기계식 접점이 짧은 시간 여러 번 붙었다 떨어지는 현상을 하나의 상태 변화로 확정하는 처리입니다.

Blocking 버전은 이해하기 쉽지만 입력 변화마다 20 ms 동안 다른 Loop 작업을 멈춥니다. Non-Blocking 버전은 후보 상태가 바뀐 시각을 저장하고, 같은 상태가 Debounce 시간 이상 유지된 경우에만 안정 상태를 변경합니다.

## 6. 핵심 학습 포인트

- 입력 Pin은 Floating 상태를 피하도록 회로에 맞는 Pull-up 또는 Pull-down을 설정해야 합니다.
- NUCLEO-F411RE의 외부 Pull-down 기반 Active-High 회로에서는 `GPIO_PIN_SET`이 Pressed 상태입니다.
- 현재 Level과 한 번의 Press Event는 서로 다른 개념이며, Event 제어에는 이전 상태의 저장이 필요합니다.
- 단순 지연 기반 Debounce는 구현이 간단하지만 Super Loop의 다른 작업을 일시 정지시킵니다.
- `HAL_GetTick()` 기반 Debounce는 다른 GPIO, UART 및 주기 작업과 함께 실행하기 유리합니다.
- Debounce 시간 20 ms는 실습 기준값이며 실제 Switch 특성과 요구 응답성에 맞추어 조정해야 합니다.

## 7. 검증 상태

- 공식 Reference Manual, HAL/LL User Manual 및 NUCLEO-F411RE Board 회로도를 바탕으로 GPIO 입력, Pull 설정 및 `HAL_GPIO_ReadPin()` 동작을 정적 검토했습니다.
- 세 버전의 CubeIDE 형식 `main.c`와 개선 모듈은 HAL Stub을 사용하여 C 문법 및 경고 검사를 수행할 수 있도록 구성했습니다.
- 원본 Tact Switch Polling 소스와 `.ioc`는 현재 보관 자료에서 확인되지 않아, 이후 EXTI 실습에 남아 있는 PC13/PA5 설정을 기반으로 복원했습니다.
- 이번 정리 과정에서는 CubeIDE 재빌드와 STM32F411RE 실물 보드 재시험을 수행하지 않았습니다.
