#ifndef INC_MOTOR_TASK_H_
#define INC_MOTOR_TASK_H_

#include <stdint.h>
#include "cmsis_os2.h"
#include "motor_control.h"

#ifdef __cplusplus
extern "C" {
#endif

/* 큐는 freertos.c에서 생성하고 Motor_Task가 소비합니다.
 * 즉시 정지 명령은 큐가 가득 차도 전달되도록 별도 요청 플래그를 사용합니다. */
typedef enum {
    MOTOR_SOURCE_USER = 0,
    MOTOR_SOURCE_AUTO = 1
} MotorSource;

typedef struct {
    uint8_t source;
    uint8_t user_command;
    MotorControlState motion;
    uint16_t generation;
} MotorMessage;

osStatus_t MotorTask_SubmitUserCommand(uint8_t command);
osStatus_t MotorTask_QueueAutoMotion(MotorAction action,
                                     uint16_t left_pwm,
                                     uint16_t right_pwm);
uint8_t MotorTask_IsAutoMode(void);
uint16_t MotorTask_GetSpeed(void);
void MotorTask_GetState(MotorControlState *out_state);

#ifdef __cplusplus
}
#endif

#endif /* INC_MOTOR_TASK_H_ */
