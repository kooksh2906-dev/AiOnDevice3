#include "cpu_polling_engine.h"

#include <assert.h>
#include <stdio.h>

static cpu_poll_trigger_config_t config(cpu_poll_trigger_mode_t mode)
{
    cpu_poll_trigger_config_t result = {
        .mode = mode,
        .edge_channel = 0u,
        .pattern = 0xa0u,
        .mask = 0xf0u,
    };
    return result;
}

static void prefill(cpu_poll_capture_t *capture, uint8_t value)
{
    for (unsigned i = 0; i < CPU_POLL_PRE_COUNT; ++i) {
        assert(!cpu_poll_capture_observe(capture, value));
    }
    assert(cpu_poll_capture_is_armed(capture));
}

static void test_rising_capture_layout(void)
{
    const cpu_poll_trigger_config_t cfg = config(CPU_POLL_TRIGGER_RISING);
    cpu_poll_capture_t capture;

    cpu_poll_capture_init(&capture, &cfg);
    prefill(&capture, 0x00u);

    assert(!cpu_poll_capture_observe(&capture, 0x00u));
    for (unsigned i = 0; i < 600u; ++i) {
        assert(!cpu_poll_capture_observe(&capture, 0x00u));
    }
    assert(cpu_poll_capture_observe(&capture, 0x01u));
    assert(capture.trigger.trigger_count == 1u);

    for (unsigned i = 0; i < CPU_POLL_POST_AFTER; ++i) {
        assert(!cpu_poll_capture_observe(&capture, 0x02u));
    }

    assert(cpu_poll_capture_is_done(&capture));
    for (unsigned i = 0; i < CPU_POLL_TRIGGER_INDEX; ++i) {
        assert(cpu_poll_capture_logical_sample(&capture, (uint16_t)i) == 0x00u);
    }
    assert(cpu_poll_capture_logical_sample(&capture, CPU_POLL_TRIGGER_INDEX) ==
           0x01u);
    for (unsigned i = CPU_POLL_TRIGGER_INDEX + 1u;
         i < CPU_POLL_CAPTURE_DEPTH; ++i) {
        assert(cpu_poll_capture_logical_sample(&capture, (uint16_t)i) == 0x02u);
    }
}

static void test_first_edge_observation_is_baseline(void)
{
    const cpu_poll_trigger_config_t cfg = config(CPU_POLL_TRIGGER_RISING);
    cpu_poll_capture_t capture;

    cpu_poll_capture_init(&capture, &cfg);
    prefill(&capture, 0x00u);
    assert(!cpu_poll_capture_observe(&capture, 0x01u));
    assert(!capture.trigger.triggered);
    assert(!cpu_poll_capture_observe(&capture, 0x00u));
    assert(cpu_poll_capture_observe(&capture, 0x01u));
}

static void test_falling(void)
{
    const cpu_poll_trigger_config_t cfg = config(CPU_POLL_TRIGGER_FALLING);
    cpu_poll_capture_t capture;

    cpu_poll_capture_init(&capture, &cfg);
    prefill(&capture, 0xffu);
    assert(!cpu_poll_capture_observe(&capture, 0x01u));
    assert(cpu_poll_capture_observe(&capture, 0x00u));
}

static void test_pattern_entry_and_hold(void)
{
    const cpu_poll_trigger_config_t cfg = config(CPU_POLL_TRIGGER_PATTERN);
    cpu_poll_capture_t capture;

    cpu_poll_capture_init(&capture, &cfg);
    prefill(&capture, 0x95u);
    assert(cpu_poll_capture_observe(&capture, 0xa5u));
    assert(!cpu_poll_capture_observe(&capture, 0xa5u));
    assert(capture.trigger.trigger_count == 1u);
}

static void test_zero_mask_never_triggers(void)
{
    cpu_poll_trigger_config_t cfg = config(CPU_POLL_TRIGGER_PATTERN);
    cpu_poll_capture_t capture;

    cfg.mask = 0x00u;
    cpu_poll_capture_init(&capture, &cfg);
    prefill(&capture, 0x00u);
    for (unsigned i = 0; i < 2000u; ++i) {
        assert(!cpu_poll_capture_observe(&capture, 0xa5u));
    }
    assert(!capture.trigger.triggered);
    assert(cpu_poll_capture_is_armed(&capture));
}

int main(void)
{
    test_rising_capture_layout();
    test_first_edge_observation_is_baseline();
    test_falling();
    test_pattern_entry_and_hold();
    test_zero_mask_never_triggers();
    puts("cpu_polling_engine: all tests passed");
    return 0;
}
