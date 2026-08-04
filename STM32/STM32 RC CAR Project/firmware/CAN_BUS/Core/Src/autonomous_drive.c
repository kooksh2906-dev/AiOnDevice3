#include "autonomous_drive.h"

#include "can_app.h"
#include "cmsis_os2.h"
#include "motor_control.h"
#include "uart_log.h"
#include "ultrasonic.h"

#include <stdint.h>
#include <stdio.h>

#define SAFE_DIST                  35U
#define FRONT_BLOCK_CONFIRM_COUNT   3U
#define FRONT_CLEAR_CONFIRM_COUNT   3U
#define TURN_SPEED                 800U
#define TURN_GAP                    12U
#define REVERSE_DIST                12U
#define SIDE_BLOCKED_DIST           24U
#define SIDE_CENTER_DEADBAND         6U
#define SIDE_CORRECT_PWM            300U
#define REVERSE_HOLD_MS             160U
#define TURN_MIN_MS                 600U
#define TURN_MAX_MS                1200U
#define CORNER_COMMIT_MS             30U
#define COMMIT_SPEED                400U
#define FRONT_CLEAR_HYSTERESIS       12U
#define SENSOR_FALLBACK_DIST         70U
#define CAN_STATUS_PERIOD_MS        100U
#define CAN_SPEED_PWM_MAX           1000U

typedef enum {
    AVOID_CRUISE = 0,
    AVOID_REVERSING,
    AVOID_TURNING
} AvoidState;

volatile uint32_t front_invalid_total_count = 0U;
volatile uint32_t front_invalid_streak = 0U;

/* 0=none, 1=left, 2=right */
uint8_t turn_dir = 0U;

static uint32_t last_can_tx_tick = 0U;
static uint32_t last_print = 0U;

static uint8_t SelectTurnDirection(uint16_t left, uint16_t right);
static uint8_t PwmToSpeedPercent(uint16_t left_pwm, uint16_t right_pwm);
static CanDirection_t MotorActionToCanDirection(uint8_t action);
static void SendVehicleStatusOverCan(uint16_t front_distance,
                                     uint8_t front_valid);

