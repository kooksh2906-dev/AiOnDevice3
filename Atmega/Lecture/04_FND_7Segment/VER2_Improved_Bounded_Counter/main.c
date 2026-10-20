#include <avr/io.h>
#include <util/delay.h>
#include <stdint.h>

#define FND_DIGIT_COUNT 10U

// 원자료의 7·9 글꼴을 유지하되 실행 중 변경되지 않도록 const로 선언한다.
static const uint8_t fndNumber[FND_DIGIT_COUNT] = {
    0x3FU, 0x06U, 0x5BU, 0x4FU, 0x66U,
    0x6DU, 0x7DU, 0x27U, 0x7FU, 0x67U
};

int main(void)
{
    uint8_t count = 0U;

    DDRC = 0xFFU;
    PORTC = 0x00U;

    while (1)
    {
        PORTC = fndNumber[count];
        _delay_ms(500);

        count++;
        if (count >= FND_DIGIT_COUNT)
        {
            count = 0U;
        }
    }
}
