#include "bluetooth_control.h"

#include "cmsis_os2.h"
#include "motor_control.h"
#include "usart.h"

#define BT_RX_BUFFER_SIZE 16U

uint8_t rxData = 0U;

static volatile uint8_t bt_rx_buffer[BT_RX_BUFFER_SIZE];
static volatile uint8_t bt_rx_head = 0U;
static volatile uint8_t bt_rx_tail = 0U;

volatile uint32_t bt_rx_count = 0U;
volatile uint32_t bt_rx_overflow_count = 0U;
volatile uint32_t bt_uart_error_count = 0U;
volatile uint8_t last_bt_rx = 0U;
volatile uint32_t last_bt_rx_tick = 0U;

volatile uint32_t bt_pop_count = 0U;
volatile uint32_t bt_queue_put_count = 0U;
volatile uint32_t bt_queue_put_fail_count = 0U;

static void BtRxPushFromIsr(uint8_t data);

HAL_StatusTypeDef BluetoothControl_Init(void)
{
    return HAL_UART_Receive_IT(&huart3, &rxData, 1U);
}

uint8_t BluetoothControl_PopCommand(uint8_t *out_command)
{
    uint8_t data;
    uint32_t primask;

    if (out_command == NULL) {
        return 0U;
    }

    primask = __get_PRIMASK();
    __disable_irq();

    if (bt_rx_head == bt_rx_tail) {
        if (primask == 0U) {
            __enable_irq();
        }
        return 0U;
    }

    data = bt_rx_buffer[bt_rx_tail];
    bt_rx_tail = (uint8_t)((bt_rx_tail + 1U) % BT_RX_BUFFER_SIZE);

    if (primask == 0U) {
        __enable_irq();
    }

    *out_command = data;
    return 1U;
}

void BluetoothControl_Task(void *argument)
{
    (void)argument;

    /* Bluetooth USART3 interrupt reception starts after the scheduler. */
    (void)BluetoothControl_Init();

    for (;;) {
        uint8_t cmd;

        while (BluetoothControl_PopCommand(&cmd) != 0U) {
            osStatus_t status;

            bt_pop_count++;
            status = MotorControl_QueueUserCommand(cmd);

            if (status == osOK) {
                bt_queue_put_count++;
            } else {
                bt_queue_put_fail_count++;
            }
        }

        osDelay(1U);
    }
}

static void BtRxPushFromIsr(uint8_t data)
{
    uint8_t next_head = (uint8_t)((bt_rx_head + 1U) % BT_RX_BUFFER_SIZE);

    if (next_head == bt_rx_tail) {
        bt_rx_overflow_count++;
        return;
    }

    bt_rx_buffer[bt_rx_head] = data;
    bt_rx_head = next_head;
    bt_rx_count++;
    last_bt_rx = data;
    last_bt_rx_tick = HAL_GetTick();
}

void HAL_UART_RxCpltCallback(UART_HandleTypeDef *huart)
{
    if (huart->Instance == USART3) {
        BtRxPushFromIsr(rxData);
        (void)HAL_UART_Receive_IT(huart, &rxData, 1U);
    }
}

void HAL_UART_ErrorCallback(UART_HandleTypeDef *huart)
{
    if (huart->Instance == USART3) {
        bt_uart_error_count++;

        if (__HAL_UART_GET_FLAG(huart, UART_FLAG_ORE)) {
            __HAL_UART_CLEAR_OREFLAG(huart);
        }
        (void)HAL_UART_Receive_IT(huart, &rxData, 1U);
    }
}
