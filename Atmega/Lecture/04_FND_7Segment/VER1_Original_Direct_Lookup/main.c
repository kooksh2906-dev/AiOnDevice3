#include <avr/io.h>
#include <util/delay.h>

int main(void)
{
    // 원자료에 제시된 0~9 Segment Pattern을 그대로 보존한다.
    uint8_t fndNumber[] = {
        0x3F, 0x06, 0x5B, 0x4F, 0x66,
        0x6D, 0x7D, 0x27, 0x7F, 0x67
    };

    int count = 0;

    // PC0~PC7을 FND Segment 출력으로 설정한다.
    DDRC = 0xFF;

    while (1)
    {
        // count를 10으로 나눈 나머지를 숫자 Pattern Index로 사용한다.
        PORTC = fndNumber[(count++) % 10];
        _delay_ms(500);
    }
}
