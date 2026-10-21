#include "button_exti.h"

#define BUTTON_EXTI_DEBOUNCE_MS (50U)

static volatile uint32_t last_accepted_tick;
static volatile bool press_event_pending;

void buttonExtiInit(void)
{
    /* 부팅 직후 첫 Event도 즉시 수락할 수 있도록 기준 시점을 보정합니다. */
    last_accepted_tick = HAL_GetTick() - BUTTON_EXTI_DEBOUNCE_MS;
    press_event_pending = false;
}

void buttonExtiCaptureFromIsr(uint16_t GPIO_Pin)
{
    uint32_t current_tick;

    if (GPIO_Pin != GPIO_PIN_13)
    {
        return;
    }

    current_tick = HAL_GetTick();

    /* ISR에서 기다리지 않고 일정 시간 안의 중복 Edge를 무시합니다. */
    if ((uint32_t)(current_tick - last_accepted_tick) >= BUTTON_EXTI_DEBOUNCE_MS)
    {
        last_accepted_tick = current_tick;
        press_event_pending = true;
    }
}

bool buttonExtiTakePressEvent(void)
{
    uint32_t previous_primask;
    bool event;

    /* ISR과 Main이 공유하는 Flag를 짧은 Critical Section에서 가져옵니다. */
    previous_primask = __get_PRIMASK();
    __disable_irq();

    event = press_event_pending;
    press_event_pending = false;

    if (previous_primask == 0U)
    {
        __enable_irq();
    }

    return event;
}

void HAL_GPIO_EXTI_Callback(uint16_t GPIO_Pin)
{
    /* Callback에서는 Event 수집만 수행하고 응용 동작은 Main으로 넘깁니다. */
    buttonExtiCaptureFromIsr(GPIO_Pin);
}
