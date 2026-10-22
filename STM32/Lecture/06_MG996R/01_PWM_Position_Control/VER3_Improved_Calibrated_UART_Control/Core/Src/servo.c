#include "servo.h"
#include <stddef.h>

void Servo_Init(Servo_HandleTypeDef *servo,
                TIM_HandleTypeDef *timer,
                uint32_t channel,
                uint16_t timerTickUs,
                uint16_t minPulseUs,
                uint16_t centerPulseUs,
                uint16_t maxPulseUs)
{
  if ((servo == NULL) || (timer == NULL) || (timerTickUs == 0U))
  {
    return;
  }

  servo->timer = timer;
  servo->channel = channel;
  servo->timerTickUs = timerTickUs;
  servo->minPulseUs = minPulseUs;
  servo->centerPulseUs = centerPulseUs;
  servo->maxPulseUs = maxPulseUs;
}

void Servo_WritePulseUs(Servo_HandleTypeDef *servo, uint16_t pulseUs)
{
  uint32_t compare;

  if ((servo == NULL) || (servo->timer == NULL) ||
      (servo->timerTickUs == 0U))
  {
    return;
  }

  if (pulseUs < servo->minPulseUs)
  {
    pulseUs = servo->minPulseUs;
  }
  else if (pulseUs > servo->maxPulseUs)
  {
    pulseUs = servo->maxPulseUs;
  }

  /* 반올림을 포함하여 us 단위 Pulse Width를 Timer Count로 변환합니다. */
  compare = ((uint32_t)pulseUs + (servo->timerTickUs / 2U)) /
            servo->timerTickUs;

  if (compare > __HAL_TIM_GET_AUTORELOAD(servo->timer))
  {
    compare = __HAL_TIM_GET_AUTORELOAD(servo->timer);
  }

  __HAL_TIM_SET_COMPARE(servo->timer, servo->channel, compare);
}

void Servo_WriteAngle(Servo_HandleTypeDef *servo, int16_t angleDegree)
{
  int32_t pulseUs;

  if (servo == NULL)
  {
    return;
  }

  if (angleDegree < -90)
  {
    angleDegree = -90;
  }
  else if (angleDegree > 90)
  {
    angleDegree = 90;
  }

  /* 실습의 -90/0/+90 표기를 0.5/1.5/2.5 ms에 선형 대응합니다. */
  if (angleDegree < 0)
  {
    pulseUs = (int32_t)servo->centerPulseUs -
              (((int32_t)(-angleDegree) *
                ((int32_t)servo->centerPulseUs - servo->minPulseUs)) / 90);
  }
  else
  {
    pulseUs = (int32_t)servo->centerPulseUs +
              (((int32_t)angleDegree *
                ((int32_t)servo->maxPulseUs - servo->centerPulseUs)) / 90);
  }

  Servo_WritePulseUs(servo, (uint16_t)pulseUs);
}
