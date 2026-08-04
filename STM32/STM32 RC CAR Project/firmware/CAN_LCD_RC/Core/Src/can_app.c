#include "can_app.h"
#include "can.h"

static volatile CanVehicleStatus_t latest_status;
static volatile uint8_t latest_status_valid;
static volatile uint32_t rx_count;
static volatile uint32_t tx_error_count;
static volatile uint32_t last_rx_tick;
static uint8_t tx_alive_count;
static uint8_t can_initialized;

HAL_StatusTypeDef CAN_App_Init(void)
{
    /* Production default: accept only the 0x101 vehicle-status data frame. */
    return CAN_App_InitWithFilter(CAN_APP_FILTER_VEHICLE_STATUS);
}

HAL_StatusTypeDef CAN_App_InitWithFilter(CanAppFilterMode_t filter_mode)
{
    CAN_FilterTypeDef filter = {0};
    HAL_StatusTypeDef result;

    can_initialized = 0U;

    filter.FilterBank = 0U;
    filter.FilterMode = CAN_FILTERMODE_IDMASK;
    filter.FilterScale = CAN_FILTERSCALE_32BIT;
    filter.FilterFIFOAssignment = CAN_RX_FIFO0;
    filter.FilterActivation = ENABLE;
    filter.SlaveStartFilterBank = 14U;

    if (filter_mode == CAN_APP_FILTER_ACCEPT_ALL) {
        /* Initial bus test: a zero ID with a zero mask accepts every frame. */
        filter.FilterIdHigh = 0U;
        filter.FilterIdLow = 0U;
        filter.FilterMaskIdHigh = 0U;
        filter.FilterMaskIdLow = 0U;
    } else {
        /*
         * Final filter: in bxCAN 32-bit layout the 11-bit standard ID starts
         * at bit 5. 0xFFE0 compares all ID bits; low mask bits 2 and 1 require
         * IDE=0 and RTR=0, so only the 0x101 standard data frame is accepted.
         */
        filter.FilterIdHigh = (uint16_t)(CAN_ID_VEHICLE_STATUS << 5U);
        filter.FilterIdLow = 0U;
        filter.FilterMaskIdHigh = 0xFFE0U;
        filter.FilterMaskIdLow = 0x0006U;
    }

    result = HAL_CAN_ConfigFilter(&hcan, &filter);
    if (result != HAL_OK) {
        return result;
    }

    result = HAL_CAN_Start(&hcan);
    if (result != HAL_OK) {
        return result;
    }

    result = HAL_CAN_ActivateNotification(&hcan,
                                           CAN_IT_RX_FIFO0_MSG_PENDING);
    if (result == HAL_OK) {
        can_initialized = 1U;
    }
    return result;
}

HAL_StatusTypeDef CAN_App_SendVehicleStatus(const CanVehicleStatus_t *status)
{
    CAN_TxHeaderTypeDef header = {0};
    CanVehicleStatus_t frame_status;
    uint8_t data[8] = {0};
    uint32_t mailbox;
    HAL_StatusTypeDef result;

    if ((status == NULL) || (can_initialized == 0U)) {
        tx_error_count++;
        return HAL_ERROR;
    }

    /* Never block the autonomous-driving task when all three mailboxes are in use. */
    if (HAL_CAN_GetTxMailboxesFreeLevel(&hcan) == 0U) {
        tx_error_count++;
        return HAL_BUSY;
    }

    frame_status = *status;
    frame_status.alive_count = tx_alive_count;
    CAN_EncodeVehicleStatus(data, &frame_status);

    header.StdId = CAN_ID_VEHICLE_STATUS;
    header.ExtId = 0U;
    header.IDE = CAN_ID_STD;
    header.RTR = CAN_RTR_DATA;
    header.DLC = CAN_VEHICLE_STATUS_DLC;
    header.TransmitGlobalTime = DISABLE;

    result = HAL_CAN_AddTxMessage(&hcan, &header, data, &mailbox);
    if (result == HAL_OK) {
        tx_alive_count++;
    } else {
        tx_error_count++;
    }

    return result;
}

uint8_t CAN_App_GetLatestStatus(CanVehicleStatus_t *out_status)
{
    uint32_t primask;

    if (out_status == NULL) {
        return 0U;
    }

    primask = __get_PRIMASK();
    __disable_irq();

    if (latest_status_valid == 0U) {
        if (primask == 0U) {
            __enable_irq();
        }
        return 0U;
    }

    out_status->speed_percent = latest_status.speed_percent;
    out_status->direction = latest_status.direction;
    out_status->front_distance = latest_status.front_distance;
    out_status->alive_count = latest_status.alive_count;

    if (primask == 0U) {
        __enable_irq();
    }
    return 1U;
}

uint32_t CAN_App_GetRxCount(void)
{
    return rx_count;
}

uint32_t CAN_App_GetTxErrorCount(void)
{
    return tx_error_count;
}

uint32_t CAN_App_GetLastRxTick(void)
{
    return last_rx_tick;
}

void HAL_CAN_RxFifo0MsgPendingCallback(CAN_HandleTypeDef *can_handle)
{
    CAN_RxHeaderTypeDef header;
    CanVehicleStatus_t decoded;
    uint8_t data[8];

    if ((can_handle == NULL) || (can_handle->Instance != CAN1)) {
        return;
    }

    if (HAL_CAN_GetRxMessage(can_handle, CAN_RX_FIFO0, &header, data) != HAL_OK) {
        return;
    }

    /* Counts every frame passed by the active hardware filter. */
    rx_count++;

    if ((header.IDE == CAN_ID_STD) &&
        (header.RTR == CAN_RTR_DATA) &&
        (header.StdId == CAN_ID_VEHICLE_STATUS) &&
        (header.DLC == CAN_VEHICLE_STATUS_DLC)) {
        CAN_DecodeVehicleStatus(data, &decoded);

        latest_status.speed_percent = decoded.speed_percent;
        latest_status.direction = decoded.direction;
        latest_status.front_distance = decoded.front_distance;
        latest_status.alive_count = decoded.alive_count;
        last_rx_tick = HAL_GetTick();
        latest_status_valid = 1U;
    }
}
