#ifndef INC_CAN_PROTOCOL_H_
#define INC_CAN_PROTOCOL_H_

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>

#define CAN_ID_VEHICLE_STATUS      0x101U
#define CAN_VEHICLE_STATUS_DLC     4U

typedef enum
{
    CAN_DIR_STOP = 0,
    CAN_DIR_FORWARD = 1,
    CAN_DIR_LEFT = 2,
    CAN_DIR_RIGHT = 3,
    CAN_DIR_BACK = 4,
    CAN_DIR_AVOID = 5
} CanDirection_t;

typedef struct
{
    uint8_t speed_percent;
    CanDirection_t direction;
    uint8_t front_distance;
    uint8_t alive_count;
} CanVehicleStatus_t;

static inline void CAN_EncodeVehicleStatus(uint8_t data[8],
                                           const CanVehicleStatus_t *status)
{
    uint8_t speed = status->speed_percent;

    if (speed > 100U) {
        speed = 100U;
    }

    data[0] = speed;
    data[1] = (uint8_t)status->direction;
    data[2] = status->front_distance;
    data[3] = status->alive_count;
    data[4] = 0U;
    data[5] = 0U;
    data[6] = 0U;
    data[7] = 0U;
}

static inline void CAN_DecodeVehicleStatus(const uint8_t data[8],
                                           CanVehicleStatus_t *status)
{
    status->speed_percent = (data[0] <= 100U) ? data[0] : 100U;
    status->direction = (CanDirection_t)data[1];
    status->front_distance = data[2];
    status->alive_count = data[3];
}

#ifdef __cplusplus
}
#endif

#endif /* INC_CAN_PROTOCOL_H_ */
