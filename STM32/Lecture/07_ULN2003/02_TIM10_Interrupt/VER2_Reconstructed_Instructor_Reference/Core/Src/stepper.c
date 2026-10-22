#include "stepper.h"

static const uint16_t speedTable[] = {1000U, 800U, 600U, 400U, 200U};
#define SPEED_TABLE_SIZE (sizeof(speedTable) / sizeof(speedTable[0]))

static volatile uint8_t currentStep = 0U;
volatile uint8_t motorDirection = DIR_CW;
static volatile uint16_t remainingSteps = 0U;

void stepperSpeed(TIM_HandleTypeDef *htim, uint8_t speedLevel)
{
  if (htim->Instance == TIM10)
  {
    if (speedLevel >= SPEED_TABLE_SIZE)
    {
      return;
    }

    uint16_t frequency = speedTable[speedLevel];
    uint16_t arr = (uint16_t)((1000000U / frequency) - 1U);

    /* TIM10 입력 Clock 100 MHz를 1 MHz Counter Clock으로 분주합니다. */
    htim->Instance->PSC = 100U - 1U;
    htim->Instance->ARR = arr;
    __HAL_TIM_SET_COUNTER(htim, 0U);
  }
}

void setMotorDirection(uint8_t direction)
{
  motorDirection = direction;
}

void HAL_TIM_PeriodElapsedCallback(TIM_HandleTypeDef *htim)
{
  if (htim->Instance == TIM10)
  {
    if (remainingSteps > 0U)
    {
      if (motorDirection == DIR_CW)
      {
        currentStep = (uint8_t)((currentStep + 1U) % 8U);
      }
      else
      {
        currentStep = (currentStep == 0U) ? 7U : (uint8_t)(currentStep - 1U);
      }

      HAL_GPIO_WritePin(IN1_PORT, IN1_PIN,
                        (GPIO_PinState)HALF_STEP_SEQ[currentStep][0]);
      HAL_GPIO_WritePin(IN2_PORT, IN2_PIN,
                        (GPIO_PinState)HALF_STEP_SEQ[currentStep][1]);
      HAL_GPIO_WritePin(IN3_PORT, IN3_PIN,
                        (GPIO_PinState)HALF_STEP_SEQ[currentStep][2]);
      HAL_GPIO_WritePin(IN4_PORT, IN4_PIN,
                        (GPIO_PinState)HALF_STEP_SEQ[currentStep][3]);

      remainingSteps--;
    }
    else
    {
      HAL_TIM_Base_Stop_IT(htim);
    }
  }
}

void rotateDegrees(uint16_t degrees,
                   uint8_t direction,
                   uint8_t speedLevel,
                   TIM_HandleTypeDef *htim)
{
  uint16_t steps = (uint16_t)(((uint32_t)degrees * DRIVE_RESOLUTION) / 360U);

  remainingSteps = steps;
  stepperSpeed(htim, speedLevel);
  motorDirection = direction;
  HAL_TIM_Base_Start_IT(htim);
}
