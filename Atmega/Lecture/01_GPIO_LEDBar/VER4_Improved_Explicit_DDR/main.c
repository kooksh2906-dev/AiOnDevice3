#include <util/delay.h>
#include "led.h"

int main(void)
{
    LED led =
    {
        .ddr = &DDRD,
        .port = &PORTD,
        .pin = 0
    };

    // 구조체에 저장된 DDR 주소를 사용하여 PD0~PD7을 각각 출력으로 설정한다.
    for (uint8_t i = 0; i < 8; i++)
    {
        led.pin = i;
        ledInit(&led);
    }

    led.pin = 0;

    while (1)
    {
        ledOn(&led);
        _delay_ms(300);

        ledOff(&led);

        led.pin++;

        if (led.pin > 7)
        {
            led.pin = 0;
        }

        _delay_ms(200);
    }
}
