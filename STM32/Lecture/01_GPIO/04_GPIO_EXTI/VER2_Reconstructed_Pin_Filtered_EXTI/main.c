/*
 * Reconstructed from the retained CubeMX settings and callback screenshot.
 * CubeMX-generated clock and GPIO initialization bodies are not reproduced.
 */

#include "main.h"
#include "gpio.h"

void SystemClock_Config(void);

int main(void)
{
    HAL_Init();
    SystemClock_Config();
    MX_GPIO_Init();

    while (1)
    {
        /* Button Event는 EXTI Callback에서 처리됩니다. */
    }
}

void HAL_GPIO_EXTI_Callback(uint16_t GPIO_Pin)
{
    /* EXTI10~15는 IRQ Vector를 공유하므로 발생 Pin을 확인합니다. */
    if (GPIO_Pin == GPIO_PIN_13)
    {
        HAL_GPIO_TogglePin(GPIOA, GPIO_PIN_5);
    }
}
