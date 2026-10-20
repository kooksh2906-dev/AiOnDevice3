#include <avr/io.h>
#include <util/delay.h>

int main(void)
{
    DDRB |= (1 << PB4);

    // Timer0 Fast PWM, 비반전 출력, 64분주
    TCCR0 |= (1 << WGM00) | (1 << COM01) |
             (1 << WGM01) | (1 << CS02);

    while (1)
    {
        /*
         * 원자료의 uint8_t 반복문을 보존한다.
         * uint8_t는 255 다음 0으로 되돌아가므로 i < 256은 항상 참이며,
         * 이 반복문은 OCR0를 0~255로 계속 순환시키는 Sawtooth Sweep이 된다.
         */
        for (uint8_t i = 0; i < 256; i++)
        {
            OCR0 = i;
            _delay_ms(10);
        }
    }
}
