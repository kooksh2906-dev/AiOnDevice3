#include <avr/io.h>
#include <util/delay.h>

int main(void)
{
    // PB5는 Timer1 Channel A의 OC1A 출력 핀이다.
    DDRB |= (1 << PB5);

    /*
     * WGM13:0=1110: Mode 14 Fast PWM, TOP=ICR1
     * COM1A1:0=10 : OC1A 비반전 출력
     * CS12:0=011  : 64분주
     */
    TCCR1A |= (1 << COM1A1) | (1 << WGM11);
    TCCR1B |= (1 << WGM13) | (1 << WGM12) |
              (1 << CS11) | (1 << CS10);
    TCCR1C = 0x00;

    // 1,250 Count × 4 us = 5 ms High, 20 ms 주기의 25% Duty
    OCR1A = 1249;

    // 5,000 Count × 4 us = 20 ms, 즉 50 Hz
    ICR1 = 4999;

    while (1)
    {
        // Timer1 하드웨어가 고정 PWM 파형을 생성한다.
    }
}
