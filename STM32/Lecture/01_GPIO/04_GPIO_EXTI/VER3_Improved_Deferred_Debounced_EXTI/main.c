#include "main.h"
#include "gpio.h"

#include "button_exti.h"

void SystemClock_Config(void);

int main(void)
{
    HAL_Init();
    SystemClock_Config();
    MX_GPIO_Init();

    buttonExtiInit();

    while (1)
    {
        /* 실제 출력 제어는 Interrupt Context가 아닌 Main Context에서 수행합니다. */
        if (buttonExtiTakePressEvent())
        {
            HAL_GPIO_TogglePin(GPIOA, GPIO_PIN_5);
        }

        /* 여기에 UART, Sensor 등 다른 Main Loop 작업을 함께 배치할 수 있습니다. */
    }
}
