#include "dht11.h"

void dht11Init(DHT11 *dht, GPIO_TypeDef *port, uint16_t pin)
{
  dht->port = port;
  dht->pin = pin;
}

void dht11GpioMode(DHT11 *dht, uint8_t mode)
{
  GPIO_InitTypeDef GPIO_InitStruct = {0};

  if (mode == OUTPUT)
  {
    GPIO_InitStruct.Pin = dht->pin;
    GPIO_InitStruct.Mode = GPIO_MODE_OUTPUT_PP;
    GPIO_InitStruct.Pull = GPIO_NOPULL;
    GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_HIGH;
    HAL_GPIO_Init(dht->port, &GPIO_InitStruct);
  }
  else if (mode == INPUT)
  {
    GPIO_InitStruct.Pin = dht->pin;
    GPIO_InitStruct.Mode = GPIO_MODE_INPUT;
    GPIO_InitStruct.Pull = GPIO_NOPULL;
    GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_HIGH;
    HAL_GPIO_Init(dht->port, &GPIO_InitStruct);
  }
  else
  {
  }
}

uint8_t dht11Read(DHT11 *dht)
{
  bool ret = true;
  uint16_t timeTick = 0U;
  uint8_t pulse[40] = {0};
  uint8_t humValue1 = 0U;
  uint8_t humValue2 = 0U;
  uint8_t tempValue1 = 0U;
  uint8_t tempValue2 = 0U;
  uint8_t parityValue = 0U;

  HAL_TIM_Base_Start(&htim11);

  /* MCU Start: 최소 18 ms Low 뒤 20~40 us High를 출력합니다. */
  dht11GpioMode(dht, OUTPUT);
  HAL_GPIO_WritePin(dht->port, dht->pin, GPIO_PIN_RESET);
  HAL_Delay(20U);
  HAL_GPIO_WritePin(dht->port, dht->pin, GPIO_PIN_SET);
  delay_us(20U);

  dht11GpioMode(dht, INPUT);

  /* DHT11의 약 80 us Low 응답과 약 80 us High 준비 신호를 기다립니다. */
  __HAL_TIM_SET_COUNTER(&htim11, 0U);
  while (HAL_GPIO_ReadPin(dht->port, dht->pin) == GPIO_PIN_RESET)
  {
    if (__HAL_TIM_GET_COUNTER(&htim11) > 100U)
    {
      printf("Low Signal Time out\n\r");
      break;
    }
  }

  __HAL_TIM_SET_COUNTER(&htim11, 0U);
  while (HAL_GPIO_ReadPin(dht->port, dht->pin) == GPIO_PIN_SET)
  {
    if (__HAL_TIM_GET_COUNTER(&htim11) > 100U)
    {
      printf("High Signal Time out\n\r");
      break;
    }
  }

  /* 40 bit의 각 High Pulse 길이로 0과 1을 구분합니다. */
  for (uint8_t i = 0U; i < 40U; i++)
  {
    while (HAL_GPIO_ReadPin(dht->port, dht->pin) == GPIO_PIN_RESET)
    {
    }

    __HAL_TIM_SET_COUNTER(&htim11, 0U);
    while (HAL_GPIO_ReadPin(dht->port, dht->pin) == GPIO_PIN_SET)
    {
      timeTick = (uint16_t)__HAL_TIM_GET_COUNTER(&htim11);

      if ((timeTick > 20U) && (timeTick < 30U))
      {
        pulse[i] = 0U;
      }
      else if ((timeTick > 65U) && (timeTick < 85U))
      {
        pulse[i] = 1U;
      }
      else
      {
      }
    }
  }

  HAL_TIM_Base_Stop(&htim11);

  for (uint8_t i = 0U; i < 8U; i++)
  {
    humValue1 = (uint8_t)((humValue1 << 1U) + pulse[i]);
  }
  for (uint8_t i = 8U; i < 16U; i++)
  {
    humValue2 = (uint8_t)((humValue2 << 1U) + pulse[i]);
  }
  for (uint8_t i = 16U; i < 24U; i++)
  {
    tempValue1 = (uint8_t)((tempValue1 << 1U) + pulse[i]);
  }
  for (uint8_t i = 24U; i < 32U; i++)
  {
    tempValue2 = (uint8_t)((tempValue2 << 1U) + pulse[i]);
  }
  for (uint8_t i = 32U; i < 40U; i++)
  {
    parityValue = (uint8_t)((parityValue << 1U) + pulse[i]);
  }

  dht->temperature = tempValue1;
  dht->humidity = humValue1;

  {
    uint8_t checkSum = (uint8_t)(humValue1 + humValue2 +
                                 tempValue1 + tempValue2);
    if (checkSum != parityValue)
    {
      printf("checkSum Error\r\n");
      ret = false;
    }
  }

  return (uint8_t)ret;
}
