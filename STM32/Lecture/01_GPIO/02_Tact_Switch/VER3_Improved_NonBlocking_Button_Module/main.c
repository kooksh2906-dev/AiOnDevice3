#include "main.h"
#include "gpio.h"

#include "button.h"

#define BUTTON_DEBOUNCE_MS (20U)

void SystemClock_Config(void);

int main(void)
{
    BUTTON_CONTROL user_button;

    HAL_Init();
    SystemClock_Config();
    MX_GPIO_Init();

    buttonInit(&user_button,
               GPIOC,
               GPIO_PIN_13,
               GPIO_PIN_SET,
               BUTTON_DEBOUNCE_MS);

    while (1)
    {
        buttonUpdate(&user_button);

        /* 한 번의 안정된 Press Event마다 Board LED를 한 번 Toggle합니다. */
        if (buttonWasPressed(&user_button))
        {
            HAL_GPIO_TogglePin(GPIOA, GPIO_PIN_5);
        }

        /* 이 Loop에는 UART, Sensor 등 다른 Non-Blocking 작업을 추가할 수 있습니다. */
    }
}
