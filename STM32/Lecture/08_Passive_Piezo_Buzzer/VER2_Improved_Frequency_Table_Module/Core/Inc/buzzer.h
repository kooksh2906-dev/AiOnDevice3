#ifndef INC_BUZZER_H_
#define INC_BUZZER_H_

#include "stm32f4xx_hal.h"

typedef struct
{
  uint16_t frequency_hz;
  uint16_t duration_ms;
  uint16_t rest_ms;
} BuzzerNote_t;

typedef struct
{
  TIM_HandleTypeDef *htim;
  uint32_t channel;
  uint32_t timer_clock_hz;
  uint32_t period_counts;
  uint16_t duty_permille;
} Buzzer_HandleTypeDef;

HAL_StatusTypeDef Buzzer_Init(Buzzer_HandleTypeDef *buzzer,
                              TIM_HandleTypeDef *htim,
                              uint32_t channel,
                              uint32_t timer_clock_hz,
                              uint16_t duty_permille);
HAL_StatusTypeDef Buzzer_PlayTone(Buzzer_HandleTypeDef *buzzer,
                                  uint16_t frequency_hz,
                                  uint32_t duration_ms);
HAL_StatusTypeDef Buzzer_PlayMelody(Buzzer_HandleTypeDef *buzzer,
                                    const BuzzerNote_t *melody,
                                    uint32_t note_count);
void Buzzer_Stop(Buzzer_HandleTypeDef *buzzer);

#endif /* INC_BUZZER_H_ */
