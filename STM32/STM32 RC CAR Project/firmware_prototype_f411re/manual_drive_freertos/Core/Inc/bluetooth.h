/*
 * uart_cmd.h
 *
 *  Created on: 2026. 6. 8.
 *      Author: user
 */

#ifndef INC_BLUETOOTH_H_
#define INC_BLUETOOTH_H_

#include "main.h"

typedef enum{
	RX_RESET,
	RX_SET
} RX_FLAG;

// main.c에서 사용할 수 있도록 extern 선언
extern volatile uint8_t rx_data;
extern volatile uint8_t rx_flag; // while loop 내에서 한 번만 실행하기 위한 플래그 추가

#endif /* INC_BLUETOOTH_H_ */
