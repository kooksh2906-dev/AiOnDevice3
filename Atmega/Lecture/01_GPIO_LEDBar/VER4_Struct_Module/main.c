#include <util/delay.h>
#include "led.h"

int main(void)
{
    LED led;

    led.port = &PORTD;
    led.pin = 0;

    // 구조체의 pin 값을 바꿔가며 PD0~PD7을 각각 출력으로 설정한다.
    for (uint8_t i = 0; i < 8; i++)
    {
        led.pin = i;
        ledInit(&led);
    }

    // 초기화 반복문 종료 후 남아 있는 pin=7을 시작 위치 pin=0으로 복원한다.
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
