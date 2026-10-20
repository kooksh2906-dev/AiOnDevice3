/*
 * Reconstructed reference version.
 * The original Tact Switch polling source was not retained. PC13 input and
 * PA5 LED were reconstructed from the later EXTI lesson configuration.
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
        GPIO_PinState button_state;

        /* Board 외부 Pull-down 회로이므로 High(GPIO_PIN_SET)를 눌림으로 해석합니다. */
        button_state = HAL_GPIO_ReadPin(GPIOC, GPIO_PIN_13);

        if (button_state == GPIO_PIN_SET)
        {
            HAL_GPIO_WritePin(GPIOA, GPIO_PIN_5, GPIO_PIN_SET);
        }
        else
        {
            HAL_GPIO_WritePin(GPIOA, GPIO_PIN_5, GPIO_PIN_RESET);
        }
    }
}
