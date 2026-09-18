#ifndef CPU_POLLING_ENGINE_H
#define CPU_POLLING_ENGINE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define CPU_POLL_CAPTURE_DEPTH 1024u
#define CPU_POLL_TRIGGER_INDEX 512u
#define CPU_POLL_PRE_COUNT     512u
#define CPU_POLL_POST_AFTER    511u

typedef enum {
    CPU_POLL_TRIGGER_DISABLED = 0,
    CPU_POLL_TRIGGER_RISING = 1,
    CPU_POLL_TRIGGER_FALLING = 2,
    CPU_POLL_TRIGGER_PATTERN = 3
} cpu_poll_trigger_mode_t;

typedef struct {
    cpu_poll_trigger_mode_t mode;
    uint8_t edge_channel;
    uint8_t pattern;
    uint8_t mask;
} cpu_poll_trigger_config_t;

typedef struct {
    cpu_poll_trigger_config_t config;
    uint8_t previous_sample;
    bool previous_match;
    bool edge_baseline_valid;
    bool triggered;
    uint32_t trigger_count;
} cpu_poll_trigger_state_t;

typedef enum {
    CPU_POLL_CAPTURE_PREFILL = 0,
    CPU_POLL_CAPTURE_ARMED,
    CPU_POLL_CAPTURE_POST,
    CPU_POLL_CAPTURE_DONE
} cpu_poll_capture_phase_t;

typedef struct {
    uint32_t words[CPU_POLL_CAPTURE_DEPTH];
    cpu_poll_trigger_state_t trigger;
    cpu_poll_capture_phase_t phase;
    uint16_t write_pos;
    uint16_t prefill_count;
    uint16_t post_remaining;
    uint16_t start_addr;
    uint16_t trigger_addr;
    uint32_t observation_count;
} cpu_poll_capture_t;

void cpu_poll_trigger_init(cpu_poll_trigger_state_t *state,
                           const cpu_poll_trigger_config_t *config);
void cpu_poll_trigger_arm(cpu_poll_trigger_state_t *state);
bool cpu_poll_trigger_observe(cpu_poll_trigger_state_t *state,
                              uint8_t current_sample);

void cpu_poll_capture_init(cpu_poll_capture_t *capture,
                           const cpu_poll_trigger_config_t *config);
bool cpu_poll_capture_observe(cpu_poll_capture_t *capture, uint8_t sample);
bool cpu_poll_capture_is_armed(const cpu_poll_capture_t *capture);
bool cpu_poll_capture_is_done(const cpu_poll_capture_t *capture);
uint8_t cpu_poll_capture_logical_sample(const cpu_poll_capture_t *capture,
                                        uint16_t logical_index);

#endif
