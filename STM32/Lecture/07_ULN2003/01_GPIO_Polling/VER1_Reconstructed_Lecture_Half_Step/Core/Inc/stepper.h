#ifndef INC_STEPPER_H_
#define INC_STEPPER_H_

#include "main.h"

/* 수업 코드의 이름을 그대로 보존합니다(FER는 원문 표기입니다). */
#define STEPS_FER_REVOLUTION 4096U

#define DIR_CW  0U
#define DIR_CCW 1U

#define IN1_GPIO_PORT GPIOB
#define IN1_GPIO_PIN  GPIO_PIN_1
#define IN2_GPIO_PORT GPIOB
#define IN2_GPIO_PIN  GPIO_PIN_15
#define IN3_GPIO_PORT GPIOB
#define IN3_GPIO_PIN  GPIO_PIN_14
#define IN4_GPIO_PORT GPIOB
#define IN4_GPIO_PIN  GPIO_PIN_13

void stepMotor(uint8_t step);
void rotateSteps(uint16_t steps, uint8_t direction);
void rotateDegrees(uint16_t degrees, uint8_t direction);

#endif /* INC_STEPPER_H_ */
