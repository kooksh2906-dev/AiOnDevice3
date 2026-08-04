#include "stepper.h"

/*
 * 1-2상 여자 방식(Half-Step) 모터 구동 패턴 배열입니다.
 * 스텝 모터가 부드럽고 정밀하게 회전할 수 있도록 8단계의 신호 패턴을 정의합니다.
 * 1은 전원 인가(HIGH), 0은 전원 차단(LOW)을 의미합니다.
 */
static const uint8_t HALF_STEP_SEQ[8][4] =          /* 1-2상 여자 방식 */
{
        {1, 0, 0, 1},
        {0, 0, 0, 1},
        {0, 0, 1, 1},
        {0, 0, 1, 0},
        {0, 1, 1, 0},
        {0, 1, 0, 0},
        {1, 1, 0, 0},
        {1, 0, 0, 0}

};

/*
 * 전달받은 인덱스(step)에 해당하는 배열 패턴을 모터 제어 핀(IN1 ~ IN4)에 실제로 출력하는 함수입니다.
 * 이 함수가 호출될 때마다 모터가 1스텝(한 칸)씩 움직이게 됩니다.
 */
void stepMotor(uint8_t step)
{
    HAL_GPIO_WritePin(IN1_GPIO_PORT, IN1_GPIO_PIN, HALF_STEP_SEQ[step][0]);
    HAL_GPIO_WritePin(IN2_GPIO_PORT, IN2_GPIO_PIN, HALF_STEP_SEQ[step][1]);
    HAL_GPIO_WritePin(IN3_GPIO_PORT, IN3_GPIO_PIN, HALF_STEP_SEQ[step][2]);
    HAL_GPIO_WritePin(IN4_GPIO_PORT, IN4_GPIO_PIN, HALF_STEP_SEQ[step][3]);
}

/*
 * 승강용 모터로 들어가는 모든 핀의 출력을 LOW(RESET)로 설정하여 전류를 완전히 차단하는 함수입니다.
 * 엘리베이터가 목적 층에 도착하여 멈춰있을 때, 모터에 불필요한 전류가 흘러 과열되는 것을 방지합니다.
 */
void motorStop(void)
{
    HAL_GPIO_WritePin(IN1_GPIO_PORT, IN1_GPIO_PIN, GPIO_PIN_RESET);
    HAL_GPIO_WritePin(IN2_GPIO_PORT, IN2_GPIO_PIN, GPIO_PIN_RESET);
    HAL_GPIO_WritePin(IN3_GPIO_PORT, IN3_GPIO_PIN, GPIO_PIN_RESET);
    HAL_GPIO_WritePin(IN4_GPIO_PORT, IN4_GPIO_PIN, GPIO_PIN_RESET);
}
