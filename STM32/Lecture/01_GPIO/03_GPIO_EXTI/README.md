# GPIO EXTI - External Interrupt

## 1. 학습 개요

STM32F411RE의 PC13 User Button 입력을 Polling하지 않고, GPIO Edge가 발생했을 때 EXTI Interrupt로 처리하는 실습입니다. 보관된 실제 학습 기록에는 다음 설정과 코드가 남아 있습니다.

- PA5: GPIO Output, Board LED
- PC13: External Interrupt Mode with Rising Edge Trigger Detection
- PC13 Pull: Pull-up
- NVIC: `EXTI line[15:10] interrupts` Enable, Preemption Priority 0
- Callback: Pin 구분 없이 PA5 LED Toggle

원본 전체 CubeIDE 프로젝트와 `.ioc`는 확인되지 않았지만, CubeMX 설정 화면 3장과 Callback 코드 화면 1장을 바탕으로 설정과 코드를 분석했습니다. 원본 화면은 Notion 학습 기록에 보존하고, GitHub에는 코드와 설정 문서만 저장합니다.

## 2. 버전 구성

| 버전 | 성격 | 주요 내용 |
|---|---|---|
| `VER1_Original_Callback_Fragment` | 원본 조각 보존 | 기록 화면에서 확인한 `HAL_GPIO_EXTI_Callback()` 함수 본문을 그대로 보존합니다. Callback 인자인 `GPIO_Pin`을 확인하지 않고 PA5를 Toggle합니다. |
| `VER2_Reconstructed_Pin_Filtered_EXTI` | 복원·정정본 | CubeMX가 생성하는 Main Loop와 IRQ Handler 흐름을 최소 형태로 복원하고, Callback에서 `GPIO_PIN_13`을 확인합니다. |
| `VER3_Improved_Deferred_Debounced_EXTI` | 개선·모듈화 | ISR에서는 Pin 확인, 시간 간격 검사 및 Event 저장만 수행합니다. LED Toggle은 Main Loop가 Event를 가져가 처리합니다. |

## 3. Board 회로와 원본 설정 검토

NUCLEO-F411RE Board 자료에서는 User LED LD2가 PA5, User Button B1이 PC13에 연결됩니다. Board 회로에는 PC13 입력을 Low로 유지하는 외부 Pull-down 저항과 Button 입력의 직렬 저항이 포함되어 있으므로 Button을 누르면 PC13이 Low에서 High로 바뀌는 Active-High 구조입니다.

따라서 보관된 Rising Edge 설정은 **Button을 누르는 순간**을 검출하는 의도와 일치합니다. 다만 원본의 내부 Pull-up은 Board의 외부 Pull-down과 중복되므로 개선 설정에서는 `No Pull`을 사용합니다. 원본 동작을 부정하거나 덮어쓰지 않고, 원본 설정과 Board 회로 기준 개선 설정을 별도로 기록했습니다.

## 4. EXTI 처리 경로

```text
PC13 Rising Edge
    -> EXTI13 Pending
    -> EXTI15_10_IRQn
    -> EXTI15_10_IRQHandler()
    -> HAL_GPIO_EXTI_IRQHandler(GPIO_PIN_13)
    -> HAL_GPIO_EXTI_Callback(GPIO_PIN_13)
```

- `SYSCFG_EXTICR4`: EXTI13의 입력 Port를 GPIOC로 연결
- `EXTI_RTSR`: EXTI13 Rising Trigger Enable
- `EXTI_IMR`: EXTI13 Interrupt Mask 해제
- `EXTI_PR`: Edge 발생 시 Pending Bit Set, Handler에서 Write 1로 Clear
- NVIC `EXTI15_10_IRQn`: EXTI Line 10~15의 공용 IRQ 활성화

PC13은 EXTI Line 13을 사용하므로 단독 Vector가 아니라 `EXTI15_10_IRQn` 그룹에 포함됩니다. IRQ Handler는 HAL의 EXTI Handler를 호출하고, HAL은 Pending을 확인·해제한 뒤 사용자 Callback을 호출합니다.

## 5. 원본 Callback 분석

```c
void HAL_GPIO_EXTI_Callback(uint16_t GPIO_Pin)
{
    HAL_GPIO_TogglePin(GPIOA, GPIO_PIN_5);
}
```

이 코드는 PC13만 사용한 단일 실습에서는 LED를 Toggle할 수 있습니다. 그러나 `GPIO_Pin`을 확인하지 않으므로 이후 다른 EXTI Line을 추가해도 같은 Callback에서 PA5가 Toggle됩니다. 정정본은 다음과 같이 발생 Pin을 확인합니다.

```c
if (GPIO_Pin == GPIO_PIN_13)
{
    HAL_GPIO_TogglePin(GPIOA, GPIO_PIN_5);
}
```

## 6. ISR 최소화와 Debounce 개선

기계식 Button은 한 번 눌러도 짧은 시간 동안 여러 Edge를 만들 수 있습니다. ISR 안에서 `HAL_Delay()`로 기다리면 다른 Interrupt의 처리가 지연될 수 있으므로 개선본은 다음 원칙을 사용합니다.

1. Callback에서 PC13인지 확인합니다.
2. 마지막으로 수락한 Event 이후 50 ms가 지났는지 검사합니다.
3. 조건을 만족하면 `volatile` Event Flag만 저장합니다.
4. Main Loop가 Event를 안전하게 가져가 PA5를 Toggle합니다.

이 구조는 ISR 실행 시간을 줄이고 응용 동작을 Main Context로 이동합니다. 50 ms는 학습용 기준값이며 실제 Switch, 응답성 및 시스템 요구사항에 맞추어 조정해야 합니다.

## 7. 핵심 학습 포인트

- EXTI는 입력 Level 자체가 아니라 Rising, Falling 또는 양 Edge의 변화를 검출합니다.
- GPIO Pin과 EXTI Line 번호는 연결되며, PC13은 EXTI13을 사용합니다.
- EXTI10~15는 하나의 `EXTI15_10_IRQn` Vector를 공유하므로 Callback의 Pin 구분이 중요합니다.
- HAL의 IRQ Handler가 Pending Bit를 처리한 뒤 사용자 `HAL_GPIO_EXTI_Callback()`을 호출합니다.
- ISR에서는 긴 지연, 반복 처리 및 복잡한 응용 로직을 피하고 필요한 상태만 전달하는 편이 좋습니다.
- Board의 외부 Pull-up/Pull-down 회로를 확인한 뒤 CubeMX 내부 Pull 설정을 결정해야 합니다.
- 원본 코드 조각, 복원 정정본 및 개선 모듈을 분리하면 학습 당시 코드와 이후 개선 판단을 함께 설명할 수 있습니다.

## 8. 검증 상태

- Notion에 보관한 CubeMX 설정 및 Callback 화면을 원본 증거로 확인했습니다.
- Reference Manual, HAL/LL User Manual 및 NUCLEO-F411RE Board 회로도를 바탕으로 EXTI 경로와 Pin 회로를 정적 검토했습니다.
- 세 버전은 HAL Stub으로 C 문법 검사를 통과했습니다. VER2·VER3은 `-Wall -Wextra -Werror`를 적용했으며, VER1은 원본의 미사용 `GPIO_Pin` 인자를 보존하기 위해 해당 경고만 제외했습니다.
- 원본 `.ioc`와 전체 CubeIDE 프로젝트는 현재 보관본에 포함되지 않았습니다.
- 이번 정리 과정에서는 CubeIDE 재빌드와 STM32F411RE 실물 보드 재시험을 수행하지 않았습니다.
