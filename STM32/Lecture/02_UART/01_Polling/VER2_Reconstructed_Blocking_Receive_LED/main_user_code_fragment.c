#include "main.h"
#include "usart.h"
#include "gpio.h"

static uint8_t rxData[10];

/*
 * 원본 강의 화면과 주석을 결합한 Polling 비교용 복원본입니다.
 * 실제 수업의 독립된 전체 main.c 원본으로 표기하지 않습니다.
 */
void uartPollingReceiveLedExample(void)
{
    while (1)
    {
        /* 4바이트를 모두 받거나 1000 ms Timeout이 발생할 때까지 Blocking됩니다. */
        (void)HAL_UART_Receive(&huart2, rxData, 4U, 1000U);

        /* UART 대기 시간만큼 이 LED 처리도 늦어집니다. */
        HAL_GPIO_TogglePin(GPIOA, GPIO_PIN_5);
        HAL_Delay(200U);
    }
}
