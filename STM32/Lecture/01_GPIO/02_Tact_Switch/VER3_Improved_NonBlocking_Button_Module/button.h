#ifndef INC_BUTTON_H_
#define INC_BUTTON_H_

#include "main.h"

#include <stdbool.h>

typedef struct
{
    GPIO_TypeDef *port;
    uint16_t pin;
    GPIO_PinState active_state;
    GPIO_PinState raw_state;
    GPIO_PinState stable_state;
    uint32_t debounce_ms;
    uint32_t last_raw_change_tick;
    bool pressed_event;
} BUTTON_CONTROL;

void buttonInit(BUTTON_CONTROL *button,
                GPIO_TypeDef *port,
                uint16_t pin,
                GPIO_PinState active_state,
                uint32_t debounce_ms);
void buttonUpdate(BUTTON_CONTROL *button);
bool buttonIsPressed(const BUTTON_CONTROL *button);
bool buttonWasPressed(BUTTON_CONTROL *button);

#endif /* INC_BUTTON_H_ */
