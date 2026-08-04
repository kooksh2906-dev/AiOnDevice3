#include "delay.h"

void delay_us(uint16_t us)
{
    uint16_t start = (uint16_t)__HAL_TIM_GET_COUNTER(&htim2);

    while ((uint16_t)((uint16_t)__HAL_TIM_GET_COUNTER(&htim2) - start) < us) {
        __NOP();
    }
}
