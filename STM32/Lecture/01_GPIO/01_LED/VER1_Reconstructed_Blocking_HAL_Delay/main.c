/*
 * Reconstructed reference version.
 * The original Blocking lesson file was not retained. This minimal example was
 * reconstructed from the HAL_Delay()/HAL_GPIO_TogglePin() pattern that remains
 * in later lesson sources.
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
        /* HAL_Delay()가 끝날 때까지 다음 Loop 작업은 실행되지 않습니다. */
        HAL_GPIO_TogglePin(GPIOA, GPIO_PIN_5);
        HAL_Delay(500U);
    }
}

