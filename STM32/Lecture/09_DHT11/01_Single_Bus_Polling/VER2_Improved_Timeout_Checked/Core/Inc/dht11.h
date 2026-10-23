#ifndef INC_DHT11_H_
#define INC_DHT11_H_

#include "delay_us.h"

typedef enum
{
  DHT11_OK = 0,
  DHT11_ERROR_ARGUMENT,
  DHT11_ERROR_RESPONSE_START_TIMEOUT,
  DHT11_ERROR_RESPONSE_LOW_TIMEOUT,
  DHT11_ERROR_RESPONSE_HIGH_TIMEOUT,
  DHT11_ERROR_DATA_LOW_TIMEOUT,
  DHT11_ERROR_DATA_HIGH_TIMEOUT,
  DHT11_ERROR_CHECKSUM
} DHT11_Status;

typedef enum
{
  DHT11_PIN_INPUT = 0,
  DHT11_PIN_OUTPUT
} DHT11_PinMode;

typedef struct
{
  GPIO_TypeDef *port;
  uint16_t pin;
  TIM_HandleTypeDef *timer;
  uint8_t humidityInteger;
  uint8_t humidityDecimal;
  uint8_t temperatureInteger;
  uint8_t temperatureDecimal;
} DHT11_HandleTypeDef;

void DHT11_Init(DHT11_HandleTypeDef *dht,
                GPIO_TypeDef *port,
                uint16_t pin,
                TIM_HandleTypeDef *timer);
DHT11_Status DHT11_Read(DHT11_HandleTypeDef *dht);

#endif /* INC_DHT11_H_ */
