#include "led.h"

void ledInit(LED *led)
{
    /*
     * ATmega128A의 Port D에서는 DDRD가 PORTD보다 한 주소 앞에 있다.
     * PORT 포인터에서 1을 빼 DDR에 접근하고, 선택한 핀만 출력으로 설정한다.
     * 이 주소 관계를 다른 MCU에 그대로 일반화할 수는 없다.
     */
    *(led->port - 1) |= (uint8_t)(1U << led->pin);
}

void ledOn(LED *led)
{
    // 다른 비트 상태를 유지하면서 선택한 핀만 High로 설정한다.
    *(led->port) |= (uint8_t)(1U << led->pin);
}

void ledOff(LED *led)
{
    // 반전 마스크를 사용해 선택한 핀만 Low로 설정한다.
    *(led->port) &= (uint8_t)~(1U << led->pin);
}
