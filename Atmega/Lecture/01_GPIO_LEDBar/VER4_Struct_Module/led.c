#include "led.h"

void ledInit(LED *led)
{
    *(led->port - 1) |= (1 << led->pin);
}

void ledOn(LED *led)
{
    *(led->port) |= (1 << led->pin);
}

void ledOff(LED *led)
{
    *(led->port) &= ~(1 << led->pin);
}
