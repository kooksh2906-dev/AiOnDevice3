/*
 * uart_cmd.c
 *
 *  Created on: 2026. 6. 8.
 *      Author: user
 */

#include "bluetooth.h"
#include "usart.h" // huart1 사용

// 사용자가 선언했던 원본 변수 그대로
volatile uint8_t rx_data;
volatile uint8_t rx_flag = RX_RESET;

// 사용자가 작성했던 인터럽트 콜백 코드 그대로
void HAL_UART_RxCpltCallback(UART_HandleTypeDef *huart) {
	if (huart->Instance == USART1) {

		HAL_GPIO_TogglePin(GPIOA, GPIO_PIN_5); // 블루투스 수신 확인
		rx_flag = RX_SET;
		HAL_UART_Receive_IT(&huart1, (uint8_t *)&rx_data, 1);
	}
}

void HAL_UART_ErrorCallback(UART_HandleTypeDef *huart)
{
	if (huart->Instance == USART1)
	{
		__HAL_UART_CLEAR_OREFLAG(huart);
		__HAL_UART_CLEAR_NEFLAG(huart);
		__HAL_UART_CLEAR_FEFLAG(huart);
		HAL_UART_Receive_IT(&huart1, (uint8_t*)&rx_data, 1);
	}
}
