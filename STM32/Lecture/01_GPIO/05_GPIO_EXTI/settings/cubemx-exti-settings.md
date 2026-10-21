# STM32CubeMX / EXTI 설정

## 1. 학습 기록 원본 설정

| 대상 | Pin/IRQ | 원본 설정 |
|---|---|---|
| Board LED | PA5 | GPIO Output Push-Pull, No Pull, Low Speed |
| User Button | PC13 | External Interrupt Mode with Rising Edge Trigger Detection |
| PC13 Pull | PC13 | Pull-up |
| NVIC | EXTI line[15:10] interrupts | Enabled, Preemption Priority 0, Sub Priority 0 |

`VER1_Original_Callback`와 원본 Evidence는 위 설정을 수정하지 않고 보존합니다.

## 2. Board 회로 기준 개선 설정

| 대상 | Pin/IRQ | 개선 설정 | 이유 |
|---|---|---|---|
| Board LED | PA5 | GPIO Output Push-Pull, No Pull | User LED LD2 제어 |
| User Button | PC13 | External Interrupt Mode with Rising Edge Trigger Detection | Active-High Button Press 검출 |
| PC13 Pull | PC13 | No Pull | Board의 외부 Pull-down 회로 사용 |
| NVIC | EXTI line[15:10] interrupts | Enabled | EXTI13이 EXTI10~15 공용 Vector 사용 |

Bare-Metal 복원에서는 원본 Priority 0을 유지할 수 있습니다. FreeRTOS에 이식할 때에는 Interrupt 안에서 RTOS API를 호출하는지와 `configLIBRARY_MAX_SYSCALL_INTERRUPT_PRIORITY`를 함께 검토한 뒤 NVIC Priority를 정해야 합니다.

## 3. 생성 코드에서 확인할 항목

`gpio.c`:

```c
GPIO_InitStruct.Pin = GPIO_PIN_13;
GPIO_InitStruct.Mode = GPIO_MODE_IT_RISING;
GPIO_InitStruct.Pull = GPIO_NOPULL;
HAL_GPIO_Init(GPIOC, &GPIO_InitStruct);

HAL_NVIC_SetPriority(EXTI15_10_IRQn, 0, 0);
HAL_NVIC_EnableIRQ(EXTI15_10_IRQn);
```

`stm32f4xx_it.c`:

```c
void EXTI15_10_IRQHandler(void)
{
    HAL_GPIO_EXTI_IRQHandler(GPIO_PIN_13);
}
```

## 4. 관련 레지스터

- `RCC_APB2ENR.SYSCFGEN`: SYSCFG Clock 활성화
- `SYSCFG_EXTICR4.EXTI13`: EXTI13 Source를 Port C로 선택
- `EXTI_IMR.MR13`: EXTI13 Interrupt Request 허용
- `EXTI_RTSR.TR13`: EXTI13 Rising Edge 검출 활성화
- `EXTI_FTSR.TR13`: Falling Edge 검출 여부
- `EXTI_PR.PR13`: EXTI13 Pending 상태 및 Write-1-to-Clear
- NVIC ISER/IPR: `EXTI15_10_IRQn` Enable 및 Priority
