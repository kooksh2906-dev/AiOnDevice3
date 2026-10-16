#include "manual_drive.h"

#include <stddef.h>

#define MANUAL_START_PWM      400U
#define MANUAL_MAX_PWM        1000U
#define MANUAL_PWM_STEP       50U
#define MANUAL_ACCEL_STEP_MS  500U
#define MANUAL_DECEL_STEP_MS  2000U

enum {
    MANUAL_DIR_NONE = 0,
    MANUAL_DIR_FORWARD,
    MANUAL_DIR_BACKWARD
};

static ManualDriveOutput NoMotion(void)
{
    ManualDriveOutput output = {0};
    return output;
}

static ManualDriveOutput Motion(uint8_t action, uint16_t pwm)
{
    ManualDriveOutput output = {
        .valid = 1U,
        .motion = {
            .action = action,
            .left_pwm = pwm,
            .right_pwm = pwm
        }
    };
    return output;
}

static uint8_t DriveAction(uint8_t direction)
{
    return (direction == MANUAL_DIR_FORWARD)
           ? MOTOR_ACTION_FORWARD
           : MOTOR_ACTION_BACKWARD;
}

void ManualDrive_Reset(ManualDriveState *state, uint32_t now)
{
    if (state == NULL) {
        return;
    }

    state->requested_direction = MANUAL_DIR_NONE;
    state->active_direction = MANUAL_DIR_NONE;
    state->throttle_pressed = 0U;
    state->pwm = 0U;
    state->last_accel_tick = now;
    state->last_decel_tick = now;
}

void ManualDrive_Init(ManualDriveState *state, uint32_t now)
{
    ManualDrive_Reset(state, now);
}

ManualDriveOutput ManualDrive_HandleCommand(ManualDriveState *state,
                                            uint8_t command,
                                            uint16_t turn_speed,
                                            uint32_t now)
{
    if (state == NULL) {
        return NoMotion();
    }

    switch (command) {
    case 'w':
    case 'F':
    case 's':
    case 'B': {
        uint8_t direction = ((command == 'w') || (command == 'F'))
                          ? MANUAL_DIR_FORWARD
                          : MANUAL_DIR_BACKWARD;
        ManualDriveOutput output = NoMotion();

        if ((state->active_direction != MANUAL_DIR_NONE) &&
            (state->active_direction != direction)) {
            state->pwm = 0U;
            state->active_direction = MANUAL_DIR_NONE;
            output = Motion(MOTOR_ACTION_STOP, 0U);
        }

        state->requested_direction = direction;
        if ((state->throttle_pressed == 0U) && (state->pwm == 0U)) {
            output = Motion(MOTOR_ACTION_STOP, 0U);
        }
        return output;
    }

    case 'a':
    case 'L':
        ManualDrive_Reset(state, now);
        return Motion(MOTOR_ACTION_TURN_LEFT, turn_speed);

    case 'd':
    case 'R':
        ManualDrive_Reset(state, now);
        return Motion(MOTOR_ACTION_TURN_RIGHT, turn_speed);

    case 'q':
        /* 기존 완만한 감속 명령. 즉시 정지는 Motor 태스크에서 S/r로 처리. */
        state->requested_direction = MANUAL_DIR_NONE;
        state->last_decel_tick = now;
        if ((state->active_direction == MANUAL_DIR_NONE) ||
            (state->pwm == 0U)) {
            return Motion(MOTOR_ACTION_STOP, 0U);
        }
        return NoMotion();

    case 'X':
        state->throttle_pressed = 1U;
        state->last_accel_tick = now;
        if (state->requested_direction != MANUAL_DIR_NONE) {
            state->active_direction = state->requested_direction;
            if (state->pwm < MANUAL_START_PWM) {
                state->pwm = MANUAL_START_PWM;
            }
            return Motion(DriveAction(state->active_direction), state->pwm);
        }
        return NoMotion();

    case 'x':
        state->throttle_pressed = 0U;
        state->last_decel_tick = now;
        return NoMotion();

    default:
        return NoMotion();
    }
}

ManualDriveOutput ManualDrive_Update(ManualDriveState *state, uint32_t now)
{
    if (state == NULL) {
        return NoMotion();
    }

    if ((state->throttle_pressed != 0U) &&
        (state->requested_direction != MANUAL_DIR_NONE)) {
        if ((state->active_direction != state->requested_direction) ||
            (state->pwm == 0U)) {
            state->active_direction = state->requested_direction;
            state->pwm = MANUAL_START_PWM;
            state->last_accel_tick = now;
        } else if ((now - state->last_accel_tick) >= MANUAL_ACCEL_STEP_MS) {
            state->last_accel_tick = now;
            if (state->pwm < MANUAL_MAX_PWM) {
                uint16_t next_pwm = (uint16_t)(state->pwm + MANUAL_PWM_STEP);
                state->pwm = (next_pwm > MANUAL_MAX_PWM)
                           ? MANUAL_MAX_PWM
                           : next_pwm;
            }
        }
        return Motion(DriveAction(state->active_direction), state->pwm);
    }

    if ((state->active_direction != MANUAL_DIR_NONE) && (state->pwm > 0U) &&
        ((now - state->last_decel_tick) >= MANUAL_DECEL_STEP_MS)) {
        state->last_decel_tick = now;
        state->pwm = (state->pwm > MANUAL_PWM_STEP)
                   ? (uint16_t)(state->pwm - MANUAL_PWM_STEP)
                   : 0U;
        if (state->pwm == 0U) {
            state->active_direction = MANUAL_DIR_NONE;
            return Motion(MOTOR_ACTION_STOP, 0U);
        }
        return Motion(DriveAction(state->active_direction), state->pwm);
    }

    return NoMotion();
}
