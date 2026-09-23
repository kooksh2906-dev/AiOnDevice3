#ifndef INC_LED_H_
#define INC_LED_H_

#include "main.h"
#include <stdint.h>

/*
 	 현재 켜져야 할 LED의 인덱스 번호를 받아 해당 LED만 켜고 나머지는 끄는 함수
 	 active_index: 0~7 사이의 값이면 해당 위치의 LED 점등, -1이 들어오면 모든 LED 소등
*/
void LED_Update(int8_t active_index);

/* 100ms 간격으로 이동 방향에 맞춰 LED 표시를 갱신합니다 (0:소등). */
void LED_ShiftUpdate(uint8_t lift_direction);

#endif /* INC_LED_H_ */
