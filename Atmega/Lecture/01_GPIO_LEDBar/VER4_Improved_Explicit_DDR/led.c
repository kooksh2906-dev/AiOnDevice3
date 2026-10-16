#include "led.h"

void ledInit(LED *led)
{
    // DDR 주소를 명시적으로 사용하여 선택한 핀만 출력으로 설정한다.
    *(led->ddr) |= (uint8_t)(1U << led->pin);
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
