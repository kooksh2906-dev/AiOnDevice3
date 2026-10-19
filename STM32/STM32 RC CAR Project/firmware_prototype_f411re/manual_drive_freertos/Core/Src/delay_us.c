/*
 * us_delay.c
 *
 *  Created on: 2026. 6. 4.
 *      Author: user
 */

#include <delay_us.h>

void delay_us(uint16_t us){ // delay 함수를 만드는 가장 기초적인 원리

	__HAL_TIM_SET_COUNTER(&htim10,0); // 예를 호출하면 카운터가 0부터 세팅
	while((__HAL_TIM_GET_COUNTER(&htim10)) < us); // blocking 코드, 입력받는 us보다 작을 때 까지 카운터를 셈

}
