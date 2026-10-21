#include "main.h"
#include "usart.h"

static uint8_t rxData;

void uartInterruptEchoStart(void)
{
    HAL_UART_Receive_IT(&huart2, &rxData, sizeof(rxData));
}

void HAL_UART_RxCpltCallback(UART_HandleTypeDef *huart)
{
    /* 여러 UART가 Callback을 공유하므로 발생 Instance를 먼저 구분합니다. */
    if (huart->Instance == USART2)
    {
        /* 원본은 Callback 안에서 Blocking 송신으로 한 글자를 Echo했습니다. */
        HAL_UART_Transmit(&huart2, &rxData, sizeof(rxData), 100U);

        /* HAL의 고정 길이 Interrupt 수신은 완료 후 다시 등록해야 합니다. */
        HAL_UART_Receive_IT(&huart2, &rxData, sizeof(rxData));
    }
}
