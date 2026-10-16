#include <avr/io.h>
#include <util/delay.h>

int main(void)
{
    // DDRD의 모든 비트를 1로 설정하여 PD0~PD7을 출력으로 구성한다.
    DDRD = 0xFF;

    while (1)
    {
        // 0x05 패턴을 MSB 방향으로 이동한다.
        for (uint8_t i = 0; i < 4; i++)
        {
            PORTD = (uint8_t)(0x05U << i);
            _delay_ms(200);
        }

        // 0xA0 패턴을 LSB 방향으로 이동한다.
        for (uint8_t i = 0; i < 4; i++)
        {
            PORTD = (uint8_t)(0xA0U >> i);
            _delay_ms(200);
        }
    }
}
