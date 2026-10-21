#include "main.h"
#include "usart.h"

static uint8_t rxData;
static volatile uint8_t rxEvent;

void uartDeferredEchoStart(void)
{
    rxEvent = 0U;
    HAL_UART_Receive_IT(&huart2, &rxData, sizeof(rxData));
}

void HAL_UART_RxCpltCallback(UART_HandleTypeDef *huart)
{
    if (huart->Instance == USART2)
    {
        /* ISR에서는 완료 Event만 기록하고 Blocking 송신을 수행하지 않습니다. */
        rxEvent = 1U;
    }
}

/* Main Loop에서 반복 호출합니다. */
void uartDeferredEchoProcess(void)
{
    if (rxEvent != 0U)
    {
        rxEvent = 0U;
        (void)HAL_UART_Transmit(&huart2, &rxData, sizeof(rxData), 100U);
        HAL_UART_Receive_IT(&huart2, &rxData, sizeof(rxData));
    }
}
