/*
 * motor.h
 *
 *  Created on: 2026. 6. 4.
 *      Author: user
 */

#ifndef INC_MOTOR_H_
#define INC_MOTOR_H_

#include "main.h"

#define PORT_L298N GPIOB
#define PIN_IN1    GPIO_PIN_1   // 우측 전진
#define PIN_IN2    GPIO_PIN_15  // 우측 후진
#define PIN_IN3    GPIO_PIN_14  // 좌측 전진
#define PIN_IN4    GPIO_PIN_13  // 좌측 후진

void motor_forward(void);
void motor_backward(void);
void motor_left(void);
void motor_right(void);
void motor_stop(void);
void motor_speed_up(void);
void motor_speed_down(void);

#endif /* INC_MOTOR_H_ */
