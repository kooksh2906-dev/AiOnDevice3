#ifndef SERVO_H_
#define SERVO_H_

#include "main.h"

typedef struct
{
  TIM_HandleTypeDef *timer;
  uint32_t channel;
  uint16_t timerTickUs;
  uint16_t minPulseUs;
  uint16_t centerPulseUs;
  uint16_t maxPulseUs;
} Servo_HandleTypeDef;

void Servo_Init(Servo_HandleTypeDef *servo,
                TIM_HandleTypeDef *timer,
                uint32_t channel,
                uint16_t timerTickUs,
                uint16_t minPulseUs,
                uint16_t centerPulseUs,
                uint16_t maxPulseUs);
void Servo_WritePulseUs(Servo_HandleTypeDef *servo, uint16_t pulseUs);
void Servo_WriteAngle(Servo_HandleTypeDef *servo, int16_t angleDegree);

#endif /* SERVO_H_ */
