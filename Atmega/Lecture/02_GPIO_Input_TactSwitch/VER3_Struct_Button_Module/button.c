#include "button.h"

void ButtonInit(BUTTON *button, volatile uint8_t *ddr,
                volatile uint8_t *pin, uint8_t pinNum)
{
    button->ddr = ddr;
    button->pin = pin;
    button->btnPin = pinNum;
    button->prevState = RELEASED;

    // 전달받은 버튼 핀만 입력으로 설정한다.
    *button->ddr &= (uint8_t)~(1U << button->btnPin);
}

uint8_t ButtonGetState(BUTTON *button)
{
    uint8_t curState = *button->pin & (1U << button->btnPin);

    // Active-Low 입력이므로 0이면 눌림 상태이다.
    if ((curState == PUSHED) && (button->prevState == RELEASED))
    {
        _delay_ms(50);
        button->prevState = PUSHED;
        return ACT_PUSH;
    }
    else if ((curState != PUSHED) && (button->prevState == PUSHED))
    {
        _delay_ms(50);
        button->prevState = RELEASED;
        return ACT_RELEASE;
    }

    return NO_ACT;
}

