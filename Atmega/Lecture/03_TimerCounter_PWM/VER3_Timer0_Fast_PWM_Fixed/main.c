#include <avr/io.h>
#include <util/delay.h>

int main(void)
{
    // PB4/OC0를 출력으로 설정한다.
    DDRB |= (1 << PB4);

    /*
     * WGM01:0=11 : 8-bit Fast PWM, TOP=0xFF
     * COM01:0=10 : 비반전 PWM
     * CS02:0=100 : 64분주
     */
    TCCR0 |= (1 << WGM00) | (1 << COM01) |
             (1 << WGM01) | (1 << CS02);

    // 약 25.39% Duty: (64 + 1) / 256
    OCR0 = 64;

    while (1)
    {
        // PWM 파형은 Timer0 하드웨어가 계속 생성한다.
    }
}
