/*
 * Original callback fragment preserved from the retained LAB_EXTI screenshot.
 * The include is restored only so this fragment can be checked independently.
 */

#include "main.h"

void HAL_GPIO_EXTI_Callback(uint16_t GPIO_Pin)
{
    HAL_GPIO_TogglePin(GPIOA, GPIO_PIN_5);
}
