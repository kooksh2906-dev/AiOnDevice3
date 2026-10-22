/*
 * delay.c
 *
 * 수업 화면에 남은 TIM11 기반 마이크로초 지연 함수를 복원했습니다.
 */

#include "delay.h"

void delay_us(uint16_t us)
{
  /* TIM11은 1 MHz Counter Clock이므로 Counter 1 Count가 1 us입니다. */
  __HAL_TIM_SET_COUNTER(&htim11, 0U);
  while (__HAL_TIM_GET_COUNTER(&htim11) < us)
  {
  }
}
