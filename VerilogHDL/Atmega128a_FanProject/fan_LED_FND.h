#ifndef FAN_VISUAL_H_
#define FAN_VISUAL_H_

#include "fan_config.h" // 공용 상태 변수(speed_state 등)를 공유하기 위해 포함

// 외부(main.c)에서 호출할 수 있도록 함수 선언
void visual_init(void);                    // FND, LED 핀 및 타이머0 초기화
void display_speed(uint8_t state);         // 현재 풍속을 FND에 표시
void update_led_sweep(uint16_t servo_pos); // 서보 위치에 따른 LED 잔상 계산

#endif /* FAN_VISUAL_H_ */
