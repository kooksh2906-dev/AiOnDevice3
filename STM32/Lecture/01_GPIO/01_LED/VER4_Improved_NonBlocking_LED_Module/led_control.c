#include "led_control.h"

#include <stddef.h>

void ledControlInit(LED_CONTROL *led,
                    GPIO_TypeDef *port,
                    uint16_t pin,
                    uint32_t interval_ms,
                    GPIO_PinState initial_state)
{
    if ((led == NULL) || (port == NULL))
    {
        return;
    }

    led->port = port;
    led->pin = pin;
    led->interval_ms = interval_ms;
    led->last_tick = HAL_GetTick();
    led->state = initial_state;

    /* 구조체에 저장한 초기 상태와 실제 GPIO 출력을 일치시킵니다. */
    HAL_GPIO_WritePin(led->port, led->pin, led->state);
}

void ledControlSetInterval(LED_CONTROL *led, uint32_t interval_ms)
{
    if (led == NULL)
    {
        return;
    }

    led->interval_ms = interval_ms;
    led->last_tick = HAL_GetTick();
}

void ledControlUpdate(LED_CONTROL *led)
{
    uint32_t current_tick;

    if ((led == NULL) || (led->port == NULL) || (led->interval_ms == 0U))
    {
        return;
    }

    current_tick = HAL_GetTick();

    /* Unsigned subtraction keeps the elapsed-time comparison wraparound-safe. */
    if ((uint32_t)(current_tick - led->last_tick) >= led->interval_ms)
    {
        led->last_tick = current_tick;
        led->state = (led->state == GPIO_PIN_RESET) ? GPIO_PIN_SET : GPIO_PIN_RESET;

        /* HAL_GPIO_WritePin()은 GPIOx_BSRR를 사용하여 Pin을 Set/Reset합니다. */
        HAL_GPIO_WritePin(led->port, led->pin, led->state);
    }
}

