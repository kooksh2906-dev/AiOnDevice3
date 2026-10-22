#include "stepper.h"

#define STEPPER_TIMER_TICK_HZ 1000000U

#define IN1_PORT GPIOB
#define IN1_PIN  GPIO_PIN_1
#define IN2_PORT GPIOB
#define IN2_PIN  GPIO_PIN_15
#define IN3_PORT GPIOB
#define IN3_PIN  GPIO_PIN_14
#define IN4_PORT GPIOB
#define IN4_PIN  GPIO_PIN_13

static const uint8_t waveSequence[4][4] = {
  {1U, 0U, 0U, 0U}, {0U, 1U, 0U, 0U},
  {0U, 0U, 1U, 0U}, {0U, 0U, 0U, 1U}
};

static const uint8_t fullSequence[4][4] = {
  {1U, 1U, 0U, 0U}, {0U, 1U, 1U, 0U},
  {0U, 0U, 1U, 1U}, {1U, 0U, 0U, 1U}
};

static const uint8_t halfSequence[8][4] = {
  {1U, 0U, 0U, 0U}, {1U, 1U, 0U, 0U},
  {0U, 1U, 0U, 0U}, {0U, 1U, 1U, 0U},
  {0U, 0U, 1U, 0U}, {0U, 0U, 1U, 1U},
  {0U, 0U, 0U, 1U}, {1U, 0U, 0U, 1U}
};

static uint8_t Stepper_GetSequenceLength(StepperDriveMode driveMode)
{
  return (driveMode == STEPPER_DRIVE_HALF) ? 8U : 4U;
}

static const uint8_t (*Stepper_GetSequence(StepperDriveMode driveMode))[4]
{
  if (driveMode == STEPPER_DRIVE_WAVE)
  {
    return waveSequence;
  }
  if (driveMode == STEPPER_DRIVE_FULL)
  {
    return fullSequence;
  }
  return halfSequence;
}

static void Stepper_WritePhase(StepperDriveMode driveMode, uint8_t step)
{
  const uint8_t (*sequence)[4] = Stepper_GetSequence(driveMode);

  HAL_GPIO_WritePin(IN1_PORT, IN1_PIN, (GPIO_PinState)sequence[step][0]);
  HAL_GPIO_WritePin(IN2_PORT, IN2_PIN, (GPIO_PinState)sequence[step][1]);
  HAL_GPIO_WritePin(IN3_PORT, IN3_PIN, (GPIO_PinState)sequence[step][2]);
  HAL_GPIO_WritePin(IN4_PORT, IN4_PIN, (GPIO_PinState)sequence[step][3]);
}

void Stepper_Init(Stepper_HandleTypeDef *stepper,
                  TIM_HandleTypeDef *timer,
                  StepperDriveMode driveMode,
                  uint16_t stepsPerRevolution)
{
  if ((stepper == NULL) || (timer == NULL))
  {
    return;
  }

  stepper->timer = timer;
  stepper->driveMode = driveMode;
  stepper->direction = STEPPER_DIR_CW;
  stepper->stepsPerRevolution = stepsPerRevolution;
  stepper->remainingSteps = 0U;
  stepper->currentStep = 0U;
  stepper->busy = 0U;

  Stepper_Release(stepper);
}

HAL_StatusTypeDef Stepper_SetStepFrequency(Stepper_HandleTypeDef *stepper,
                                           uint32_t frequencyHz)
{
  uint32_t counterCounts;

  if ((stepper == NULL) || (stepper->timer == NULL) ||
      (frequencyHz == 0U) || (frequencyHz > STEPPER_TIMER_TICK_HZ))
  {
    return HAL_ERROR;
  }

  counterCounts = STEPPER_TIMER_TICK_HZ / frequencyHz;

  /* TIM10은 16-bit Timer이므로 ARR+1이 1~65536 Count 범위여야 합니다. */
  if ((counterCounts == 0U) || (counterCounts > 65536U))
  {
    return HAL_ERROR;
  }

  __HAL_TIM_SET_AUTORELOAD(stepper->timer, counterCounts - 1U);
  __HAL_TIM_SET_COUNTER(stepper->timer, 0U);
  __HAL_TIM_GENERATE_EVENT(stepper->timer, TIM_EVENTSOURCE_UPDATE);
  __HAL_TIM_CLEAR_FLAG(stepper->timer, TIM_FLAG_UPDATE);

  return HAL_OK;
}

