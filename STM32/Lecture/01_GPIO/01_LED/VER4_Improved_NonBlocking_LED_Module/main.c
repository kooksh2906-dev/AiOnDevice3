#include "main.h"
#include "gpio.h"

#include "led_control.h"

void SystemClock_Config(void);

int main(void)
{
    LED_CONTROL board_led;
    LED_CONTROL external_led;

    HAL_Init();
    SystemClock_Config();
    MX_GPIO_Init();

    ledControlInit(&board_led,
                   GPIOA,
                   GPIO_PIN_5,
                   500U,
                   GPIO_PIN_RESET);
    ledControlInit(&external_led,
                   GPIOA,
                   GPIO_PIN_6,
                   1000U,
                   GPIO_PIN_RESET);

    while (1)
    {
        /* 각 LED는 서로의 대기 시간에 영향을 주지 않고 독립적으로 갱신됩니다. */
        ledControlUpdate(&board_led);
        ledControlUpdate(&external_led);

        /* 여기에 Switch, UART 등 다른 Non-Blocking 작업을 함께 호출할 수 있습니다. */
    }
}

