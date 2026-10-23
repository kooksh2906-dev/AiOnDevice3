#ifndef INC_BUZZER_H_
#define INC_BUZZER_H_

#include "main.h"

/* 원본 화면의 TIM4 Prescaler 값을 보존합니다. */
#define NOTE_A4   226U  /* 라 */
#define NOTE_B4   202U  /* 시 */
#define NOTE_C5   190U  /* 도 */
#define NOTE_D5   169U  /* 레 */
#define NOTE_E5   151U  /* 미 */
#define NOTE_FS5  134U  /* 파# */
#define NOTE_G5   127U  /* 솔 */
#define NOTE_A5   113U  /* 높은 라 */

#define T_8       150U  /* 8분음표 */
#define T_4       300U  /* 4분음표 */
#define T_2       600U  /* 2분음표 */

void Buzzer_Do(void);
void Buzzer_Mi(void);
void Buzzer_Sol(void);
void Buzzer_Play(uint16_t psc, uint32_t duration_ms);
void Play_Melodica_Washing_Machine(void);

#endif /* INC_BUZZER_H_ */
