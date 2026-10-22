/*
 * delay.c
 *
 * TIM11의 1 MHz Counter를 이용한 짧은 Blocking Delay입니다.
 */

#include "delay.h"

void delay_us(uint16_t us)
{
  __HAL_TIM_SET_COUNTER(&htim11, 0U);
  while (__HAL_TIM_GET_COUNTER(&htim11) < us)
  {
  }
}
