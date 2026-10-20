/*
 * Corrected original learning logic.
 * lastTick is updated when each LED changes state.
 */

#include "main.h"
#include "gpio.h"
#include "usart.h"

typedef enum
{
    LED_OFF,
    LED_ON
} LED_STATE;

typedef struct
{
    GPIO_TypeDef *port;
    uint16_t number;
    uint32_t interval;
    LED_STATE state;
    uint32_t lastTick;
} LED_CONTROL;

void SystemClock_Config(void);

void updateLed(LED_CONTROL *led)
{
    uint32_t currTick = HAL_GetTick();

    if (currTick - led->lastTick >= led->interval)
    {
        /* 다음 실행 주기를 현재 상태 변경 시점부터 다시 측정합니다. */
        led->lastTick = currTick;

        if (led->state == LED_OFF)
        {
            HAL_GPIO_WritePin(led->port, led->number, 1);
            led->state = LED_ON;
        }
        else
        {
            HAL_GPIO_WritePin(led->port, led->number, 0);
            led->state = LED_OFF;
        }
    }
}

int main(void)
{
    HAL_Init();
    SystemClock_Config();
    MX_GPIO_Init();
    MX_USART2_UART_Init();

    LED_CONTROL led1 = {GPIOA, GPIO_PIN_5, 500U, LED_OFF, 0U};
    LED_CONTROL led2 = {GPIOA, GPIO_PIN_6, 1000U, LED_OFF, 0U};

    while (1)
    {
        updateLed(&led1);
        updateLed(&led2);
    }
}

