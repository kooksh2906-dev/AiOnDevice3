#include <avr/io.h>
#include <stdint.h>

#define LED_DDR        DDRD
#define LED_PORT       PORTD
#define BUTTON_DDR     DDRG
#define BUTTON_PIN_REG PING
#define BUTTON_PIN_NUM 4U

int main(void)
{
    // PORTD 전체를 LED Bar 출력으로 설정한다.
    LED_DDR = 0xFFU;

    // 다른 PORTG 핀 설정은 유지하고 PG4만 입력으로 설정한다.
    BUTTON_DDR &= (uint8_t)~(1U << BUTTON_PIN_NUM);

    // 시작 시 LED Bar를 끈 상태로 명시한다.
    LED_PORT = 0x00U;

    while (1)
    {
        /*
         * 외부 Pull-up을 사용한 Active-Low 입력이다.
         * PG4가 High이면 버튼을 놓은 상태, Low이면 누른 상태이다.
         */
        if ((BUTTON_PIN_REG & (1U << BUTTON_PIN_NUM)) != 0U)
        {
            LED_PORT = 0x00U;
        }
        else
        {
            LED_PORT = 0xFFU;
        }
    }
}

