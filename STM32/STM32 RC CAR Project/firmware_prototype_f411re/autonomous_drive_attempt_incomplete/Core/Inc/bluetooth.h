#ifndef INC_BLUETOOTH_H_
#define INC_BLUETOOTH_H_

#include "main.h"

void Bluetooth_Init(void);

extern volatile uint8_t rx_data;
extern volatile uint8_t bt_cmd;
extern volatile uint8_t auto_mode;

#endif /* INC_BLUETOOTH_H_ */