HAL_StatusTypeDef Stepper_RotateSteps(Stepper_HandleTypeDef *stepper,
                                      uint32_t steps,
                                      StepperDirection direction)
{
  uint8_t sequenceLength;

  if ((stepper == NULL) || (stepper->timer == NULL) ||
      (steps == 0U) || (stepper->busy != 0U))
  {
    return HAL_ERROR;
  }

  sequenceLength = Stepper_GetSequenceLength(stepper->driveMode);
  stepper->direction = direction;
  stepper->remainingSteps = steps;
  stepper->currentStep = (direction == STEPPER_DIR_CW) ? 0U
                                                       : (uint8_t)(sequenceLength - 1U);
  stepper->busy = 1U;

  __HAL_TIM_SET_COUNTER(stepper->timer, 0U);
  __HAL_TIM_CLEAR_FLAG(stepper->timer, TIM_FLAG_UPDATE);

  if (HAL_TIM_Base_Start_IT(stepper->timer) != HAL_OK)
  {
    stepper->busy = 0U;
    stepper->remainingSteps = 0U;
    return HAL_ERROR;
  }

  return HAL_OK;
}

HAL_StatusTypeDef Stepper_RotateDegrees(Stepper_HandleTypeDef *stepper,
                                        uint16_t degrees,
                                        StepperDirection direction)
{
  uint32_t steps;

  if ((stepper == NULL) || (stepper->stepsPerRevolution == 0U) ||
      (degrees == 0U))
  {
    return HAL_ERROR;
  }

  /* +180은 정수 나눗셈에서 가장 가까운 Step으로 반올림하기 위한 값입니다. */
  steps = (((uint32_t)degrees * stepper->stepsPerRevolution) + 180U) / 360U;
  if (steps == 0U)
  {
    steps = 1U;
  }

  return Stepper_RotateSteps(stepper, steps, direction);
}

void Stepper_OnTimerElapsed(Stepper_HandleTypeDef *stepper,
                            TIM_HandleTypeDef *htim)
{
  uint8_t sequenceLength;

  if ((stepper == NULL) || (htim == NULL) ||
      (stepper->timer != htim) || (stepper->busy == 0U))
  {
    return;
  }

  Stepper_WritePhase(stepper->driveMode, stepper->currentStep);
  stepper->remainingSteps--;

  if (stepper->remainingSteps == 0U)
  {
    /* 마지막 상은 유지하여 정지 토크를 보존합니다. */
    Stepper_Stop(stepper);
    return;
  }

  sequenceLength = Stepper_GetSequenceLength(stepper->driveMode);
  if (stepper->direction == STEPPER_DIR_CW)
  {
    stepper->currentStep = (uint8_t)((stepper->currentStep + 1U) % sequenceLength);
  }
  else
  {
    stepper->currentStep = (stepper->currentStep == 0U)
                         ? (uint8_t)(sequenceLength - 1U)
                         : (uint8_t)(stepper->currentStep - 1U);
  }
}

void Stepper_Stop(Stepper_HandleTypeDef *stepper)
{
  if ((stepper == NULL) || (stepper->timer == NULL))
  {
    return;
  }

  (void)HAL_TIM_Base_Stop_IT(stepper->timer);
  stepper->remainingSteps = 0U;
  stepper->busy = 0U;
}

void Stepper_Release(Stepper_HandleTypeDef *stepper)
{
  Stepper_Stop(stepper);

  HAL_GPIO_WritePin(IN1_PORT, IN1_PIN, GPIO_PIN_RESET);
  HAL_GPIO_WritePin(IN2_PORT, IN2_PIN, GPIO_PIN_RESET);
  HAL_GPIO_WritePin(IN3_PORT, IN3_PIN, GPIO_PIN_RESET);
  HAL_GPIO_WritePin(IN4_PORT, IN4_PIN, GPIO_PIN_RESET);
}

uint8_t Stepper_IsBusy(const Stepper_HandleTypeDef *stepper)
{
  return (stepper == NULL) ? 0U : stepper->busy;
}
