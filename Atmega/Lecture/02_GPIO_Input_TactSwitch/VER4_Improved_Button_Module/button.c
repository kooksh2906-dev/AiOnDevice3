#include "button.h"

#include <util/delay.h>

#define BUTTON_DEBOUNCE_MS 50

static ButtonLevel buttonReadLevel(const Button *button)
{
    const uint8_t mask = (uint8_t)(1U << button->pinNumber);

    // 외부 Pull-up 기반 Active-Low 입력을 논리적인 버튼 상태로 변환한다.
    return ((*button->pin & mask) == 0U)
               ? BUTTON_LEVEL_PRESSED
               : BUTTON_LEVEL_RELEASED;
}

void buttonInit(Button *button, volatile uint8_t *ddr,
                volatile uint8_t *port, volatile uint8_t *pin,
                uint8_t pinNumber)
{
    button->ddr = ddr;
    button->port = port;
    button->pin = pin;
    button->pinNumber = pinNumber;

    // 해당 핀만 입력으로 바꾸고 다른 PORTG 방향 설정은 보존한다.
    *button->ddr &= (uint8_t)~(1U << button->pinNumber);

    /*
     * 데이터시트에 따르면 입력 모드에서 PORTxn=1이면 내부 Pull-up이 켜진다.
     * 이 실습은 외부 10 kOhm Pull-up을 사용하므로 PORTG의 해당 비트를
     * 명시적으로 0으로 만들어 내부 Pull-up을 끈다.
     */
    *button->port &= (uint8_t)~(1U << button->pinNumber);

    // 시작 시 실제 핀 값을 읽어 잘못된 첫 이벤트를 방지한다.
    button->previousLevel = buttonReadLevel(button);
}

ButtonEvent buttonGetEvent(Button *button)
{
    ButtonLevel currentLevel = buttonReadLevel(button);

    if (currentLevel == button->previousLevel)
    {
        return BUTTON_EVENT_NONE;
    }

    /*
     * 기계식 접점 바운스가 가라앉기를 기다린 뒤 다시 읽는다.
     * 두 번째 값이 이전 안정 상태와 같으면 일시적인 튐으로 판단한다.
     */
    _delay_ms(BUTTON_DEBOUNCE_MS);
    currentLevel = buttonReadLevel(button);

    if (currentLevel == button->previousLevel)
    {
        return BUTTON_EVENT_NONE;
    }

    button->previousLevel = currentLevel;

    return (currentLevel == BUTTON_LEVEL_PRESSED)
               ? BUTTON_EVENT_PRESSED
               : BUTTON_EVENT_RELEASED;
}