void AutonomousDrive_Task(void *argument)
{
    (void)argument;
    AvoidState avoid_state = AVOID_CRUISE;
    uint32_t state_until = 0U;
    uint32_t turn_started = 0U;
    uint32_t commit_until = 0U;
    uint8_t front_block_count = 0U;
    uint8_t front_clear_count = 0U;
    uint16_t last_side[2] = {SENSOR_FALLBACK_DIST, SENSOR_FALLBACK_DIST};
    uint32_t last_side_tick[2] = {0U, 0U};
    uint8_t side_initialized[2] = {0U, 0U};

    osDelay(1000);

    for (;;) {
        uint16_t measured[3] = {0U, 0U, 0U};
        uint8_t valid[3] = {0U, 0U, 0U};

        HCSR04_BeginMeasurement(HCSR04_SENSOR_FRONT);
        osDelay(25U);

        HCSR04_BeginMeasurement(HCSR04_SENSOR_LEFT);
        osDelay(25U);

        HCSR04_BeginMeasurement(HCSR04_SENSOR_RIGHT);
        osDelay(25U);

        HCSR04_ReadSnapshot(measured, valid);

        if (valid[0] == 0U) {
            front_invalid_total_count++;
            front_invalid_streak++;
            front_block_count = 0U;
        } else {
            front_invalid_streak = 0U;
        }

        uint32_t can_now = HAL_GetTick();
        if ((can_now - last_can_tx_tick) >= CAN_STATUS_PERIOD_MS) {
            SendVehicleStatusOverCan(measured[0], valid[0]);
            last_can_tx_tick = can_now;
        }

        uint32_t measurement_tick = HAL_GetTick();
        for (uint8_t side = 0U; side < 2U; ++side) {
            uint8_t sensor = (uint8_t)(side + 1U);
            if (valid[sensor] != 0U) {
                if (side_initialized[side] != 0U) {
                    if (measured[sensor] <= 18U) {
                        last_side[side] = measured[sensor];
                    } else if (measured[sensor] < last_side[side]) {
                        last_side[side] =
                            (uint16_t)(((uint32_t)last_side[side] +
                                       ((uint32_t)measured[sensor] * 3U)) / 4U);
                    } else {
                        last_side[side] =
                            (uint16_t)(((uint32_t)last_side[side] +
                                       measured[sensor]) / 2U);
                    }
                } else {
                    last_side[side] = measured[sensor];
                    side_initialized[side] = 1U;
                }
                last_side_tick[side] = measurement_tick;
            }
        }

        uint16_t left = ((side_initialized[0] != 0U) &&
                         ((measurement_tick - last_side_tick[0]) <= 500U))
                      ? last_side[0] : SENSOR_FALLBACK_DIST;
        uint16_t right = ((side_initialized[1] != 0U) &&
                          ((measurement_tick - last_side_tick[1]) <= 500U))
                       ? last_side[1] : SENSOR_FALLBACK_DIST;

        if ((HAL_GetTick() - last_print) > 500U) {
            last_print = HAL_GetTick();
            char dbg[96];
            MotorControlState motor_state;
            MotorControl_GetState(&motor_state);
            int length = snprintf(dbg, sizeof(dbg),
                                  "F=%u L=%u R=%u FL=%u FR=%u V=%u%u%u T=%u S=%u A=%u\r\n",
                                  measured[0], measured[1], measured[2],
                                  left, right, valid[0], valid[1], valid[2],
                                  turn_dir, (uint8_t)avoid_state,
                                  motor_state.action);
            if (length > 0) {
                uint16_t tx_length = (length < (int)sizeof(dbg))
                                   ? (uint16_t)length
                                   : (uint16_t)(sizeof(dbg) - 1U);
                UartLog_Transmit((const uint8_t *)dbg, tx_length);
            }
        }

        if (MotorControl_IsAutoMode() != 1U) {
            avoid_state = AVOID_CRUISE;
            turn_dir = 0U;
            commit_until = 0U;
            front_block_count = 0U;
            front_clear_count = 0U;
            continue;
        }

        uint32_t now = HAL_GetTick();

        if (avoid_state == AVOID_REVERSING) {
            if ((int32_t)(now - state_until) < 0) {
                MotorControl_QueueAutoMotion(MOTOR_ACTION_BACKWARD, 700U, 700U);
                continue;
            }
            avoid_state = AVOID_TURNING;
            turn_started = now;
        }

        if (avoid_state == AVOID_TURNING) {
            uint32_t turn_elapsed = now - turn_started;
            if (turn_elapsed < TURN_MIN_MS) {
                MotorControl_QueueAutoMotion(
                    (turn_dir == 1U)
                    ? MOTOR_ACTION_TURN_LEFT
                    : MOTOR_ACTION_TURN_RIGHT,
                    TURN_SPEED,
                    TURN_SPEED);
                continue;
            }

            if (((valid[0] != 0U) &&
                 (measured[0] > (SAFE_DIST + FRONT_CLEAR_HYSTERESIS))) ||
                (turn_elapsed >= TURN_MAX_MS)) {
                if ((valid[0] != 0U) &&
                    (measured[0] <= REVERSE_DIST) &&
                    (left <= SIDE_BLOCKED_DIST) &&
                    (right <= SIDE_BLOCKED_DIST)) {
                    avoid_state = AVOID_REVERSING;
                    state_until = now + REVERSE_HOLD_MS;
                    MotorControl_QueueAutoMotion(MOTOR_ACTION_BACKWARD,
                                                 650U,
                                                 650U);
                    continue;
                }

                avoid_state = AVOID_CRUISE;
                commit_until = now + CORNER_COMMIT_MS;
                MotorControl_QueueAutoMotion(MOTOR_ACTION_FORWARD,
                                             COMMIT_SPEED,
                                             COMMIT_SPEED);
                continue;
            }

            MotorControl_QueueAutoMotion(
                (turn_dir == 1U)
                ? MOTOR_ACTION_TURN_LEFT
                : MOTOR_ACTION_TURN_RIGHT,
                TURN_SPEED,
                TURN_SPEED);
            continue;
        }

        if ((commit_until != 0U) &&
            ((int32_t)(now - commit_until) < 0)) {
            if ((valid[0] != 0U) &&
                (measured[0] <= REVERSE_DIST) &&
                (left <= SIDE_BLOCKED_DIST) &&
                (right <= SIDE_BLOCKED_DIST)) {
                commit_until = 0U;
                avoid_state = AVOID_REVERSING;
                state_until = now + REVERSE_HOLD_MS;
                MotorControl_QueueAutoMotion(MOTOR_ACTION_BACKWARD, 650U, 650U);
            } else {
                MotorControl_QueueAutoMotion(MOTOR_ACTION_FORWARD,
                                             COMMIT_SPEED,
                                             COMMIT_SPEED);
            }
            continue;
        }

        if (commit_until != 0U) {
            commit_until = 0U;
        }

        if (turn_dir != 0U) {
            if ((valid[0] != 0U) &&
                (measured[0] > (SAFE_DIST + FRONT_CLEAR_HYSTERESIS))) {
                if (front_clear_count < FRONT_CLEAR_CONFIRM_COUNT) {
                    front_clear_count++;
                }

                if (front_clear_count >= FRONT_CLEAR_CONFIRM_COUNT) {
                    turn_dir = 0U;
                    front_clear_count = 0U;
                }
            } else {
                front_clear_count = 0U;
            }
        }

        if ((valid[0] != 0U) &&
            (measured[0] <= SAFE_DIST)) {
            if (front_block_count < FRONT_BLOCK_CONFIRM_COUNT) {
                front_block_count++;
            }
        } else {
            front_block_count = 0U;
        }

        if (front_block_count >= FRONT_BLOCK_CONFIRM_COUNT) {
            front_block_count = 0U;

            if (turn_dir == 0U) {
                uint16_t turn_left =
                    (valid[1] != 0U)
                    ? measured[1]
                    : SENSOR_FALLBACK_DIST;
                uint16_t turn_right =
                    (valid[2] != 0U)
                    ? measured[2]
                    : SENSOR_FALLBACK_DIST;

                turn_dir = SelectTurnDirection(turn_left, turn_right);

                if (turn_dir == 0U) {
                    turn_dir = 2U;
                }
            }

            if ((valid[0] != 0U) &&
                (measured[0] <= REVERSE_DIST) &&
                (left <= SIDE_BLOCKED_DIST) &&
                (right <= SIDE_BLOCKED_DIST)) {
                avoid_state = AVOID_REVERSING;
                state_until = now + REVERSE_HOLD_MS;
                MotorControl_QueueAutoMotion(MOTOR_ACTION_BACKWARD, 650U, 650U);
            } else {
                avoid_state = AVOID_TURNING;
                turn_started = now;
                MotorControl_QueueAutoMotion(
                    (turn_dir == 1U)
                    ? MOTOR_ACTION_TURN_LEFT
                    : MOTOR_ACTION_TURN_RIGHT,
                    TURN_SPEED,
                    TURN_SPEED);
            }
        } else {
            uint16_t base_pwm = MotorControl_GetSpeed();
            uint16_t low_pwm =
                (base_pwm > SIDE_CORRECT_PWM)
                ? (uint16_t)(base_pwm - SIDE_CORRECT_PWM)
                : 0U;
            uint16_t high_pwm =
                (((uint32_t)base_pwm + SIDE_CORRECT_PWM) > CAN_SPEED_PWM_MAX)
                ? CAN_SPEED_PWM_MAX
                : (uint16_t)(base_pwm + SIDE_CORRECT_PWM);

            if ((valid[1] != 0U) &&
                (valid[2] != 0U) &&
                (((uint32_t)left + SIDE_CENTER_DEADBAND) <
                 (uint32_t)right)) {
                MotorControl_QueueAutoMotion(MOTOR_ACTION_FORWARD,
                                             high_pwm,
                                             low_pwm);
            } else if ((valid[1] != 0U) &&
                       (valid[2] != 0U) &&
                       (((uint32_t)right + SIDE_CENTER_DEADBAND) <
                        (uint32_t)left)) {
                MotorControl_QueueAutoMotion(MOTOR_ACTION_FORWARD,
                                             low_pwm,
                                             high_pwm);
            } else {
                MotorControl_QueueAutoMotion(MOTOR_ACTION_FORWARD,
                                             base_pwm,
                                             base_pwm);
            }
        }
    }
}

