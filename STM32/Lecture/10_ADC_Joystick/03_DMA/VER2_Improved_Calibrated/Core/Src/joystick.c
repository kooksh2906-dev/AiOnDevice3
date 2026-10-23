#include "joystick.h"

#include <stddef.h>

#define JOYSTICK_FILTER_SCALE 4L

static int16_t Joystick_NormalizeAxis(uint16_t value,
                                      uint16_t center,
                                      uint16_t deadZone);

void Joystick_Init(Joystick_HandleTypeDef *joystick,
                   uint16_t centerX,
                   uint16_t centerY,
                   uint16_t deadZone)
{
  if (joystick == NULL)
  {
    return;
  }

  if (centerX > JOYSTICK_ADC_MAX_VALUE)
  {
    centerX = JOYSTICK_ADC_MAX_VALUE;
  }
  if (centerY > JOYSTICK_ADC_MAX_VALUE)
  {
    centerY = JOYSTICK_ADC_MAX_VALUE;
  }

  joystick->centerX = centerX;
  joystick->centerY = centerY;
  joystick->deadZone = deadZone;
  joystick->filteredXQ2 = (int32_t)centerX * JOYSTICK_FILTER_SCALE;
  joystick->filteredYQ2 = (int32_t)centerY * JOYSTICK_FILTER_SCALE;
}

void Joystick_Update(Joystick_HandleTypeDef *joystick,
                     uint16_t rawX,
                     uint16_t rawY,
                     Joystick_StateTypeDef *state)
{
  uint16_t filteredX;
  uint16_t filteredY;

  if ((joystick == NULL) || (state == NULL))
  {
    return;
  }

  /* 1차 IIR: filtered += (input - filtered) / 4 */
  joystick->filteredXQ2 +=
      (((int32_t)rawX * JOYSTICK_FILTER_SCALE) - joystick->filteredXQ2) / 4L;
  joystick->filteredYQ2 +=
      (((int32_t)rawY * JOYSTICK_FILTER_SCALE) - joystick->filteredYQ2) / 4L;

  filteredX = (uint16_t)(joystick->filteredXQ2 / JOYSTICK_FILTER_SCALE);
  filteredY = (uint16_t)(joystick->filteredYQ2 / JOYSTICK_FILTER_SCALE);

  state->rawX = rawX;
  state->rawY = rawY;
  state->normalizedX = Joystick_NormalizeAxis(filteredX,
                                               joystick->centerX,
                                               joystick->deadZone);
  state->normalizedY = Joystick_NormalizeAxis(filteredY,
                                               joystick->centerY,
                                               joystick->deadZone);
}

static int16_t Joystick_NormalizeAxis(uint16_t value,
                                      uint16_t center,
                                      uint16_t deadZone)
{
  int32_t lowerBoundary;
  int32_t upperBoundary;
  int32_t normalized;

  lowerBoundary = (int32_t)center - (int32_t)deadZone;
  upperBoundary = (int32_t)center + (int32_t)deadZone;

  if (lowerBoundary < 0L)
  {
    lowerBoundary = 0L;
  }
  if (upperBoundary > (int32_t)JOYSTICK_ADC_MAX_VALUE)
  {
    upperBoundary = JOYSTICK_ADC_MAX_VALUE;
  }

  if (((int32_t)value >= lowerBoundary) &&
      ((int32_t)value <= upperBoundary))
  {
    return 0;
  }

  if ((int32_t)value > upperBoundary)
  {
    if (upperBoundary >= (int32_t)JOYSTICK_ADC_MAX_VALUE)
    {
      return 0;
    }

    normalized = ((int32_t)value - upperBoundary) * JOYSTICK_NORMALIZED_MAX /
                 ((int32_t)JOYSTICK_ADC_MAX_VALUE - upperBoundary);
  }
  else
  {
    if (lowerBoundary <= 0L)
    {
      return 0;
    }

    normalized = -((lowerBoundary - (int32_t)value) * JOYSTICK_NORMALIZED_MAX /
                   lowerBoundary);
  }

  if (normalized > JOYSTICK_NORMALIZED_MAX)
  {
    normalized = JOYSTICK_NORMALIZED_MAX;
  }
  else if (normalized < -JOYSTICK_NORMALIZED_MAX)
  {
    normalized = -JOYSTICK_NORMALIZED_MAX;
  }

  return (int16_t)normalized;
}

