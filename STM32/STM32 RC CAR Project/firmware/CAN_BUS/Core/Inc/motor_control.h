#ifndef INC_MOTOR_CONTROL_H_
#define INC_MOTOR_CONTROL_H_

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>
#include "cmsis_os2.h"

typedef enum {
    MOTOR_SOURCE_USER = 0,
    MOTOR_SOURCE_AUTO = 1
} MotorSource;

typedef enum {
    MOTOR_ACTION_STOP = 0,
    MOTOR_ACTION_FORWARD,
    MOTOR_ACTION_BACKWARD,
    MOTOR_ACTION_TURN_LEFT,
    MOTOR_ACTION_TURN_RIGHT
} MotorAction;

typedef struct {
    uint8_t source;
    uint8_t action;
    uint16_t left_pwm;
    uint16_t right_pwm;
} MotorMessage;

typedef struct {
    uint8_t action;
    uint16_t left_pwm;
    uint16_t right_pwm;
} MotorControlState;

void MotorControl_Init(osMessageQueueId_t motor_queue);
void MotorControl_Task(void *argument);
osStatus_t MotorControl_QueueUserCommand(uint8_t command);
void MotorControl_QueueAutoMotion(MotorAction action,
                                  uint16_t left_pwm,
                                  uint16_t right_pwm);
uint8_t MotorControl_IsAutoMode(void);
uint16_t MotorControl_GetSpeed(void);
void MotorControl_GetState(MotorControlState *out_state);

#ifdef __cplusplus
}
#endif

#endif /* INC_MOTOR_CONTROL_H_ */
