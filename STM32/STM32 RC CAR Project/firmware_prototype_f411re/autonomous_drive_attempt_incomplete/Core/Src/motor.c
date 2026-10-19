#include "motor.h"
#include "tim.h"

#define MOTOR_GPIO        GPIOB
#define L298N_IN1_PIN     GPIO_PIN_1   // 우전진
#define L298N_IN2_PIN     GPIO_PIN_15  // 우후진
#define L298N_IN3_PIN     GPIO_PIN_14  // 좌전진
#define L298N_IN4_PIN     GPIO_PIN_13  // 좌후진

void Motor_Init(void) {
    HAL_TIM_PWM_Start(&htim4, TIM_CHANNEL_1);
    HAL_TIM_PWM_Start(&htim4, TIM_CHANNEL_2);
    Motor_Stop();
}

void Motor_Stop(void) {
    HAL_GPIO_WritePin(MOTOR_GPIO, L298N_IN1_PIN | L298N_IN2_PIN | L298N_IN3_PIN | L298N_IN4_PIN, GPIO_PIN_RESET);
    __HAL_TIM_SET_COMPARE(&htim4, TIM_CHANNEL_1, 0);
    __HAL_TIM_SET_COMPARE(&htim4, TIM_CHANNEL_2, 0);
}

void Motor_Straight(uint16_t pwm) {
    HAL_GPIO_WritePin(MOTOR_GPIO, L298N_IN1_PIN | L298N_IN3_PIN, GPIO_PIN_SET);
    HAL_GPIO_WritePin(MOTOR_GPIO, L298N_IN2_PIN | L298N_IN4_PIN, GPIO_PIN_RESET);
    __HAL_TIM_SET_COMPARE(&htim4, TIM_CHANNEL_1, pwm); // 좌측
    __HAL_TIM_SET_COMPARE(&htim4, TIM_CHANNEL_2, pwm); // 우측
}

void Motor_Backward(uint16_t pwm) {
    HAL_GPIO_WritePin(MOTOR_GPIO, L298N_IN1_PIN | L298N_IN3_PIN, GPIO_PIN_RESET);
    HAL_GPIO_WritePin(MOTOR_GPIO, L298N_IN2_PIN | L298N_IN4_PIN, GPIO_PIN_SET);
    __HAL_TIM_SET_COMPARE(&htim4, TIM_CHANNEL_1, pwm);
    __HAL_TIM_SET_COMPARE(&htim4, TIM_CHANNEL_2, pwm);
}

void Motor_Turn_Left_Spot(uint16_t pwm) {
    HAL_GPIO_WritePin(MOTOR_GPIO, L298N_IN1_PIN | L298N_IN4_PIN, GPIO_PIN_SET);
    HAL_GPIO_WritePin(MOTOR_GPIO, L298N_IN2_PIN | L298N_IN3_PIN, GPIO_PIN_RESET);
    __HAL_TIM_SET_COMPARE(&htim4, TIM_CHANNEL_1, pwm);
    __HAL_TIM_SET_COMPARE(&htim4, TIM_CHANNEL_2, pwm);
}

void Motor_Turn_Right_Spot(uint16_t pwm) {
    HAL_GPIO_WritePin(MOTOR_GPIO, L298N_IN2_PIN | L298N_IN3_PIN, GPIO_PIN_SET);
    HAL_GPIO_WritePin(MOTOR_GPIO, L298N_IN1_PIN | L298N_IN4_PIN, GPIO_PIN_RESET);
    __HAL_TIM_SET_COMPARE(&htim4, TIM_CHANNEL_1, pwm);
    __HAL_TIM_SET_COMPARE(&htim4, TIM_CHANNEL_2, pwm);
}

void Motor_Steer(uint16_t left_pwm, uint16_t right_pwm) {
    HAL_GPIO_WritePin(MOTOR_GPIO, L298N_IN1_PIN | L298N_IN3_PIN, GPIO_PIN_SET);
    HAL_GPIO_WritePin(MOTOR_GPIO, L298N_IN2_PIN | L298N_IN4_PIN, GPIO_PIN_RESET);
    __HAL_TIM_SET_COMPARE(&htim4, TIM_CHANNEL_1, left_pwm);
    __HAL_TIM_SET_COMPARE(&htim4, TIM_CHANNEL_2, right_pwm);
}
