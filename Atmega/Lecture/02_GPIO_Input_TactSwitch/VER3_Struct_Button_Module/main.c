#include "button.h"

int main(void)
{
    LED_DDR = 0xFFU;

    BUTTON btnOn;
    BUTTON btnOff;
    BUTTON btnTog;

    ButtonInit(&btnOn, &BUTTON_DDR, &BUTTON_PIN, BUTTON_ON);
    ButtonInit(&btnOff, &BUTTON_DDR, &BUTTON_PIN, BUTTON_OFF);
    ButtonInit(&btnTog, &BUTTON_DDR, &BUTTON_PIN, BUTTON_TOGGLE);

    while (1)
    {
        // 원자료는 버튼을 뗀 순간(ACT_RELEASE)에 LED 동작을 실행한다.
        if (ButtonGetState(&btnOn) == ACT_RELEASE)
        {
            LED_PORT = 0xFFU;
        }

        if (ButtonGetState(&btnOff) == ACT_RELEASE)
        {
            LED_PORT = 0x00U;
        }

        if (ButtonGetState(&btnTog) == ACT_RELEASE)
        {
            LED_PORT ^= 0xFFU;
        }
    }
}

