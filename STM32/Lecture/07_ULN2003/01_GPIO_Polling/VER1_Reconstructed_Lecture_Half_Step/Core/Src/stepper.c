#include "stepper.h"

/* 1상과 2상 통전을 번갈아 사용하는 1-2상 여자(Half-step) 시퀀스입니다. */
static const uint8_t HALF_STEP_SEQ[8][4] = {
  {1U, 0U, 0U, 0U},
  {1U, 1U, 0U, 0U},
  {0U, 1U, 0U, 0U},
  {0U, 1U, 1U, 0U},
  {0U, 0U, 1U, 0U},
  {0U, 0U, 1U, 1U},
  {0U, 0U, 0U, 1U},
  {1U, 0U, 0U, 1U}
};

void stepMotor(uint8_t step)
{
  HAL_GPIO_WritePin(IN1_GPIO_PORT, IN1_GPIO_PIN,
                    (GPIO_PinState)HALF_STEP_SEQ[step][0]);
  HAL_GPIO_WritePin(IN2_GPIO_PORT, IN2_GPIO_PIN,
                    (GPIO_PinState)HALF_STEP_SEQ[step][1]);
  HAL_GPIO_WritePin(IN3_GPIO_PORT, IN3_GPIO_PIN,
                    (GPIO_PinState)HALF_STEP_SEQ[step][2]);
  HAL_GPIO_WritePin(IN4_GPIO_PORT, IN4_GPIO_PIN,
                    (GPIO_PinState)HALF_STEP_SEQ[step][3]);
}

void rotateSteps(uint16_t steps, uint8_t direction)
{
  for (uint16_t i = 0U; i < steps; i++)
  {
    uint8_t step;

    if (direction == DIR_CW)
    {
      step = (uint8_t)(i % 8U);
    }
    else
    {
      step = (uint8_t)(7U - (i % 8U));
    }

    stepMotor(step);
    HAL_Delay(1U);
  }
}

void rotateDegrees(uint16_t degrees, uint8_t direction)
{
  uint16_t steps = (uint16_t)(((uint32_t)degrees * STEPS_FER_REVOLUTION) / 360U);

  rotateSteps(steps, direction);
}
