#include <avr/io.h>
#include <util/delay.h>
#include <stdint.h>

#define LED_DDR               DDRD
#define LED_PORT              PORTD
#define BUTTON_DDR            DDRG
#define BUTTON_PIN_REG        PING
#define BUTTON_ROTATE_LEFT    2U
#define BUTTON_ROTATE_RIGHT   3U
#define BUTTON_CLEAR          4U
#define BUTTON_REPEAT_MS      200

int main(void)
{
    uint8_t ledData = 0x01U;
    uint8_t buttonData;

    LED_DDR = 0xFFU;

    // 원자료의 방식대로 PORTG의 5개 GPIO를 모두 입력으로 설정한다.
    BUTTON_DDR = 0x00U;

    LED_PORT = 0x00U;

    while (1)
    {
        // 같은 반복 주기에서 세 버튼을 판정하기 위해 PING를 한 번 읽는다.
        buttonData = BUTTON_PIN_REG;

        if ((buttonData & (1U << BUTTON_ROTATE_LEFT)) == 0U)
        {
            LED_PORT = ledData;

            // bit 7을 bit 0으로 되돌리는 8-bit Rotate-Left이다.
            ledData = (uint8_t)((ledData >> 7U) | (ledData << 1U));
            _delay_ms(BUTTON_REPEAT_MS);
        }

        if ((buttonData & (1U << BUTTON_ROTATE_RIGHT)) == 0U)
        {
            LED_PORT = ledData;

            // bit 0을 bit 7로 되돌리는 8-bit Rotate-Right이다.
            ledData = (uint8_t)((ledData >> 1U) | (ledData << 7U));
            _delay_ms(BUTTON_REPEAT_MS);
        }

        if ((buttonData & (1U << BUTTON_CLEAR)) == 0U)
        {
            LED_PORT = 0x00U;
        }
    }
}

