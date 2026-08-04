#ifndef INC_UART_LOG_H_
#define INC_UART_LOG_H_

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>
#include "stm32f1xx_hal.h"

HAL_StatusTypeDef UartLog_Init(void);
void UartLog_Transmit(const uint8_t *data, uint16_t length);

#ifdef __cplusplus
}
#endif

#endif /* INC_UART_LOG_H_ */
