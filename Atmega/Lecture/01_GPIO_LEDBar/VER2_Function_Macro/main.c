#include <avr/io.h>
#include <util/delay.h>

#define LED_DDR  DDRD
#define LED_PORT PORTD

// 계산된 8비트 패턴을 PORTD 전체에 출력한다.
void GPIO_Output(uint8_t data)
{
    LED_PORT = data;
}

// PD0~PD7을 모두 출력 모드로 설정한다.
void ledInit(void)
{
    LED_DDR = 0xFF;
}

/*
 * 양 끝의 LED를 동시에 선택하여 중앙으로 이동한 후
 * 다시 바깥쪽으로 이동하는 대칭 비트 패턴을 생성한다.
 *
 * i = 0~7 출력:
 * 0x81 -> 0x42 -> 0x24 -> 0x18 -> 0x18 -> 0x24 -> 0x42 -> 0x81
 */
void ledShift(uint8_t i, uint8_t *data)
{
    *data = (uint8_t)((1U << i) | (1U << (7U - i)));
}

int main(void)
{
    uint8_t ledData = 0U; // 첫 ledShift() 호출에서 출력 패턴으로 갱신된다.

    ledInit();

    while (1)
    {
        for (uint8_t i = 0; i < 8; i++)
        {
            ledShift(i, &ledData);
            GPIO_Output(ledData);
            _delay_ms(1000);
        }
    }
}
