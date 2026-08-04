#include "motor_control.h"

#include "main.h"
#include "tim.h"
#include "uart_log.h"

#define MANUAL_START_PWM      400U
#define MANUAL_MAX_PWM        1000U
#define MANUAL_PWM_STEP       50U
#define MANUAL_ACCEL_STEP_MS  500U
#define MANUAL_DECEL_STEP_MS  2000U
#define MOTOR_TASK_PERIOD_MS  20U

typedef enum {
    MANUAL_DIR_NONE = 0,
    MANUAL_DIR_FORWARD,
    MANUAL_DIR_BACKWARD
} ManualDirection;

static osMessageQueueId_t motor_queue;
static volatile uint8_t auto_mode = 0U;
static uint16_t auto_speed = 600U;
static volatile uint8_t current_motor_action = MOTOR_ACTION_STOP;
static volatile uint16_t current_left_pwm = 0U;
static volatile uint16_t current_right_pwm = 0U;

volatile uint32_t motor_msg_count = 0U;
volatile uint32_t motor_user_msg_count = 0U;
volatile uint32_t motor_auto_msg_count = 0U;
volatile uint8_t last_motor_cmd = 0U;

volatile osStatus_t last_motor_queue_put_status = osOK;
volatile osStatus_t last_motor_queue_get_status = osOK;

static void ApplyMotorAction(const MotorMessage *message);
static void MotorSetForwardDirection(void);
static void MotorSetBackwardDirection(void);
static void MotorSetLeftDirection(void);
static void MotorSetRightDirection(void);
static void MotorSetStopDirection(void);
static void MotorSetPwm(uint16_t left_pwm, uint16_t right_pwm);

void MotorControl_Init(osMessageQueueId_t motor_queue_handle)
{
    motor_queue = motor_queue_handle;
}

osStatus_t MotorControl_QueueUserCommand(uint8_t command)
{
    MotorMessage message = {
        .source = MOTOR_SOURCE_USER,
        .action = command,
        .left_pwm = 0U,
        .right_pwm = 0U
    };
    osStatus_t status;

    if (motor_queue == NULL) {
        return osErrorParameter;
    }

    status = osMessageQueuePut(motor_queue, &message, 0U, 0U);
    last_motor_queue_put_status = status;

    return status;
}

