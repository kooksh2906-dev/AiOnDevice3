#ifndef INC_LED_CONTROL_H_
#define INC_LED_CONTROL_H_

#include "main.h"

typedef struct
{
    GPIO_TypeDef *port;
    uint16_t pin;
    uint32_t interval_ms;
    uint32_t last_tick;
    GPIO_PinState state;
} LED_CONTROL;

void ledControlInit(LED_CONTROL *led,
                    GPIO_TypeDef *port,
                    uint16_t pin,
                    uint32_t interval_ms,
                    GPIO_PinState initial_state);
void ledControlSetInterval(LED_CONTROL *led, uint32_t interval_ms);
void ledControlUpdate(LED_CONTROL *led);

#endif /* INC_LED_CONTROL_H_ */

