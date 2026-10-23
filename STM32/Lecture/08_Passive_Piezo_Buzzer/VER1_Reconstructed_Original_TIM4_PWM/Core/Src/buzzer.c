#include "buzzer.h"

void Buzzer_Do(void)
{
  TIM4->PSC = 383U; /* 도 */
  HAL_Delay(600U);
  TIM4->CCR1 = 0U;
  HAL_Delay(10U);
  TIM4->CCR1 = 500U;
}

void Buzzer_Mi(void)
{
  TIM4->PSC = 304U; /* 미 */
  HAL_Delay(600U);
  TIM4->CCR1 = 0U;
  HAL_Delay(10U);
  TIM4->CCR1 = 500U;
}

void Buzzer_Sol(void)
{
  /* 실제 수업 화면은 Mi와 같은 PSC 304를 사용합니다. */
  TIM4->PSC = 304U; /* 솔 */
  HAL_Delay(600U);
  TIM4->CCR1 = 0U;
  HAL_Delay(10U);
  TIM4->CCR1 = 500U;
}

void Buzzer_Play(uint16_t psc, uint32_t duration_ms)
{
  TIM4->PSC = psc;
  HAL_Delay(duration_ms);
  TIM4->CCR1 = 0U;   /* 음 분리 */
  HAL_Delay(20U);    /* 20 ms 여백 */
  TIM4->CCR1 = 500U; /* 약 50% Duty 복구 */
}

void Play_Melodica_Washing_Machine(void)
{
  TIM4->CCR1 = 500U;

  /* [1절] 레 솔 파# 미 레 시 */
  Buzzer_Play(NOTE_D5, T_4);
  Buzzer_Play(NOTE_G5, T_4);
  Buzzer_Play(NOTE_FS5, T_8);
  Buzzer_Play(NOTE_E5, T_8);
  Buzzer_Play(NOTE_D5, T_4);
  Buzzer_Play(NOTE_B4, T_2);

  TIM4->CCR1 = 0U;
  HAL_Delay(50U);
  TIM4->CCR1 = 500U;

  /* [2절] 도레미라시레 */
  Buzzer_Play(NOTE_C5, T_4);
  Buzzer_Play(NOTE_D5, T_4);
  Buzzer_Play(NOTE_E5, T_4);
  Buzzer_Play(NOTE_A4, T_4);
  Buzzer_Play(NOTE_B4, T_8);
  Buzzer_Play(NOTE_C5, T_8);
  Buzzer_Play(NOTE_B4, T_4);
  Buzzer_Play(NOTE_D5, T_4);

  /* [3절] 레 솔 파# 미 레 솔 */
  Buzzer_Play(NOTE_D5, T_4);
  Buzzer_Play(NOTE_G5, T_4);
  Buzzer_Play(NOTE_FS5, T_8);
  Buzzer_Play(NOTE_E5, T_8);
  Buzzer_Play(NOTE_D5, T_4);
  Buzzer_Play(NOTE_G5, T_2);

  TIM4->CCR1 = 0U;
  HAL_Delay(50U);
  TIM4->CCR1 = 500U;

  /* [4절] 솔 라 솔 파# 미 파# 솔 */
  Buzzer_Play(NOTE_G5, T_8);
  Buzzer_Play(NOTE_A5, T_8);
  Buzzer_Play(NOTE_G5, T_8);
  Buzzer_Play(NOTE_FS5, T_4);
  Buzzer_Play(NOTE_E5, T_8);
  Buzzer_Play(NOTE_FS5, T_8);
  Buzzer_Play(NOTE_G5, T_2);

  TIM4->CCR1 = 0U;
}
