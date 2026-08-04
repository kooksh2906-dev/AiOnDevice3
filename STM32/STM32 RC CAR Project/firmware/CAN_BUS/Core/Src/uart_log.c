#include "uart_log.h"

#include "cmsis_os2.h"
#include "usart.h"

static osMutexId_t uartMutexHandle;

HAL_StatusTypeDef UartLog_Init(void)
{
    uartMutexHandle = osMutexNew(NULL);

    return (uartMutexHandle != NULL) ? HAL_OK : HAL_ERROR;
}

void UartLog_Transmit(const uint8_t *data, uint16_t length)
{
    if ((data == NULL) || (length == 0U)) {
        return;
    }

    if ((uartMutexHandle != NULL) &&
        (osMutexAcquire(uartMutexHandle, 30U) == osOK)) {
        (void)HAL_UART_Transmit(&huart2, data, length, 30U);
        (void)osMutexRelease(uartMutexHandle);
    }
}
