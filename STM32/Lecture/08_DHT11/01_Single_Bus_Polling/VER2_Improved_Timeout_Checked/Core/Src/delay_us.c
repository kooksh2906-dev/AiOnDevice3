#include "delay_us.h"

void delay_us(TIM_HandleTypeDef *timer, uint16_t us)
{
  if (timer == NULL)
  {
    return;
  }

  __HAL_TIM_SET_COUNTER(timer, 0U);
  while (__HAL_TIM_GET_COUNTER(timer) < us)
  {
  }
}
