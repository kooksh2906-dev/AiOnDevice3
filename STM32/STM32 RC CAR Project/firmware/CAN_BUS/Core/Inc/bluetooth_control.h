#ifndef INC_BLUETOOTH_CONTROL_H_
#define INC_BLUETOOTH_CONTROL_H_

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>
#include "stm32f1xx_hal.h"

HAL_StatusTypeDef BluetoothControl_Init(void);
uint8_t BluetoothControl_PopCommand(uint8_t *out_command);
void BluetoothControl_Task(void *argument);

#ifdef __cplusplus
}
#endif

#endif /* INC_BLUETOOTH_CONTROL_H_ */
