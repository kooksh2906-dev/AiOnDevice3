#ifndef INC_MOTOR_CONTROL_H_
#define INC_MOTOR_CONTROL_H_

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* 모터 GPIO/PWM 구동 계층: RTOS 큐와 주행 모드는 여기서 관리하지 않습니다. */
typedef enum {
    MOTOR_ACTION_STOP = 0,
    MOTOR_ACTION_FORWARD,
    MOTOR_ACTION_BACKWARD,
    MOTOR_ACTION_TURN_LEFT,
    MOTOR_ACTION_TURN_RIGHT
} MotorAction;

typedef struct {
    uint8_t action;
    uint16_t left_pwm;
    uint16_t right_pwm;
} MotorControlState;

void MotorControl_Start(void);
uint8_t MotorControl_Apply(const MotorControlState *motion);

#ifdef __cplusplus
}
#endif

#endif /* INC_MOTOR_CONTROL_H_ */
