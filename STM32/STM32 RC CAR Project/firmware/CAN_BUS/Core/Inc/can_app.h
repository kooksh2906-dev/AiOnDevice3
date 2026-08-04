#ifndef INC_CAN_APP_H_
#define INC_CAN_APP_H_

#ifdef __cplusplus
extern "C" {
#endif

#include "stm32f1xx_hal.h"
#include "can_protocol.h"

/* hcan is declared by the CubeMX-generated can.h/c module. */
typedef enum
{
    CAN_APP_FILTER_VEHICLE_STATUS = 0,
    CAN_APP_FILTER_ACCEPT_ALL
} CanAppFilterMode_t;

HAL_StatusTypeDef CAN_App_Init(void);
HAL_StatusTypeDef CAN_App_InitWithFilter(CanAppFilterMode_t filter_mode);
HAL_StatusTypeDef CAN_App_SendVehicleStatus(const CanVehicleStatus_t *status);
uint8_t CAN_App_GetLatestStatus(CanVehicleStatus_t *out_status);
uint32_t CAN_App_GetRxCount(void);
uint32_t CAN_App_GetTxErrorCount(void);
uint32_t CAN_App_GetLastRxTick(void);

#ifdef __cplusplus
}
#endif

#endif /* INC_CAN_APP_H_ */
