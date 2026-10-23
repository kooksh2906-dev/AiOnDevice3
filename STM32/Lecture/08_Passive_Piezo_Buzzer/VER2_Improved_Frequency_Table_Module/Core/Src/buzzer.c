#include "buzzer.h"

HAL_StatusTypeDef Buzzer_Init(Buzzer_HandleTypeDef *buzzer,
                              TIM_HandleTypeDef *htim,
                              uint32_t channel,
                              uint32_t timer_clock_hz,
                              uint16_t duty_permille)
{
  if ((buzzer == NULL) || (htim == NULL) ||
      (timer_clock_hz == 0U) || (duty_permille > 1000U))
  {
    return HAL_ERROR;
  }

  buzzer->htim = htim;
  buzzer->channel = channel;
  buzzer->timer_clock_hz = timer_clock_hz;
  buzzer->period_counts = __HAL_TIM_GET_AUTORELOAD(htim) + 1U;
  buzzer->duty_permille = duty_permille;

  if (buzzer->period_counts == 0U)
  {
    return HAL_ERROR;
  }

  Buzzer_Stop(buzzer);
  return HAL_OK;
}

HAL_StatusTypeDef Buzzer_PlayTone(Buzzer_HandleTypeDef *buzzer,
                                  uint16_t frequency_hz,
                                  uint32_t duration_ms)
{
  uint64_t denominator;
  uint64_t divider;
  uint32_t compare;

  if ((buzzer == NULL) || (buzzer->htim == NULL) || (duration_ms == 0U))
  {
    return HAL_ERROR;
  }

  if (frequency_hz == 0U)
  {
    Buzzer_Stop(buzzer);
    HAL_Delay(duration_ms);
    return HAL_OK;
  }

  denominator = (uint64_t)frequency_hz * buzzer->period_counts;
  divider = ((uint64_t)buzzer->timer_clock_hz + (denominator / 2U)) /
            denominator;

  /* TIM4의 PSC는 16-bit이므로 분주 계수는 1~65536 범위여야 합니다. */
  if ((divider == 0U) || (divider > 65536U))
  {
    Buzzer_Stop(buzzer);
    return HAL_ERROR;
  }

  compare = (buzzer->period_counts * buzzer->duty_permille) / 1000U;
  if (compare >= buzzer->period_counts)
  {
    compare = buzzer->period_counts - 1U;
  }

  /* PSC는 Preload Register이므로 Update Event로 새 분주값을 반영합니다. */
  __HAL_TIM_SET_COMPARE(buzzer->htim, buzzer->channel, 0U);
  __HAL_TIM_SET_PRESCALER(buzzer->htim, (uint32_t)(divider - 1U));
  __HAL_TIM_SET_COUNTER(buzzer->htim, 0U);
  __HAL_TIM_GENERATE_EVENT(buzzer->htim, TIM_EVENTSOURCE_UPDATE);
  __HAL_TIM_SET_COMPARE(buzzer->htim, buzzer->channel, compare);

  HAL_Delay(duration_ms);
  Buzzer_Stop(buzzer);
  return HAL_OK;
}

HAL_StatusTypeDef Buzzer_PlayMelody(Buzzer_HandleTypeDef *buzzer,
                                    const BuzzerNote_t *melody,
                                    uint32_t note_count)
{
  uint32_t i;

  if ((buzzer == NULL) || (melody == NULL) || (note_count == 0U))
  {
    return HAL_ERROR;
  }

  for (i = 0U; i < note_count; i++)
  {
    if (Buzzer_PlayTone(buzzer,
                        melody[i].frequency_hz,
                        melody[i].duration_ms) != HAL_OK)
    {
      return HAL_ERROR;
    }

    if (melody[i].rest_ms > 0U)
    {
      HAL_Delay(melody[i].rest_ms);
    }
  }

  return HAL_OK;
}

void Buzzer_Stop(Buzzer_HandleTypeDef *buzzer)
{
  if ((buzzer != NULL) && (buzzer->htim != NULL))
  {
    __HAL_TIM_SET_COMPARE(buzzer->htim, buzzer->channel, 0U);
  }
}
