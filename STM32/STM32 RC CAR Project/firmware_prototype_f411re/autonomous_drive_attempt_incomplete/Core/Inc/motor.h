#ifndef INC_MOTOR_H_
#define INC_MOTOR_H_

#include "main.h"

void Motor_Init(void);
void Motor_Stop(void);
void Motor_Straight(uint16_t pwm);
void Motor_Backward(uint16_t pwm);
void Motor_Turn_Left_Spot(uint16_t pwm);
void Motor_Turn_Right_Spot(uint16_t pwm);
void Motor_Steer(uint16_t left_pwm, uint16_t right_pwm);

#endif /* INC_MOTOR_H_ */
