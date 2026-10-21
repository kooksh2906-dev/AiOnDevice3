#include "main.h"
#include "usart.h"

static uint8_t rxData[10];

/* MX_USART2_UART_Init() 이후 USER CODE BEGIN 2에서 호출한 원본 흐름입니다. */
void uartInterruptReceiveStart(void)
{
    HAL_UART_Receive_IT(&huart2, rxData, 4U);
}

/*
 * 4바이트 수신 완료 후 호출되며 다음 4바이트 수신을 다시 등록합니다.
 * 원본은 huart 인자를 확인하지 않았다는 점까지 그대로 보존했습니다.
 */
void HAL_UART_RxCpltCallback(UART_HandleTypeDef *huart)
{
    (void)huart;
    HAL_UART_Receive_IT(&huart2, rxData, 4U);
}