void MotorControl_Task(void *argument)
{
    (void)argument;
    osDelay(1000);

    (void)HAL_TIM_PWM_Start(&htim3, TIM_CHANNEL_1);
    (void)HAL_TIM_PWM_Start(&htim3, TIM_CHANNEL_2);

    MotorMessage motor_message = {
        .source = MOTOR_SOURCE_USER,
        .action = MOTOR_ACTION_STOP,
        .left_pwm = 0U,
        .right_pwm = 0U
    };

    /*
     * X button manual acceleration state.
     *
     * requested_direction is the currently requested F/B direction.
     * active_direction is the direction currently accelerating/decelerating.
     */
    ManualDirection requested_direction = MANUAL_DIR_NONE;
    ManualDirection active_direction = MANUAL_DIR_NONE;
    uint8_t x_pressed = 0U;
    uint16_t manual_pwm = 0U;
    uint32_t last_accel_tick = HAL_GetTick();
    uint32_t last_decel_tick = HAL_GetTick();

    ApplyMotorAction(&motor_message);

    for (;;) {
        MotorMessage received_message;
        osStatus_t get_status =
            osMessageQueueGet(motor_queue,
                              &received_message,
                              NULL,
                              MOTOR_TASK_PERIOD_MS);

        last_motor_queue_get_status = get_status;

        if (get_status == osOK) {
            motor_msg_count++;

            if (received_message.source == MOTOR_SOURCE_AUTO) {
                motor_auto_msg_count++;

                if (auto_mode == 1U) {
                    ApplyMotorAction(&received_message);
                }
            } else {
                uint8_t cmd = received_message.action;

                motor_user_msg_count++;
                last_motor_cmd = cmd;
                UartLog_Transmit(&cmd, 1U);

                switch (cmd) {
                case 'l':
                    auto_speed = 400U;
                    break;

                case 'm':
                    auto_speed = 600U;
                    break;

                case 'h':
                    auto_speed = 800U;
                    break;

                case 'w':
                case 'F':
                    auto_mode = 0U;

                    if ((active_direction != MANUAL_DIR_NONE) &&
                        (active_direction != MANUAL_DIR_FORWARD)) {
                        manual_pwm = 0U;
                        active_direction = MANUAL_DIR_NONE;

                        motor_message.action = MOTOR_ACTION_STOP;
                        motor_message.left_pwm = 0U;
                        motor_message.right_pwm = 0U;
                        ApplyMotorAction(&motor_message);
                    }

                    requested_direction = MANUAL_DIR_FORWARD;

                    if ((x_pressed == 0U) && (manual_pwm == 0U)) {
                        motor_message.action = MOTOR_ACTION_STOP;
                        motor_message.left_pwm = 0U;
                        motor_message.right_pwm = 0U;
                        ApplyMotorAction(&motor_message);
                    }
                    break;

                case 's':
                case 'B':
                    auto_mode = 0U;

                    if ((active_direction != MANUAL_DIR_NONE) &&
                        (active_direction != MANUAL_DIR_BACKWARD)) {
                        manual_pwm = 0U;
                        active_direction = MANUAL_DIR_NONE;

                        motor_message.action = MOTOR_ACTION_STOP;
                        motor_message.left_pwm = 0U;
                        motor_message.right_pwm = 0U;
                        ApplyMotorAction(&motor_message);
                    }

                    requested_direction = MANUAL_DIR_BACKWARD;

                    if ((x_pressed == 0U) && (manual_pwm == 0U)) {
                        motor_message.action = MOTOR_ACTION_STOP;
                        motor_message.left_pwm = 0U;
                        motor_message.right_pwm = 0U;
                        ApplyMotorAction(&motor_message);
                    }
                    break;

                case 'a':
                case 'L':
                    auto_mode = 0U;
                    requested_direction = MANUAL_DIR_NONE;
                    active_direction = MANUAL_DIR_NONE;
                    manual_pwm = 0U;

                    motor_message.action = MOTOR_ACTION_TURN_LEFT;
                    motor_message.left_pwm = auto_speed;
                    motor_message.right_pwm = auto_speed;
                    ApplyMotorAction(&motor_message);
                    break;

                case 'd':
                case 'R':
                    auto_mode = 0U;
                    requested_direction = MANUAL_DIR_NONE;
                    active_direction = MANUAL_DIR_NONE;
                    manual_pwm = 0U;

                    motor_message.action = MOTOR_ACTION_TURN_RIGHT;
                    motor_message.left_pwm = auto_speed;
                    motor_message.right_pwm = auto_speed;
                    ApplyMotorAction(&motor_message);
                    break;

                case 'q':
                case 'S':
                    if (auto_mode == 0U) {
                        requested_direction = MANUAL_DIR_NONE;
                        last_decel_tick = HAL_GetTick();

                        if ((active_direction == MANUAL_DIR_NONE) ||
                            (manual_pwm == 0U)) {
                            motor_message.action = MOTOR_ACTION_STOP;
                            motor_message.left_pwm = 0U;
                            motor_message.right_pwm = 0U;
                            ApplyMotorAction(&motor_message);
                        }
                    }
                    break;

                case 'X':
                    auto_mode = 0U;
                    x_pressed = 1U;
                    last_accel_tick = HAL_GetTick();

                    if (requested_direction != MANUAL_DIR_NONE) {
                        active_direction = requested_direction;

                        if (manual_pwm < MANUAL_START_PWM) {
                            manual_pwm = MANUAL_START_PWM;
                        }

                        motor_message.action =
                            (active_direction == MANUAL_DIR_FORWARD)
                            ? MOTOR_ACTION_FORWARD
                            : MOTOR_ACTION_BACKWARD;

                        motor_message.left_pwm = manual_pwm;
                        motor_message.right_pwm = manual_pwm;
                        ApplyMotorAction(&motor_message);
                    }
                    break;

                case 'x':
                    x_pressed = 0U;
                    last_decel_tick = HAL_GetTick();
                    break;

                case 't':
                    auto_mode = 1U;
                    x_pressed = 0U;
                    requested_direction = MANUAL_DIR_NONE;
                    active_direction = MANUAL_DIR_NONE;
                    manual_pwm = 0U;

                    motor_message.source = MOTOR_SOURCE_USER;
                    motor_message.action = MOTOR_ACTION_FORWARD;
                    motor_message.left_pwm = auto_speed;
                    motor_message.right_pwm = auto_speed;
                    ApplyMotorAction(&motor_message);
                    break;

                case 'r':
                    auto_mode = 0U;
                    x_pressed = 0U;
                    requested_direction = MANUAL_DIR_NONE;
                    active_direction = MANUAL_DIR_NONE;
                    manual_pwm = 0U;

                    motor_message.source = MOTOR_SOURCE_USER;
                    motor_message.action = MOTOR_ACTION_STOP;
                    motor_message.left_pwm = 0U;
                    motor_message.right_pwm = 0U;
                    ApplyMotorAction(&motor_message);
                    break;

                default:
                    break;
                }
            }
        }

        if ((auto_mode == 0U) &&
            (x_pressed != 0U) &&
            (requested_direction != MANUAL_DIR_NONE)) {
            uint32_t now = HAL_GetTick();

            if ((active_direction != requested_direction) ||
                (manual_pwm == 0U)) {
                active_direction = requested_direction;
                manual_pwm = MANUAL_START_PWM;
                last_accel_tick = now;
            } else if ((now - last_accel_tick) >= MANUAL_ACCEL_STEP_MS) {
                last_accel_tick = now;

                if (manual_pwm < MANUAL_MAX_PWM) {
                    uint16_t next_pwm =
                        (uint16_t)(manual_pwm + MANUAL_PWM_STEP);

                    manual_pwm =
                        (next_pwm > MANUAL_MAX_PWM)
                        ? MANUAL_MAX_PWM
                        : next_pwm;
                }
            }

            motor_message.source = MOTOR_SOURCE_USER;
            motor_message.action =
                (active_direction == MANUAL_DIR_FORWARD)
                ? MOTOR_ACTION_FORWARD
                : MOTOR_ACTION_BACKWARD;
            motor_message.left_pwm = manual_pwm;
            motor_message.right_pwm = manual_pwm;
            ApplyMotorAction(&motor_message);
        } else if ((auto_mode == 0U) &&
                   (active_direction != MANUAL_DIR_NONE) &&
                   (manual_pwm > 0U)) {
            uint32_t now = HAL_GetTick();

            if ((now - last_decel_tick) >= MANUAL_DECEL_STEP_MS) {
                last_decel_tick = now;

                if (manual_pwm > MANUAL_PWM_STEP) {
                    manual_pwm =
                        (uint16_t)(manual_pwm - MANUAL_PWM_STEP);
                } else {
                    manual_pwm = 0U;
                }

                if (manual_pwm == 0U) {
                    active_direction = MANUAL_DIR_NONE;

                    motor_message.source = MOTOR_SOURCE_USER;
                    motor_message.action = MOTOR_ACTION_STOP;
                    motor_message.left_pwm = 0U;
                    motor_message.right_pwm = 0U;
                    ApplyMotorAction(&motor_message);
                } else {
                    motor_message.source = MOTOR_SOURCE_USER;
                    motor_message.action =
                        (active_direction == MANUAL_DIR_FORWARD)
                        ? MOTOR_ACTION_FORWARD
                        : MOTOR_ACTION_BACKWARD;
                    motor_message.left_pwm = manual_pwm;
                    motor_message.right_pwm = manual_pwm;
                    ApplyMotorAction(&motor_message);
                }
            }
        }
    }
}

