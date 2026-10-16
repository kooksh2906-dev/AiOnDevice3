#include "motor_control.h"

#include "main.h"
#include "tim.h"

static void MotorSetForwardDirection(void);
static void MotorSetBackwardDirection(void);
static void MotorSetLeftDirection(void);
static void MotorSetRightDirection(void);
static void MotorSetStopDirection(void);
static void MotorSetPwm(uint16_t left_pwm, uint16_t right_pwm);

void MotorControl_Start(void)
{
    (void)HAL_TIM_PWM_Start(&htim3, TIM_CHANNEL_1);
    (void)HAL_TIM_PWM_Start(&htim3, TIM_CHANNEL_2);
}

uint8_t MotorControl_Apply(const MotorControlState *motion)
{
    if (motion == NULL) {
        return 0U;
    }

    switch ((MotorAction)motion->action) {
    case MOTOR_ACTION_STOP:
        MotorSetStopDirection();
        MotorSetPwm(0U, 0U);
        break;
    case MOTOR_ACTION_FORWARD:
        MotorSetForwardDirection();
        MotorSetPwm(motion->left_pwm, motion->right_pwm);
        break;
    case MOTOR_ACTION_BACKWARD:
        MotorSetBackwardDirection();
        MotorSetPwm(motion->left_pwm, motion->right_pwm);
        break;
    case MOTOR_ACTION_TURN_LEFT:
        MotorSetLeftDirection();
        MotorSetPwm(motion->left_pwm, motion->right_pwm);
        break;
    case MOTOR_ACTION_TURN_RIGHT:
        MotorSetRightDirection();
        MotorSetPwm(motion->left_pwm, motion->right_pwm);
        break;
    default:
        return 0U;
    }

    return 1U;
}

static void MotorSetForwardDirection(void)
{
    HAL_GPIO_WritePin(IN1_GPIO_Port, IN1_Pin, GPIO_PIN_SET);
    HAL_GPIO_WritePin(IN2_GPIO_Port, IN2_Pin, GPIO_PIN_RESET);
    HAL_GPIO_WritePin(IN3_GPIO_Port, IN3_Pin, GPIO_PIN_SET);
    HAL_GPIO_WritePin(IN4_GPIO_Port, IN4_Pin, GPIO_PIN_RESET);
}

static void MotorSetBackwardDirection(void)
{
    HAL_GPIO_WritePin(IN1_GPIO_Port, IN1_Pin, GPIO_PIN_RESET);
    HAL_GPIO_WritePin(IN2_GPIO_Port, IN2_Pin, GPIO_PIN_SET);
    HAL_GPIO_WritePin(IN3_GPIO_Port, IN3_Pin, GPIO_PIN_RESET);
    HAL_GPIO_WritePin(IN4_GPIO_Port, IN4_Pin, GPIO_PIN_SET);
}

static void MotorSetLeftDirection(void)
{
    HAL_GPIO_WritePin(IN1_GPIO_Port, IN1_Pin, GPIO_PIN_SET);
    HAL_GPIO_WritePin(IN2_GPIO_Port, IN2_Pin, GPIO_PIN_RESET);
    HAL_GPIO_WritePin(IN3_GPIO_Port, IN3_Pin, GPIO_PIN_RESET);
    HAL_GPIO_WritePin(IN4_GPIO_Port, IN4_Pin, GPIO_PIN_SET);
}

static void MotorSetRightDirection(void)
{
    HAL_GPIO_WritePin(IN1_GPIO_Port, IN1_Pin, GPIO_PIN_RESET);
    HAL_GPIO_WritePin(IN2_GPIO_Port, IN2_Pin, GPIO_PIN_SET);
    HAL_GPIO_WritePin(IN3_GPIO_Port, IN3_Pin, GPIO_PIN_SET);
    HAL_GPIO_WritePin(IN4_GPIO_Port, IN4_Pin, GPIO_PIN_RESET);
}

static void MotorSetStopDirection(void)
{
    HAL_GPIO_WritePin(IN1_GPIO_Port, IN1_Pin, GPIO_PIN_RESET);
    HAL_GPIO_WritePin(IN2_GPIO_Port, IN2_Pin, GPIO_PIN_RESET);
    HAL_GPIO_WritePin(IN3_GPIO_Port, IN3_Pin, GPIO_PIN_RESET);
    HAL_GPIO_WritePin(IN4_GPIO_Port, IN4_Pin, GPIO_PIN_RESET);
}

static void MotorSetPwm(uint16_t left_pwm, uint16_t right_pwm)
{
    __HAL_TIM_SET_COMPARE(&htim3, TIM_CHANNEL_1, left_pwm);
    __HAL_TIM_SET_COMPARE(&htim3, TIM_CHANNEL_2, right_pwm);
}
