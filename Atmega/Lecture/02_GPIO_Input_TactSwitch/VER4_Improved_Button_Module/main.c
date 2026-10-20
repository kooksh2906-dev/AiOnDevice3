#include "button.h"

#define LED_DDR            DDRD
#define LED_PORT           PORTD
#define BUTTON_DDR         DDRG
#define BUTTON_PORT        PORTG
#define BUTTON_PIN_REG     PING
#define BUTTON_ON_PIN      2U
#define BUTTON_OFF_PIN     3U
#define BUTTON_TOGGLE_PIN  4U

int main(void)
{
    Button buttonOn;
    Button buttonOff;
    Button buttonToggle;

    LED_DDR = 0xFFU;
    LED_PORT = 0x00U;

    buttonInit(&buttonOn, &BUTTON_DDR, &BUTTON_PORT, &BUTTON_PIN_REG,
               BUTTON_ON_PIN);
    buttonInit(&buttonOff, &BUTTON_DDR, &BUTTON_PORT, &BUTTON_PIN_REG,
               BUTTON_OFF_PIN);
    buttonInit(&buttonToggle, &BUTTON_DDR, &BUTTON_PORT, &BUTTON_PIN_REG,
               BUTTON_TOGGLE_PIN);

    while (1)
    {
        // 학습 원본과 동일하게 버튼을 뗀 순간에 동작을 확정한다.
        if (buttonGetEvent(&buttonOn) == BUTTON_EVENT_RELEASED)
        {
            LED_PORT = 0xFFU;
        }

        if (buttonGetEvent(&buttonOff) == BUTTON_EVENT_RELEASED)
        {
            LED_PORT = 0x00U;
        }

        if (buttonGetEvent(&buttonToggle) == BUTTON_EVENT_RELEASED)
        {
            LED_PORT ^= 0xFFU;
        }
    }
}

