#include <avr/io.h>
#include <util/delay.h>

int main(void)
{
    // PB4는 Timer0의 OC0 출력 핀이다.
    DDRB |= (1 << PB4);

    /*
     * COM00=1: Compare Match마다 OC0 Toggle
     * WGM01=1: CTC Mode, TOP=OCR0
     * CS02=1 : 64분주
     */
    TCCR0 |= (1 << COM00) | (1 << WGM01) | (1 << CS02);

    // 16 MHz / (2 * 64 * (1 + 124)) = 1 kHz OC0 출력
    OCR0 = 124;

    while (1)
    {
        // OCF0(bit 1)가 Set될 때까지 Compare Match Flag를 Polling한다.
        while ((TIFR & 0x02) == 0)
        {
        }

        // ATmega Flag는 해당 비트에 1을 써서 해제한다.
        TIFR = 0x02;

        // 원자료의 반복 대입을 보존한다. 고정 주파수에서는 다시 쓸 필요는 없다.
        OCR0 = 124;
    }
}
