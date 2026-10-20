#include <avr/io.h>
#include <util/delay.h>
#include <stdint.h>

#define FND_DDR         DDRC
#define FND_PORT        PORTC
#define FND_DIGIT_COUNT 10U
#define FND_STEP_MS     500

static const uint8_t fndNumber[FND_DIGIT_COUNT] = {
    0x3FU, 0x06U, 0x5BU, 0x4FU, 0x66U,
    0x6DU, 0x7DU, 0x27U, 0x7FU, 0x67U
};

void fndInit(void)
{
    FND_DDR = 0xFFU;
    FND_PORT = 0x00U;
}

void fndDisplayDigit(uint8_t digit)
{
    if (digit < FND_DIGIT_COUNT)
    {
        FND_PORT = fndNumber[digit];
    }
}

void fndClear(void)
{
    FND_PORT = 0x00U;
}

// 기초 함수 연습: 0부터 9까지 증가 출력한다.
void fndCountUp(void)
{
    for (uint8_t digit = 0U; digit < FND_DIGIT_COUNT; digit++)
    {
        fndDisplayDigit(digit);
        _delay_ms(FND_STEP_MS);
    }
}

// 심화 함수 연습: Unsigned Underflow 없이 9부터 0까지 감소 출력한다.
void fndCountDown(void)
{
    for (uint8_t digit = FND_DIGIT_COUNT; digit > 0U; digit--)
    {
        fndDisplayDigit((uint8_t)(digit - 1U));
        _delay_ms(FND_STEP_MS);
    }
}

int main(void)
{
    fndInit();

    while (1)
    {
        fndCountUp();
        fndCountDown();
        fndClear();
    }
}
