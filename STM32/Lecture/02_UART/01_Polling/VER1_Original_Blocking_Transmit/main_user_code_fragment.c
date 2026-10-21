#include "main.h"
#include "usart.h"

/* 수업 원본의 USER CODE 조각을 함수 형태로 보존했습니다. */
void uartPollingTransmitExample(void)
{
    uint8_t txData[] = "hello stm!!\r\n";

    while (1)
    {
        /* Polling 송신: 완료 또는 100 ms Timeout까지 현재 흐름이 대기합니다. */
        HAL_UART_Transmit(&huart2, txData, sizeof(txData), 100U);
        HAL_Delay(1000U);
    }
}
