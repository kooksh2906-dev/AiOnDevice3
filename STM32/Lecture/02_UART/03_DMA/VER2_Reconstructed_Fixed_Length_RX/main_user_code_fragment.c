#include "main.h"
#include "usart.h"

#define UART_DMA_RX_SIZE 4U

static uint8_t dmaRxData[UART_DMA_RX_SIZE];
static volatile uint8_t dmaRxComplete;

void uartDmaReceiveStart(void)
{
    dmaRxComplete = 0U;
    HAL_UART_Receive_DMA(&huart2, dmaRxData, UART_DMA_RX_SIZE);
}

void HAL_UART_RxCpltCallback(UART_HandleTypeDef *huart)
{
    if (huart->Instance == USART2)
    {
        /* DMA 전송 완료 Event만 Main Context로 전달합니다. */
        dmaRxComplete = 1U;
    }
}

/* Main Loop에서 반복 호출하고, 이 위치에 4바이트 처리 로직을 추가합니다. */
void uartDmaReceiveProcess(void)
{
    if (dmaRxComplete != 0U)
    {
        dmaRxComplete = 0U;

        /* processUartFrame(dmaRxData, UART_DMA_RX_SIZE); */

        /* 다음 고정 길이 Frame 수신을 다시 시작합니다. */
        HAL_UART_Receive_DMA(&huart2, dmaRxData, UART_DMA_RX_SIZE);
    }
}
