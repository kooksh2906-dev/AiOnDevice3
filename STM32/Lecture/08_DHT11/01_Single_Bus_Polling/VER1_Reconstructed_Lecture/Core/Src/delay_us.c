#include "delay_us.h"

void delay_us(uint16_t us)
{
  /* TIM11은 dht11Read()에서 먼저 시작하며, 1 MHz로 설정되어 있습니다. */
  __HAL_TIM_SET_COUNTER(&htim11, 0U);
  while (__HAL_TIM_GET_COUNTER(&htim11) < us)
  {
  }
}
