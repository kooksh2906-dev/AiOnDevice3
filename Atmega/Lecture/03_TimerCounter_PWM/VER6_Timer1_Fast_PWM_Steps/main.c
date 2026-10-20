#include <avr/io.h>
#include <util/delay.h>

int main(void)
{
    DDRB |= (1 << PB5);

    // Timer1 Mode 14 Fast PWM, OC1A 비반전 출력, 64분주
    TCCR1A |= (1 << COM1A1) | (1 << WGM11);
    TCCR1B |= (1 << WGM13) | (1 << WGM12) |
              (1 << CS11) | (1 << CS10);
    TCCR1C = 0x00;

    // 50 Hz PWM 주기
    ICR1 = 4999;

    while (1)
    {
        // 약 2.524 ms High Pulse
        OCR1A = 630;
        _delay_ms(1000);

        // 약 1.020 ms High Pulse
        OCR1A = 254;
        _delay_ms(1000);

        // 약 0.484 ms High Pulse
        OCR1A = 120;
        _delay_ms(1000);
    }
}
