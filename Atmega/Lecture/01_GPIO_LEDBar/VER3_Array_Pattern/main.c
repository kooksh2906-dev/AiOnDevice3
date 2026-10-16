#include <stdio.h>
#include <avr/io.h>
#include <util/delay.h>

uint8_t ledArr[] =
{
    0x00,
    0x80,   // 1000 0000
    0xC0,   // 1100 0000
    0xE0,   // 1110 0000
    0xF0,   // 1111 0000
    0xF8,   // 1111 1000
    0xFC,   // 1111 1100
    0xFE,   // 1111 1110
    0xFF,   // 1111 1111
    0x7F,   // 0111 1111
    0x3F,   // 0011 1111
    0x1F,   // 0001 1111
    0x0F,   // 0000 1111
    0x07,   // 0000 0111
    0x03,   // 0000 0011
    0x01    // 0000 0001
};

int main()
{
    DDRD = 0xFF;

    uint8_t arrSize = sizeof(ledArr) / sizeof(ledArr[0]);

    while (1)
    {
        for (uint8_t i = 0; i < arrSize; i++)
        {
            PORTD = ledArr[i];
            _delay_ms(200);
        }
    }
}
