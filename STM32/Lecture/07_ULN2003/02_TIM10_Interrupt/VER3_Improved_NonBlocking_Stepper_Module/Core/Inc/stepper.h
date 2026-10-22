#ifndef INC_STEPPER_H_
#define INC_STEPPER_H_

#include "main.h"

typedef enum
{
  STEPPER_DRIVE_WAVE = 0,
  STEPPER_DRIVE_FULL,
  STEPPER_DRIVE_HALF
} StepperDriveMode;

typedef enum
{
  STEPPER_DIR_CW = 0,
  STEPPER_DIR_CCW
} StepperDirection;

typedef struct
{
  TIM_HandleTypeDef *timer;
  StepperDriveMode driveMode;
  StepperDirection direction;
  uint16_t stepsPerRevolution;
  volatile uint32_t remainingSteps;
  volatile uint8_t currentStep;
  volatile uint8_t busy;
} Stepper_HandleTypeDef;

void Stepper_Init(Stepper_HandleTypeDef *stepper,
                  TIM_HandleTypeDef *timer,
                  StepperDriveMode driveMode,
                  uint16_t stepsPerRevolution);
HAL_StatusTypeDef Stepper_SetStepFrequency(Stepper_HandleTypeDef *stepper,
                                           uint32_t frequencyHz);
HAL_StatusTypeDef Stepper_RotateSteps(Stepper_HandleTypeDef *stepper,
                                      uint32_t steps,
                                      StepperDirection direction);
HAL_StatusTypeDef Stepper_RotateDegrees(Stepper_HandleTypeDef *stepper,
                                        uint16_t degrees,
                                        StepperDirection direction);
void Stepper_OnTimerElapsed(Stepper_HandleTypeDef *stepper,
                            TIM_HandleTypeDef *htim);
void Stepper_Stop(Stepper_HandleTypeDef *stepper);
void Stepper_Release(Stepper_HandleTypeDef *stepper);
uint8_t Stepper_IsBusy(const Stepper_HandleTypeDef *stepper);

#endif /* INC_STEPPER_H_ */
