#ifndef INC_MANUAL_DRIVE_H_
#define INC_MANUAL_DRIVE_H_

#include <stdint.h>
#include "motor_control.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint8_t requested_direction;
    uint8_t active_direction;
    uint8_t throttle_pressed;
    uint16_t pwm;
    uint32_t last_accel_tick;
    uint32_t last_decel_tick;
} ManualDriveState;

typedef struct {
    uint8_t valid;
    MotorControlState motion;
} ManualDriveOutput;

void ManualDrive_Init(ManualDriveState *state, uint32_t now);
void ManualDrive_Reset(ManualDriveState *state, uint32_t now);
ManualDriveOutput ManualDrive_HandleCommand(ManualDriveState *state,
                                            uint8_t command,
                                            uint16_t turn_speed,
                                            uint32_t now);
ManualDriveOutput ManualDrive_Update(ManualDriveState *state, uint32_t now);

#ifdef __cplusplus
}
#endif

#endif /* INC_MANUAL_DRIVE_H_ */