static uint8_t SelectTurnDirection(uint16_t left, uint16_t right)
{
    if (left > right) {
        return 1U;
    }

    if (right > left) {
        return 2U;
    }

    return 0U;
}

static uint8_t PwmToSpeedPercent(uint16_t left_pwm, uint16_t right_pwm)
{
    uint32_t avg_pwm = ((uint32_t)left_pwm + (uint32_t)right_pwm) / 2U;

    if (avg_pwm > CAN_SPEED_PWM_MAX) {
        avg_pwm = CAN_SPEED_PWM_MAX;
    }

    return (uint8_t)((avg_pwm * 100U) / CAN_SPEED_PWM_MAX);
}

static CanDirection_t MotorActionToCanDirection(uint8_t action)
{
    switch ((MotorAction)action) {
    case MOTOR_ACTION_STOP:
        return CAN_DIR_STOP;

    case MOTOR_ACTION_FORWARD:
        return CAN_DIR_FORWARD;

    case MOTOR_ACTION_BACKWARD:
        return CAN_DIR_BACK;

    case MOTOR_ACTION_TURN_LEFT:
        return CAN_DIR_LEFT;

    case MOTOR_ACTION_TURN_RIGHT:
        return CAN_DIR_RIGHT;

    default:
        return CAN_DIR_STOP;
    }
}

static void SendVehicleStatusOverCan(uint16_t front_distance,
                                     uint8_t front_valid)
{
    MotorControlState motor_state;
    MotorControl_GetState(&motor_state);

    CanVehicleStatus_t status = {
        .speed_percent = PwmToSpeedPercent(motor_state.left_pwm,
                                           motor_state.right_pwm),
        .direction = MotorActionToCanDirection(motor_state.action),
        .front_distance = (front_valid != 0U)
                        ? (uint8_t)((front_distance > 255U)
                                  ? 255U
                                  : front_distance)
                        : 255U,
        .alive_count = 0U
    };

    (void)CAN_App_SendVehicleStatus(&status);
}
