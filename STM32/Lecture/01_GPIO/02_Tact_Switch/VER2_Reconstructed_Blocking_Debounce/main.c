/*
 * Reconstructed blocking-debounce version.
 * A state change is confirmed after a short HAL_Delay() and a second read.
 */

#include "main.h"
#include "gpio.h"

#define BUTTON_DEBOUNCE_MS (20U)

void SystemClock_Config(void);

int main(void)
{
    GPIO_PinState stable_state;

    HAL_Init();
    SystemClock_Config();
    MX_GPIO_Init();

    stable_state = HAL_GPIO_ReadPin(GPIOC, GPIO_PIN_13);

    while (1)
    {
        GPIO_PinState sampled_state;

        sampled_state = HAL_GPIO_ReadPin(GPIOC, GPIO_PIN_13);

        if (sampled_state != stable_state)
        {
            /* 입력 변화가 안정될 시간을 기다리므로 이 구간은 Blocking입니다. */
            HAL_Delay(BUTTON_DEBOUNCE_MS);
            sampled_state = HAL_GPIO_ReadPin(GPIOC, GPIO_PIN_13);

            if (sampled_state != stable_state)
            {
                stable_state = sampled_state;

                /* Released -> Pressed로 확정될 때 한 번만 LED를 반전합니다. */
                if (stable_state == GPIO_PIN_RESET)
                {
                    HAL_GPIO_TogglePin(GPIOA, GPIO_PIN_5);
                }
            }
        }
    }
}
