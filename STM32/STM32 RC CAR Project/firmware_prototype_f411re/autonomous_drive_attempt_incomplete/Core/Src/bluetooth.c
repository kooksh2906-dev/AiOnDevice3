#include "bluetooth.h"
#include "usart.h"

volatile uint8_t rx_data = 0;
volatile uint8_t bt_cmd = 'S';
volatile uint8_t auto_mode = 0;

void Bluetooth_Init(void) {
    HAL_UART_Receive_IT(&huart3, (uint8_t *)&rx_data, 1);
}

void HAL_UART_RxCpltCallback(UART_HandleTypeDef *huart) {
    if (huart->Instance == USART3) {
        bt_cmd = rx_data;
        HAL_UART_Receive_IT(&huart3, (uint8_t *)&rx_data, 1);
    }
}
