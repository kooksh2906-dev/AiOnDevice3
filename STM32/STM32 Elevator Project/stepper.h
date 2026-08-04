#ifndef INC_STEPPER_H_
#define INC_STEPPER_H_

#include "main.h"

/* 스텝 모터가 1-2상 여자 방식으로 정확히 1바퀴(360도)를 돌기 위한 총 스텝 수 */
#define STEPS_PER_REVOLATION    4096

/* 모터 시계 방향 회전 (엘리베이터 상승 또는 하강 중 한 방향으로 매핑) */
#define DIR_CW                  0

/* 모터 반시계 방향 회전 */
#define DIR_CCW                 1

#define IN1_GPIO_PORT   GPIOB
#define IN1_GPIO_PIN    GPIO_PIN_7
#define IN2_GPIO_PORT   GPIOC
#define IN2_GPIO_PIN    GPIO_PIN_4
#define IN3_GPIO_PORT   GPIOD
#define IN3_GPIO_PIN    GPIO_PIN_2
#define IN4_GPIO_PORT   GPIOC
#define IN4_GPIO_PIN    GPIO_PIN_11

/*
	현재 차례에 맞는 1-2상 여자 신호 패턴을 모터 핀에 1스텝 출력하는 함수
	step: 0~7 사이의 배열 인덱스 값
*/
void stepMotor(uint8_t step);

/*
	지정된 스텝(Step) 수와 방향만큼 승강용 모터를 연속으로 회전시키는 함수
	steps: 회전할 총 스텝 수
	direction: DIR_CW 또는 DIR_CCW
*/
void rotateSteps(uint16_t steps, uint8_t direction);

/*
	지정된 각도(Degree)와 방향만큼 승강용 모터를 연속으로 회전시키는 함수
	내부적으로 각도를 스텝 수로 변환하여 rotateSteps를 호출
	degrees: 회전할 각도 (예: 180, 360)
	direction: DIR_CW 또는 DIR_CCW
*/
void rotateDegrees(uint16_t degrees, uint8_t direction);

/*
	승강용 모터와 연결된 모든 핀의 출력을 LOW로 낮춰 전류를 차단하는 함수
	엘리베이터가 층에 도착하거나 비상 정지 시, 모터 과열을 막기 위해 반드시 호출
 */
void motorStop(void);

#endif /* INC_STEPPER_H_ */
