#include "cpu_polling_engine.h"

#include <string.h>

_Static_assert((CPU_POLL_CAPTURE_DEPTH & (CPU_POLL_CAPTURE_DEPTH - 1u)) == 0u,
               "capture depth must be a power of two");
_Static_assert(CPU_POLL_PRE_COUNT + 1u + CPU_POLL_POST_AFTER ==
                   CPU_POLL_CAPTURE_DEPTH,
               "pre/trigger/post counts must fill the capture");

static bool masked_match(uint8_t sample, uint8_t pattern, uint8_t mask)
{
    return mask != 0u && (uint8_t)(sample & mask) == (uint8_t)(pattern & mask);
}

void cpu_poll_trigger_init(cpu_poll_trigger_state_t *state,
                           const cpu_poll_trigger_config_t *config)
{
    memset(state, 0, sizeof(*state));
    state->config = *config;
}

void cpu_poll_trigger_arm(cpu_poll_trigger_state_t *state)
{
    state->previous_sample = 0u;
    state->previous_match = false;
    state->edge_baseline_valid = false;
    state->triggered = false;
    state->trigger_count = 0u;
}

bool cpu_poll_trigger_observe(cpu_poll_trigger_state_t *state,
                              uint8_t current_sample)
{
    bool fire = false;

    if (state->triggered || state->config.mode == CPU_POLL_TRIGGER_DISABLED) {
        return false;
    }

    if (state->config.mode == CPU_POLL_TRIGGER_PATTERN) {
        const bool current_match =
            masked_match(current_sample, state->config.pattern, state->config.mask);

        fire = current_match && !state->previous_match;
        state->previous_match = current_match;
    } else {
        const uint8_t channel = (uint8_t)(state->config.edge_channel & 0x07u);
        const bool previous_bit =
            ((state->previous_sample >> channel) & 0x01u) != 0u;
        const bool current_bit = ((current_sample >> channel) & 0x01u) != 0u;

        if (!state->edge_baseline_valid) {
            state->edge_baseline_valid = true;
        } else if (state->config.mode == CPU_POLL_TRIGGER_RISING) {
            fire = !previous_bit && current_bit;
        } else if (state->config.mode == CPU_POLL_TRIGGER_FALLING) {
            fire = previous_bit && !current_bit;
        }
        state->previous_sample = current_sample;
    }

    if (fire) {
        state->triggered = true;
        state->trigger_count = 1u;
    }
    return fire;
}

void cpu_poll_capture_init(cpu_poll_capture_t *capture,
                           const cpu_poll_trigger_config_t *config)
{
    memset(capture, 0, sizeof(*capture));
    cpu_poll_trigger_init(&capture->trigger, config);
    capture->phase = CPU_POLL_CAPTURE_PREFILL;
}

bool cpu_poll_capture_observe(cpu_poll_capture_t *capture, uint8_t sample)
{
    const uint16_t current_addr = capture->write_pos;
    bool triggered_now = false;

    if (capture->phase == CPU_POLL_CAPTURE_DONE) {
        return false;
    }

    capture->words[current_addr] = (uint32_t)sample;
    capture->write_pos =
        (uint16_t)((capture->write_pos + 1u) & (CPU_POLL_CAPTURE_DEPTH - 1u));
    capture->observation_count++;

    if (capture->phase == CPU_POLL_CAPTURE_PREFILL) {
        capture->prefill_count++;
        if (capture->prefill_count == CPU_POLL_PRE_COUNT) {
            cpu_poll_trigger_arm(&capture->trigger);
            capture->phase = CPU_POLL_CAPTURE_ARMED;
        }
        return false;
    }

    if (capture->phase == CPU_POLL_CAPTURE_ARMED) {
        triggered_now = cpu_poll_trigger_observe(&capture->trigger, sample);
        if (triggered_now) {
            capture->trigger_addr = current_addr;
            capture->post_remaining = CPU_POLL_POST_AFTER;
            capture->phase = CPU_POLL_CAPTURE_POST;
        }
        return triggered_now;
    }

    capture->post_remaining--;
    if (capture->post_remaining == 0u) {
        capture->start_addr = capture->write_pos;
        capture->phase = CPU_POLL_CAPTURE_DONE;
    }
    return false;
}

bool cpu_poll_capture_is_armed(const cpu_poll_capture_t *capture)
{
    return capture->phase == CPU_POLL_CAPTURE_ARMED;
}

bool cpu_poll_capture_is_done(const cpu_poll_capture_t *capture)
{
    return capture->phase == CPU_POLL_CAPTURE_DONE;
}

uint8_t cpu_poll_capture_logical_sample(const cpu_poll_capture_t *capture,
                                        uint16_t logical_index)
{
    const uint16_t physical =
        (uint16_t)((capture->start_addr + logical_index) &
                   (CPU_POLL_CAPTURE_DEPTH - 1u));
    return (uint8_t)(capture->words[physical] & 0xffu);
}
