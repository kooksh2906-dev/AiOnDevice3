#include <avr/io.h>
#include <util/delay.h>
#include <stdint.h>

#define LED_DDR             DDRD
#define LED_PORT            PORTD
#define LED_STEP_DELAY_MS   200

void GPIO_Output(uint8_t data)
{
    /*
     * PORTD의 8개 출력 핀을 한 번에 갱신한다.
     * 이 실습은 High 출력에서 LED가 켜지는 연결을 전제로 한다.
     */
    LED_PORT = data;
}

void ledInit(void)
{
    // DDRD의 모든 비트를 1로 설정하여 PD0~PD7을 출력으로 설정한다.
    LED_DDR = 0xFF;
}

/*
 * 추가 함수 1
 * 단일 1비트를 bit 0에서 bit 7 방향으로 이동한다.
 * 출력: 0x01 -> 0x02 -> 0x04 -> ... -> 0x80
 */
void ledShiftLeft(void)
{
    for (uint8_t i = 0; i < 8; i++)
    {
        GPIO_Output((uint8_t)(1U << i));
        _delay_ms(LED_STEP_DELAY_MS);
    }
}

/*
 * 추가 함수 2
 * 단일 1비트를 bit 7에서 bit 0 방향으로 이동한다.
 * 출력: 0x80 -> 0x40 -> 0x20 -> ... -> 0x01
 */
void ledShiftRight(void)
{
    for (uint8_t i = 0; i < 8; i++)
    {
        GPIO_Output((uint8_t)(0x80U >> i));
        _delay_ms(LED_STEP_DELAY_MS);
    }
}

/*
 * 추가 함수 3
 * 0x55(0101 0101)와 0xAA(1010 1010)를 교대로 출력한다.
 */
void ledEvenOdd(void)
{
    GPIO_Output(0x55);
    _delay_ms(LED_STEP_DELAY_MS);

    GPIO_Output(0xAA);
    _delay_ms(LED_STEP_DELAY_MS);
}

int main(void)
{
    ledInit();

    while (1)
    {
        ledShiftLeft();
        ledShiftRight();
        ledEvenOdd();
    }
}
