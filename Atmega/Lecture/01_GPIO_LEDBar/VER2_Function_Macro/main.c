#include <stdio.h>
#include <avr/io.h>
#include <util/delay.h>

#define LED_DDR  DDRD
#define LED_PORT PORTD

// LED Output Func
void GPIO_Output(uint8_t data)
{
    LED_PORT = data;
}

// LED Init Func
void ledInit()
{
    LED_DDR = 0xFF;
}

// Func that LED shifts left and right
void ledShift(uint8_t i, uint8_t *data)
{
    *data = (1 << i) | (1 << (7 - i));
}

int main()
{
    ledInit();
    uint8_t ledData = 0x01;

    while (1)
    {
        for (int i = 0; i < 8; i++)
        {
            ledShift(i, &ledData);
            GPIO_Output(ledData);
            _delay_ms(1000);
        }
    }
}
