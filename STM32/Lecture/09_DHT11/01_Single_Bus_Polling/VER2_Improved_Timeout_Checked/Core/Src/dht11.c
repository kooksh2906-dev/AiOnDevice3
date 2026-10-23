#include "dht11.h"

#define DHT11_RESPONSE_TIMEOUT_US 110U
#define DHT11_DATA_TIMEOUT_US     110U
#define DHT11_ONE_THRESHOLD_US     50U

static void DHT11_SetPinMode(DHT11_HandleTypeDef *dht, DHT11_PinMode mode)
{
  GPIO_InitTypeDef gpio = {0};

  gpio.Pin = dht->pin;
  gpio.Pull = GPIO_NOPULL;
  gpio.Speed = GPIO_SPEED_FREQ_HIGH;
  gpio.Mode = (mode == DHT11_PIN_OUTPUT) ? GPIO_MODE_OUTPUT_PP
                                         : GPIO_MODE_INPUT;
  HAL_GPIO_Init(dht->port, &gpio);
}

static uint8_t DHT11_WaitWhile(DHT11_HandleTypeDef *dht,
                               GPIO_PinState state,
                               uint16_t timeoutUs,
                               uint16_t *elapsedUs)
{
  uint32_t elapsed;

  __HAL_TIM_SET_COUNTER(dht->timer, 0U);
  while (HAL_GPIO_ReadPin(dht->port, dht->pin) == state)
  {
    elapsed = __HAL_TIM_GET_COUNTER(dht->timer);
    if (elapsed > timeoutUs)
    {
      return 0U;
    }
  }

  if (elapsedUs != NULL)
  {
    *elapsedUs = (uint16_t)__HAL_TIM_GET_COUNTER(dht->timer);
  }

  return 1U;
}

static DHT11_Status DHT11_FinishRead(DHT11_HandleTypeDef *dht,
                                     DHT11_Status status)
{
  DHT11_SetPinMode(dht, DHT11_PIN_INPUT);
  (void)HAL_TIM_Base_Stop(dht->timer);
  return status;
}

void DHT11_Init(DHT11_HandleTypeDef *dht,
                GPIO_TypeDef *port,
                uint16_t pin,
                TIM_HandleTypeDef *timer)
{
  if (dht == NULL)
  {
    return;
  }

  dht->port = port;
  dht->pin = pin;
  dht->timer = timer;
  dht->humidityInteger = 0U;
  dht->humidityDecimal = 0U;
  dht->temperatureInteger = 0U;
  dht->temperatureDecimal = 0U;

  if ((port != NULL) && (timer != NULL))
  {
    DHT11_SetPinMode(dht, DHT11_PIN_INPUT);
  }
}

DHT11_Status DHT11_Read(DHT11_HandleTypeDef *dht)
{
  uint8_t bytes[5] = {0};
  uint16_t highPulseUs;
  uint8_t expectedChecksum;

  if ((dht == NULL) || (dht->port == NULL) || (dht->timer == NULL))
  {
    return DHT11_ERROR_ARGUMENT;
  }

  if (HAL_TIM_Base_Start(dht->timer) != HAL_OK)
  {
    return DHT11_ERROR_ARGUMENT;
  }

  DHT11_SetPinMode(dht, DHT11_PIN_OUTPUT);
  HAL_GPIO_WritePin(dht->port, dht->pin, GPIO_PIN_RESET);
  HAL_Delay(20U);
  HAL_GPIO_WritePin(dht->port, dht->pin, GPIO_PIN_SET);
  delay_us(dht->timer, 30U);
  DHT11_SetPinMode(dht, DHT11_PIN_INPUT);

  /* MCU가 선을 놓은 뒤 DHT11이 응답 Low를 시작할 때까지 기다립니다. */
  if (DHT11_WaitWhile(dht,
                      GPIO_PIN_SET,
                      DHT11_RESPONSE_TIMEOUT_US,
                      NULL) == 0U)
  {
    return DHT11_FinishRead(dht, DHT11_ERROR_RESPONSE_START_TIMEOUT);
  }

  if (DHT11_WaitWhile(dht,
                      GPIO_PIN_RESET,
                      DHT11_RESPONSE_TIMEOUT_US,
                      NULL) == 0U)
  {
    return DHT11_FinishRead(dht, DHT11_ERROR_RESPONSE_LOW_TIMEOUT);
  }

  if (DHT11_WaitWhile(dht,
                      GPIO_PIN_SET,
                      DHT11_RESPONSE_TIMEOUT_US,
                      NULL) == 0U)
  {
    return DHT11_FinishRead(dht, DHT11_ERROR_RESPONSE_HIGH_TIMEOUT);
  }

  for (uint8_t bit = 0U; bit < 40U; bit++)
  {
    if (DHT11_WaitWhile(dht,
                        GPIO_PIN_RESET,
                        DHT11_DATA_TIMEOUT_US,
                        NULL) == 0U)
    {
      return DHT11_FinishRead(dht, DHT11_ERROR_DATA_LOW_TIMEOUT);
    }

    if (DHT11_WaitWhile(dht,
                        GPIO_PIN_SET,
                        DHT11_DATA_TIMEOUT_US,
                        &highPulseUs) == 0U)
    {
      return DHT11_FinishRead(dht, DHT11_ERROR_DATA_HIGH_TIMEOUT);
    }

    bytes[bit / 8U] = (uint8_t)(bytes[bit / 8U] << 1U);
    if (highPulseUs > DHT11_ONE_THRESHOLD_US)
    {
      bytes[bit / 8U] |= 1U;
    }
  }

  expectedChecksum = (uint8_t)(bytes[0] + bytes[1] + bytes[2] + bytes[3]);
  if (expectedChecksum != bytes[4])
  {
    return DHT11_FinishRead(dht, DHT11_ERROR_CHECKSUM);
  }

  /* Checksum 통과 후에만 이전의 정상 측정값을 갱신합니다. */
  dht->humidityInteger = bytes[0];
  dht->humidityDecimal = bytes[1];
  dht->temperatureInteger = bytes[2];
  dht->temperatureDecimal = bytes[3];

  return DHT11_FinishRead(dht, DHT11_OK);
}
