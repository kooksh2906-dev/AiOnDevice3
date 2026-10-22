#ifndef INC_STEPPER_H_
#define INC_STEPPER_H_

#include "main.h"

#define STEPPER_UNITS 1U

#define WAVE_STEP_DRIVE 0U
#define FULL_STEP_DRIVE 1U
#define HALF_STEP_DRIVE 2U

#define DIR_CW  0U
#define DIR_CCW 1U

#define WAVE_RESOLUTION  2048U
#define DRIVE_RESOLUTION 4096U

#define IN1_PIN  GPIO_PIN_1
#define IN1_PORT GPIOB
#define IN2_PIN  GPIO_PIN_15
#define IN2_PORT GPIOB
#define IN3_PIN  GPIO_PIN_14
#define IN3_PORT GPIOB
#define IN4_PIN  GPIO_PIN_13
#define IN4_PORT GPIOB

/* 강사님 참고 자료에 함께 제시된 세 가지 여자 시퀀스를 보존합니다. */
static const uint8_t WAVE_STEP_SEQ[4][4] = {
  {1U, 0U, 0U, 0U}, {0U, 1U, 0U, 0U},
  {0U, 0U, 1U, 0U}, {0U, 0U, 0U, 1U}
};

static const uint8_t FULL_STEP_SEQ[4][4] = {
  {1U, 1U, 0U, 0U}, {0U, 1U, 1U, 0U},
  {0U, 0U, 1U, 1U}, {1U, 0U, 0U, 1U}
};

static const uint8_t HALF_STEP_SEQ[8][4] = {
  {1U, 0U, 0U, 0U}, {1U, 1U, 0U, 0U},
  {0U, 1U, 0U, 0U}, {0U, 1U, 1U, 0U},
  {0U, 0U, 1U, 0U}, {0U, 0U, 1U, 1U},
  {0U, 0U, 0U, 1U}, {1U, 0U, 0U, 1U}
};

void stepperSpeed(TIM_HandleTypeDef *htim, uint8_t speedLevel);
void setMotorDirection(uint8_t direction);
void rotateDegrees(uint16_t degrees,
                   uint8_t direction,
                   uint8_t speedLevel,
                   TIM_HandleTypeDef *htim);

#endif /* INC_STEPPER_H_ */
