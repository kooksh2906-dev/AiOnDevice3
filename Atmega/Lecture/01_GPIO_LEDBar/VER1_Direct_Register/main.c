#include <stdio.h>
#include <avr/io.h>
#include <util/delay.h>

int main()
{
    DDRD = 0xFF;

    while (1)
    {
        for (uint8_t i = 0; i < 4; i++)
        {
            PORTD = (0x05 << i);
            _delay_ms(200);
        }

        for (uint8_t i = 0; i < 4; i++)
        {
            PORTD = (0xA0 >> i);
            _delay_ms(200);
        }
    }
}
