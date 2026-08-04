#include "photo.h"

bool Photo_IsTopBlocked(void)
{
    // PC4 상단 리밋 센서 검사 코드 반영
    return (HAL_GPIO_ReadPin(GPIOC, GPIO_PIN_2) != GPIO_PIN_RESET);
}

bool Photo_IsBottomBlocked(void)
{
    // PC3 하단 리밋 센서 검사 코드 반영
    return (HAL_GPIO_ReadPin(GPIOC, GPIO_PIN_3) != GPIO_PIN_RESET);
}
