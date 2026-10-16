#include <avr/io.h>
#include <util/delay.h>

#define LED_PORT PORTD
#define LED_DDR  DDRD

typedef struct
{
    volatile uint8_t *port; // Port which connected with LED
    uint8_t pin;            // Pin number which connected with LED
} LED;

void ledInit(LED *led);
void ledOn(LED *led);
void ledOff(LED *led);
