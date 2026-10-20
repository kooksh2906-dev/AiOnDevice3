#include "button.h"

#include <stddef.h>

void buttonInit(BUTTON_CONTROL *button,
                GPIO_TypeDef *port,
                uint16_t pin,
                GPIO_PinState active_state,
                uint32_t debounce_ms)
{
    GPIO_PinState initial_state;

    if ((button == NULL) || (port == NULL))
    {
        return;
    }

    initial_state = HAL_GPIO_ReadPin(port, pin);

    button->port = port;
    button->pin = pin;
    button->active_state = active_state;
    button->raw_state = initial_state;
    button->stable_state = initial_state;
    button->debounce_ms = debounce_ms;
    button->last_raw_change_tick = HAL_GetTick();
    button->pressed_event = false;
}

void buttonUpdate(BUTTON_CONTROL *button)
{
    GPIO_PinState sampled_state;
    uint32_t current_tick;

    if ((button == NULL) || (button->port == NULL))
    {
        return;
    }

    current_tick = HAL_GetTick();
    sampled_state = HAL_GPIO_ReadPin(button->port, button->pin);

    if (sampled_state != button->raw_state)
    {
        /* 새 후보 Level이 나타난 시점부터 Debounce 시간을 다시 측정합니다. */
        button->raw_state = sampled_state;
        button->last_raw_change_tick = current_tick;
    }

    if ((button->raw_state != button->stable_state) &&
        ((uint32_t)(current_tick - button->last_raw_change_tick) >= button->debounce_ms))
    {
        button->stable_state = button->raw_state;

        /* 안정 상태가 Active로 바뀌는 순간만 1회성 Press Event로 저장합니다. */
        if (button->stable_state == button->active_state)
        {
            button->pressed_event = true;
        }
    }
}

bool buttonIsPressed(const BUTTON_CONTROL *button)
{
    if (button == NULL)
    {
        return false;
    }

    return button->stable_state == button->active_state;
}

bool buttonWasPressed(BUTTON_CONTROL *button)
{
    bool event;

    if (button == NULL)
    {
        return false;
    }

    event = button->pressed_event;
    button->pressed_event = false;

    return event;
}
