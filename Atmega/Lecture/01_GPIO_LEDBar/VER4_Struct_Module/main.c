#include <stdio.h>
#include "led.h"

int main()
{
    LED led;        // LED라는 구조를 가진 led 변수 선언
    led.port = &PORTD;
    led.pin = 0;

    for (uint8_t i = 0; i < 8; i++)
    {
        led.pin = i;
        ledInit(&led);
    }

    // ledInit(&led);
    // DDRD = 0xFF;

    while (1)
    {
        ledOn(&led);
        _delay_ms(300);

        ledOff(&led);

        led.pin++;

        if (led.pin > 7)
        {
            led.pin = 0;
        }

        _delay_ms(200);
    }
}
