#ifndef INC_JOYSTICK_H_
#define INC_JOYSTICK_H_

#include <stdint.h>

#define JOYSTICK_ADC_MAX_VALUE 4095U
#define JOYSTICK_NORMALIZED_MAX 1000

typedef struct
{
  uint16_t centerX;
  uint16_t centerY;
  uint16_t deadZone;
  int32_t filteredXQ2;
  int32_t filteredYQ2;
} Joystick_HandleTypeDef;

typedef struct
{
  uint16_t rawX;
  uint16_t rawY;
  int16_t normalizedX;
  int16_t normalizedY;
} Joystick_StateTypeDef;

void Joystick_Init(Joystick_HandleTypeDef *joystick,
                   uint16_t centerX,
                   uint16_t centerY,
                   uint16_t deadZone);

void Joystick_Update(Joystick_HandleTypeDef *joystick,
                     uint16_t rawX,
                     uint16_t rawY,
                     Joystick_StateTypeDef *state);

#endif /* INC_JOYSTICK_H_ */

