#include "main.h"
#include "usart.h"

static uint8_t rxData[10];

/*
 * 원본에는 Interrupt 호출과 함께 아래 DMA 전환 코드가 주석으로 남아 있었습니다.
 * 완성된 DMA 실행본으로 보지 않고 학습 당시 API 전환 흔적으로 보존합니다.
 */
void uartDmaOriginalApiTrace(void)
{
    HAL_UART_Receive_IT(&huart2, rxData, 4U);
    /* HAL_UART_Receive_DMA(&huart2, rxData, 4U); */
}