void MotorControl_QueueAutoMotion(MotorAction action,
                                  uint16_t left_pwm,
                                  uint16_t right_pwm)
{
    MotorMessage message = {
        .source = MOTOR_SOURCE_AUTO,
        .action = (uint8_t)action,
        .left_pwm = left_pwm,
        .right_pwm = right_pwm
    };

    (void)osMessageQueuePut(motor_queue, &message, 0U, 0U);
}

uint8_t MotorControl_IsAutoMode(void)
{
    return auto_mode;
}

uint16_t MotorControl_GetSpeed(void)
{
    return auto_speed;
}

void MotorControl_GetState(MotorControlState *out_state)
{
    if (out_state == NULL) {
        return;
    }

    out_state->action = current_motor_action;
    out_state->left_pwm = current_left_pwm;
    out_state->right_pwm = current_right_pwm;
}

static void ApplyMotorAction(const MotorMessage *message)
{
    if (message == NULL) {
        return;
    }

    current_motor_action = message->action;

    switch ((MotorAction)message->action) {
    case MOTOR_ACTION_STOP:
        MotorSetStopDirection();
        MotorSetPwm(0U, 0U);
        break;

    case MOTOR_ACTION_FORWARD:
        MotorSetForwardDirection();
        MotorSetPwm(message->left_pwm, message->right_pwm);
        break;

    case MOTOR_ACTION_BACKWARD:
        MotorSetBackwardDirection();
        MotorSetPwm(message->left_pwm, message->right_pwm);
        break;

    case MOTOR_ACTION_TURN_LEFT:
        MotorSetLeftDirection();
        MotorSetPwm(message->left_pwm, message->right_pwm);
        break;

    case MOTOR_ACTION_TURN_RIGHT:
        MotorSetRightDirection();
        MotorSetPwm(message->left_pwm, message->right_pwm);
        break;

    default:
        break;
    }

    current_left_pwm =
        (uint16_t)__HAL_TIM_GET_COMPARE(&htim3, TIM_CHANNEL_1);

    current_right_pwm =
        (uint16_t)__HAL_TIM_GET_COMPARE(&htim3, TIM_CHANNEL_2);
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
