/*
 * motor.c
 *
 *  Created on: 2026. 6. 4.
 *      Author: user
 */

#include "motor.h"
#include "tim.h"

void motor_forward(void) {
    if(current_speed < 300) current_speed = 300;
    HAL_GPIO_WritePin(PORT_L298N, PIN_IN1|PIN_IN3, GPIO_PIN_SET);
    HAL_GPIO_WritePin(PORT_L298N, PIN_IN2|PIN_IN4, GPIO_PIN_RESET);
    __HAL_TIM_SET_COMPARE(&htim4, TIM_CHANNEL_1, current_speed);
    __HAL_TIM_SET_COMPARE(&htim4, TIM_CHANNEL_2, current_speed);
}

void motor_backward(void) {
    if(current_speed < 300) current_speed = 300;
    HAL_GPIO_WritePin(PORT_L298N, PIN_IN1|PIN_IN3, GPIO_PIN_RESET);
    HAL_GPIO_WritePin(PORT_L298N, PIN_IN2|PIN_IN4, GPIO_PIN_SET);
    __HAL_TIM_SET_COMPARE(&htim4, TIM_CHANNEL_1, current_speed);
    __HAL_TIM_SET_COMPARE(&htim4, TIM_CHANNEL_2, current_speed);
}

void motor_left(void) {
    if(current_speed < 300) current_speed = 300;
    HAL_GPIO_WritePin(PORT_L298N, PIN_IN1|PIN_IN4, GPIO_PIN_SET);
    HAL_GPIO_WritePin(PORT_L298N, PIN_IN2|PIN_IN3, GPIO_PIN_RESET);
    __HAL_TIM_SET_COMPARE(&htim4, TIM_CHANNEL_1, current_speed);
    __HAL_TIM_SET_COMPARE(&htim4, TIM_CHANNEL_2, current_speed);
}

void motor_right(void) {
    if(current_speed < 300) current_speed = 300;
    HAL_GPIO_WritePin(PORT_L298N, PIN_IN2|PIN_IN3, GPIO_PIN_SET);
    HAL_GPIO_WritePin(PORT_L298N, PIN_IN1|PIN_IN4, GPIO_PIN_RESET);
    __HAL_TIM_SET_COMPARE(&htim4, TIM_CHANNEL_1, current_speed);
    __HAL_TIM_SET_COMPARE(&htim4, TIM_CHANNEL_2, current_speed);
}

void motor_stop(void) {
    HAL_GPIO_WritePin(PORT_L298N, PIN_IN1|PIN_IN2|PIN_IN3|PIN_IN4, GPIO_PIN_RESET);
    __HAL_TIM_SET_COMPARE(&htim4, TIM_CHANNEL_1, 0);
    __HAL_TIM_SET_COMPARE(&htim4, TIM_CHANNEL_2, 0);
}

// 새로 분리된 속도 증가 함수 (올려주신 코드 100% 동일)
void motor_speed_up(void) {
    if(current_speed <= 899) current_speed += 100;
    else current_speed = 999; // ARR 최대치 제한

    // 차가 이미 움직이고 있는 도중이라면, 즉시 새 속도를 모터에 주입!
    if (__HAL_TIM_GET_COMPARE(&htim4, TIM_CHANNEL_1) > 0) {
        __HAL_TIM_SET_COMPARE(&htim4, TIM_CHANNEL_1, current_speed);
        __HAL_TIM_SET_COMPARE(&htim4, TIM_CHANNEL_2, current_speed);
    }
}

// 새로 분리된 속도 감소 함수 (최저 속도 300 반영)
void motor_speed_down(void) {
    if(current_speed >= 400) current_speed -= 100;
    else current_speed = 300; // 최소치 제한

    // 차가 이미 움직이고 있는 도중이라면, 즉시 새 속도를 모터에 주입!
    if (__HAL_TIM_GET_COMPARE(&htim4, TIM_CHANNEL_1) > 0) {
        __HAL_TIM_SET_COMPARE(&htim4, TIM_CHANNEL_1, current_speed);
        __HAL_TIM_SET_COMPARE(&htim4, TIM_CHANNEL_2, current_speed);
    }
}
