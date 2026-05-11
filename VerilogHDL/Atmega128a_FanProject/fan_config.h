#ifndef FAN_CONFIG_H_
#define FAN_CONFIG_H_

// 1. 공통 라이브러리 (모두가 쓰는 것)
#define F_CPU 16000000UL // 16MHz (반드시 최상단에 위치)
#include <avr/io.h>
#include <util/delay.h>
#include <avr/interrupt.h>
#include <stdlib.h>
#include <stdio.h>

#include "fan_register.h" // 핀 설정 지휘자
#include "fan_uart.h"     // 통신 지휘자
#include "fan_LED_FND.h"  // 시각 지휘자
#include "fan_motor.h"    // 모터 지휘자
#include "fan_button.h"   // 버튼 지휘자


// 2. 공통 상태 변수 (모든 모듈이 공유해야 하는 시스템의 핵심 상태)
extern volatile uint8_t is_running;   // 전체 시스템 동작/정지 상태
extern volatile uint8_t speed_state;  // 현재 풍속 상태 (0~3단)
extern volatile uint8_t rotate_state; // 현재 회전 상태 (0 또는 1)

// 3. 다른 팀원들의 전용 변수 및 함수
extern volatile uint8_t brightness[8]; // [팀원 파트] LED 잔상 밝기 배열

void motor_init(void);  // [팀원 파트] 모터 초기화
void visual_init(void); // [팀원 파트] FND & LED 초기화

#endif /* FAN_CONFIG_H_ */
