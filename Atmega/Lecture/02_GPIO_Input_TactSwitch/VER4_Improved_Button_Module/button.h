#ifndef BUTTON_H_
#define BUTTON_H_

#include <avr/io.h>
#include <stdint.h>

typedef enum
{
    BUTTON_LEVEL_PRESSED = 0,
    BUTTON_LEVEL_RELEASED = 1
} ButtonLevel;

typedef enum
{
    BUTTON_EVENT_NONE = 0,
    BUTTON_EVENT_PRESSED,
    BUTTON_EVENT_RELEASED
} ButtonEvent;

typedef struct
{
    volatile uint8_t *ddr;
    volatile uint8_t *port;
    volatile uint8_t *pin;
    uint8_t pinNumber;
    ButtonLevel previousLevel;
} Button;

void buttonInit(Button *button, volatile uint8_t *ddr,
                volatile uint8_t *port, volatile uint8_t *pin,
                uint8_t pinNumber);
ButtonEvent buttonGetEvent(Button *button);

#endif /* BUTTON_H_ */

