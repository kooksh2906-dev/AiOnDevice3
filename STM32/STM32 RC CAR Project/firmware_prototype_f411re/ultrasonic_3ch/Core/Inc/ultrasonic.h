/*
 * ultrasonic.h
 *
 *  Created on: 2026. 6. 21.
 *      Author: user
 */

#ifndef INC_ULTRASONIC_H_
#define INC_ULTRASONIC_H_

#include "main.h"
#include "tim.h"
#include "delay_us.h"

/* 하드웨어 매핑 매크로 (사용자 환경에 맞게 수정) */
#define TRIG_LEFT_PORT    GPIOB
#define TRIG_LEFT_PIN     GPIO_PIN_4
#define TRIG_FRONT_PORT   GPIOB
#define TRIG_FRONT_PIN    GPIO_PIN_5
#define TRIG_RIGHT_PORT   GPIOB
#define TRIG_RIGHT_PIN    GPIO_PIN_3

typedef struct {
	// 1. 하드웨어 설정 (초기화 후 변하지 않음)
	GPIO_TypeDef* trig_port;       // TRIG GPIO 포트
	uint16_t              trig_pin;        // TRIG GPIO 핀
	uint32_t              tim_channel;     // TIM 인풋 캡처 채널
	uint32_t              tim_it_cc;       // TIM CC 인터럽트 플래그
	HAL_TIM_ActiveChannel active_channel;  // 콜백 판별용 채널

	// 2. 런타임 상태 (실시간으로 변하는 데이터)
	volatile uint16_t     IC_Value1;       // Rising 캡처 시간
	volatile uint16_t     IC_Value2;       // Falling 캡처 시간
	volatile uint8_t      captureFlag;     // 0: Rising 대기, 1: Falling 대기
	volatile uint16_t     distance;        // 계산된 최종 거리 (cm)
} Ultrasonic_Control;

/* 외부에서 센서 객체에 접근할 수 있도록 extern 선언 */
extern Ultrasonic_Control US_LEFT;
extern Ultrasonic_Control US_FRONT;
extern Ultrasonic_Control US_RIGHT;

/* 구조체 포인터를 인자로 받는 함수 프로토타입 */
void Ultrasonic_Trigger(Ultrasonic_Control *us);
void Ultrasonic_Scan_ALL(void);

#endif /* INC_ULTRASONIC_H_ */
