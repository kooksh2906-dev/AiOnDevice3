#include "led.h"

void ledInit(LED *led)
{
    // DDR 레지스터는 PORT 레지스터보다 1 낮은 위치에 있다.
    // *(led->port - 1)를 이용해 PORT에서 DDR로 접근한다.
    // |= (1 << led->pin)을 이용해 선택한 핀만 출력 모드로 설정한다.
    *(led->port - 1) |= (1 << led->pin);
}

void ledOn(LED *led)
{
    // 해당 핀을 High로 설정해서 LED를 켠다.
    *(led->port) |= (1 << led->pin);
}

void ledOff(LED *led)
{
    // 해당 핀을 Low로 설정해서 LED를 끈다.
    *(led->port) &= ~(1 << led->pin);
}
