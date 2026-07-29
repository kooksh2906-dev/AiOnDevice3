#include "cpu_polling_config.h"
#include "cpu_polling_engine.h"

#include "xil_io.h"
#include "xil_printf.h"
#include "xtmrctr_l.h"

#include <stdbool.h>
#include <stdint.h>

#define GPIO_DATA_OFFSET 0x00u
#define GPIO_TRI_OFFSET  0x04u
#define GPIO2_DATA_OFFSET 0x08u
#define GPIO2_TRI_OFFSET  0x0cu

#define TEST_CTRL_START_MASK (1u << 0)
#define TEST_CTRL_ID_SHIFT 1u
#define TEST_CTRL_PULSE_SHIFT 5u
#define TEST_CTRL_CLEAR_MASK (1u << 25)

#define TEST_STATUS_BUSY_MASK (1u << 0)
#define TEST_STATUS_DONE_MASK (1u << 1)

static cpu_poll_capture_t capture_work;

static void timer_start_from_zero(void)
{
    XTmrCtr_SetControlStatusReg(CPU_POLL_TIMER_BASEADDR, 0u, 0u);
    XTmrCtr_SetLoadReg(CPU_POLL_TIMER_BASEADDR, 0u, 0u);
    XTmrCtr_SetControlStatusReg(CPU_POLL_TIMER_BASEADDR, 0u, XTC_CSR_LOAD_MASK);
    XTmrCtr_SetControlStatusReg(CPU_POLL_TIMER_BASEADDR, 0u,
                               XTC_CSR_ENABLE_TMR_MASK);
}

static uint32_t timer_stop(void)
{
    const uint32_t ticks =
        XTmrCtr_GetTimerCounterReg(CPU_POLL_TIMER_BASEADDR, 0u);
    XTmrCtr_SetControlStatusReg(CPU_POLL_TIMER_BASEADDR, 0u, 0u);
    return ticks;
}

static void delay_ticks(uint32_t required_ticks)
{
    timer_start_from_zero();
    while (XTmrCtr_GetTimerCounterReg(CPU_POLL_TIMER_BASEADDR, 0u) <
           required_ticks) {
    }
    (void)timer_stop();
}

static uint8_t probe_read(void)
{
    return (uint8_t)(Xil_In32(CPU_POLL_PROBE_BASEADDR + GPIO_DATA_OFFSET) &
                     0xffu);
}

static void generator_clear(void)
{
    Xil_Out32(CPU_POLL_TEST_CTRL_BASEADDR + GPIO_DATA_OFFSET,
              TEST_CTRL_CLEAR_MASK);
    Xil_Out32(CPU_POLL_TEST_CTRL_BASEADDR + GPIO_DATA_OFFSET, 0u);
}

static bool generator_start(uint32_t test_id, uint32_t pulse_width_cycles)
{
    uint32_t control;

    if (test_id == CPU_POLL_TEST_ID_NOT_SET || test_id > 0x0fu ||
        pulse_width_cycles > 0x000fffffu) {
        xil_printf("ERROR=GENERATOR_TEST_ID_NOT_FROZEN\r\n");
        return false;
    }

    control = ((test_id & 0x0fu) << TEST_CTRL_ID_SHIFT) |
              ((pulse_width_cycles & 0x000fffffu) <<
               TEST_CTRL_PULSE_SHIFT);
    Xil_Out32(CPU_POLL_TEST_CTRL_BASEADDR + GPIO_DATA_OFFSET, control);
    Xil_Out32(CPU_POLL_TEST_CTRL_BASEADDR + GPIO_DATA_OFFSET,
              control | TEST_CTRL_START_MASK);
    Xil_Out32(CPU_POLL_TEST_CTRL_BASEADDR + GPIO_DATA_OFFSET, control);
    return true;
}

static uint32_t generator_status(void)
{
    return Xil_In32(CPU_POLL_TEST_CTRL_BASEADDR + GPIO2_DATA_OFFSET);
}

static bool wait_generator_done(void)
{
    bool done;

    timer_start_from_zero();
    do {
        done = (generator_status() & TEST_STATUS_DONE_MASK) != 0u;
    } while (!done &&
             XTmrCtr_GetTimerCounterReg(CPU_POLL_TIMER_BASEADDR, 0u) <
                 CPU_POLL_TIMEOUT_TICKS);
    (void)timer_stop();
    return done;
}

static cpu_poll_trigger_config_t trigger_config(cpu_poll_trigger_mode_t mode)
{
    cpu_poll_trigger_config_t config = {
        .mode = mode,
        .edge_channel = 0u,
        .pattern = 0xa0u,
        .mask = 0xf0u,
    };
    return config;
}

static const char *mode_name(cpu_poll_trigger_mode_t mode)
{
    switch (mode) {
    case CPU_POLL_TRIGGER_RISING:
        return "RISING";
    case CPU_POLL_TRIGGER_FALLING:
        return "FALLING";
    case CPU_POLL_TRIGGER_PATTERN:
        return "PATTERN";
    default:
        return "DISABLED";
    }
}

static bool benchmark_once(cpu_poll_trigger_mode_t mode, uint32_t trial,
                           uint32_t *observations_per_second_out)
{
    cpu_poll_trigger_config_t config = trigger_config(mode);
    cpu_poll_trigger_state_t trigger;
    uint16_t write_pos = 0u;
    bool fixed_zero = true;
    uint32_t elapsed_ticks;
    uint32_t observations_per_second;

    cpu_poll_trigger_init(&trigger, &config);
    cpu_poll_trigger_arm(&trigger);
    timer_start_from_zero();
    for (uint32_t i = 0u; i < CPU_POLL_BENCH_ITERATIONS; ++i) {
        const uint8_t sample = probe_read();
        ((volatile uint32_t *)capture_work.words)[write_pos] =
            (uint32_t)sample;
        (void)cpu_poll_trigger_observe(&trigger, sample);
        write_pos = (uint16_t)((write_pos + 1u) &
                               (CPU_POLL_CAPTURE_DEPTH - 1u));
    }
    elapsed_ticks = timer_stop();

    for (uint32_t i = 0u; i < CPU_POLL_CAPTURE_DEPTH; ++i) {
        if ((capture_work.words[i] & 0xffu) != 0u) {
            fixed_zero = false;
        }
    }

    observations_per_second = elapsed_ticks == 0u
                                  ? 0u
                                  : (uint32_t)(((uint64_t)
                                                    CPU_POLL_BENCH_ITERATIONS *
                                                CPU_POLL_TIMER_HZ) /
                                               elapsed_ticks);
    *observations_per_second_out = observations_per_second;
    xil_printf("BENCH,MODE=%s,TRIAL=%u,ITERATIONS=%u,"
               "ELAPSED_TICKS=%u,OBS_PER_SEC=%u,AVG_PERIOD_PS=%u,"
               "INPUT_ZERO=%u,"
               "TRIGGER_COUNT=%u\r\n",
               mode_name(mode), trial, CPU_POLL_BENCH_ITERATIONS,
               elapsed_ticks, observations_per_second,
               (uint32_t)(((uint64_t)elapsed_ticks * 10000u) /
                          CPU_POLL_BENCH_ITERATIONS),
               fixed_zero ? 1u : 0u, trigger.trigger_count);
    return fixed_zero && trigger.trigger_count == 0u;
}

static void run_benchmarks(void)
{
    const cpu_poll_trigger_mode_t modes[] = {
        CPU_POLL_TRIGGER_RISING,
        CPU_POLL_TRIGGER_FALLING,
        CPU_POLL_TRIGGER_PATTERN,
    };

    uint32_t representative = UINT32_MAX;
    bool all_modes_valid = true;

    generator_clear();
    delay_ticks(CPU_POLL_INTER_TRIAL_TICKS);
    xil_printf("BENCHMARK_BEGIN\r\n");
    for (unsigned mode_index = 0u;
         mode_index < sizeof(modes) / sizeof(modes[0]); ++mode_index) {
        uint64_t mode_sum = 0u;
        uint32_t valid_trials = 0u;
        for (uint32_t trial = 1u; trial <= 3u; ++trial) {
            uint32_t observations_per_second = 0u;
            if (!benchmark_once(modes[mode_index], trial,
                                &observations_per_second)) {
                xil_printf("BENCHMARK_INVALID=INPUT_OR_TRIGGER\r\n");
            } else {
                mode_sum += observations_per_second;
                valid_trials++;
            }
        }
        if (valid_trials == 3u) {
            const uint32_t mode_average =
                (uint32_t)(mode_sum / valid_trials);
            const uint32_t period_ps =
                mode_average == 0u
                    ? 0u
                    : (uint32_t)(1000000000000ull / mode_average);
            xil_printf("MODE_SUMMARY,MODE=%s,AVG_OBS_PER_SEC=%u,"
                       "AVG_PERIOD_PS=%u,VALID_TRIALS=3\r\n",
                       mode_name(modes[mode_index]), mode_average, period_ps);
            if (mode_average < representative) {
                representative = mode_average;
            }
        } else {
            all_modes_valid = false;
            xil_printf("MODE_SUMMARY,MODE=%s,STATUS=INVALID,"
                       "VALID_TRIALS=%u\r\n",
                       mode_name(modes[mode_index]), valid_trials);
        }
    }
    if (all_modes_valid && representative != UINT32_MAX) {
        xil_printf("REPRESENTATIVE_LOWEST_MODE_AVG_OBS_PER_SEC=%u\r\n",
                   representative);
    } else {
        xil_printf("REPRESENTATIVE_STATUS=INVALID\r\n");
    }
    xil_printf("BENCHMARK_END\r\n");
}

static void dump_capture(uint32_t elapsed_ticks)
{
    xil_printf("CPU_POLLING_REFERENCE\r\n");
    xil_printf("TIMER_HZ=%u\r\n", CPU_POLL_TIMER_HZ);
    xil_printf("OBSERVATIONS=%u\r\n", CPU_POLL_CAPTURE_DEPTH);
    xil_printf("TRIGGER_INDEX=%u\r\n", CPU_POLL_TRIGGER_INDEX);
    xil_printf("ELAPSED_TICKS=%u\r\n", elapsed_ticks);
    if (elapsed_ticks != 0u) {
        const uint32_t observations_per_second =
            (uint32_t)(((uint64_t)capture_work.observation_count *
                        CPU_POLL_TIMER_HZ) /
                       elapsed_ticks);
        xil_printf("OBS_PER_SEC=%u\r\n", observations_per_second);
    }
    for (uint16_t i = 0u; i < CPU_POLL_CAPTURE_DEPTH; ++i) {
        xil_printf("%04u: %02X%s\r\n", i,
                   cpu_poll_capture_logical_sample(&capture_work, i),
                   i == CPU_POLL_TRIGGER_INDEX ? "  <TRIGGER>" : "");
    }
    xil_printf("CAPTURE_END\r\n");
}

static bool run_generator_capture(const cpu_poll_trigger_config_t *config,
                                  uint32_t test_id,
                                  uint32_t pulse_width_cycles,
                                  bool dump_on_success,
                                  bool use_observation_limit)
{
    bool generator_started = false;
    uint32_t observations_after_start = 0u;
    uint64_t analyzer_ticks = 0u;
    uint32_t timeout_ticks = 0u;

    cpu_poll_capture_init(&capture_work, config);
    generator_clear();
    timer_start_from_zero();

    while (!cpu_poll_capture_is_done(&capture_work)) {
        const uint8_t sample = probe_read();
        (void)cpu_poll_capture_observe(&capture_work, sample);

        if (!generator_started && cpu_poll_capture_is_armed(&capture_work)) {
            analyzer_ticks += timer_stop();
            if (!generator_start(test_id, pulse_width_cycles)) {
                return false;
            }
            generator_started = true;
            timer_start_from_zero();
        } else if (generator_started) {
            observations_after_start++;
            timeout_ticks =
                XTmrCtr_GetTimerCounterReg(CPU_POLL_TIMER_BASEADDR, 0u);
            if (!capture_work.trigger.triggered &&
                (timeout_ticks >= CPU_POLL_TIMEOUT_TICKS ||
                 (use_observation_limit &&
                  observations_after_start >=
                      CPU_POLL_TIMEOUT_OBSERVATIONS))) {
                analyzer_ticks += timer_stop();
                xil_printf("CAPTURE_TIMEOUT,OBSERVATIONS=%u,"
                           "TRIGGER_COUNT=%u,GEN_STATUS=0x%08X\r\n",
                           capture_work.observation_count,
                           capture_work.trigger.trigger_count,
                           generator_status() &
                               (TEST_STATUS_BUSY_MASK |
                                TEST_STATUS_DONE_MASK));
                return false;
            }
        }
    }

    analyzer_ticks += timer_stop();
    xil_printf("CAPTURE_PASS,MODE=%s,TRIGGER_COUNT=%u,"
               "TOTAL_OBSERVATIONS=%u\r\n",
               mode_name(config->mode), capture_work.trigger.trigger_count,
               capture_work.observation_count);
    if (dump_on_success) {
        dump_capture((uint32_t)analyzer_ticks);
    }
    return capture_work.trigger.trigger_count == 1u;
}

static void run_zero_mask_test(void)
{
    cpu_poll_trigger_config_t config =
        trigger_config(CPU_POLL_TRIGGER_PATTERN);
    config.mask = 0x00u;

    xil_printf("P-05_BEGIN\r\n");
    if (CPU_POLL_TEST_ID_NO_TRIGGER == CPU_POLL_TEST_ID_NOT_SET) {
        xil_printf("P-05_NOT_RUN=GENERATOR_TEST_ID_NOT_FROZEN\r\n");
        return;
    }
    if (run_generator_capture(&config, CPU_POLL_TEST_ID_NO_TRIGGER, 0u, false,
                              true)) {
        xil_printf("P-05_FAIL=UNEXPECTED_TRIGGER\r\n");
    } else if (capture_work.trigger.trigger_count == 0u) {
        xil_printf("P-05_PASS=NO_TRIGGER\r\n");
    }
}

static void run_pulse_stress(void)
{
    static const uint32_t widths[] = {
        1u, 10u, 100u, 1000u, 10000u, 100000u,
    };
    const cpu_poll_trigger_config_t config =
        trigger_config(CPU_POLL_TRIGGER_RISING);

    if (CPU_POLL_TEST_ID_PULSE == CPU_POLL_TEST_ID_NOT_SET) {
        xil_printf("PULSE_STRESS_NOT_RUN=GENERATOR_TEST_ID_NOT_FROZEN\r\n");
        return;
    }

    xil_printf("PULSE_STRESS_BEGIN\r\n");
    for (unsigned width_index = 0u;
         width_index < sizeof(widths) / sizeof(widths[0]); ++width_index) {
        uint32_t detected = 0u;
        for (uint32_t trial = 0u; trial < 10u; ++trial) {
            const bool hit =
                run_generator_capture(&config, CPU_POLL_TEST_ID_PULSE,
                                      widths[width_index], false, false);
            if (!wait_generator_done()) {
                xil_printf("PULSE_TRIAL_INVALID=GENERATOR_DONE_TIMEOUT\r\n");
                xil_printf("PULSE_STRESS_ABORTED\r\n");
                return;
            }
            if (hit) {
                detected++;
            }
            delay_ticks(CPU_POLL_INTER_TRIAL_TICKS);
        }
        xil_printf("PULSE_WIDTH_CYCLES=%u,DETECTED=%u,TRIALS=10\r\n",
                   widths[width_index], detected);
    }
    xil_printf("PULSE_STRESS_END\r\n");
}

static void print_menu(void)
{
    xil_printf("\r\nCommands:\r\n");
    xil_printf("  b: three polling benchmarks per trigger mode\r\n");
    xil_printf("  r: P-01 rising capture and hex dump\r\n");
    xil_printf("  f: P-02 falling capture and hex dump\r\n");
    xil_printf("  p: P-03 pattern capture and hex dump\r\n");
    xil_printf("  h: P-04 pattern-hold capture and hex dump\r\n");
    xil_printf("  z: P-05 zero-mask timeout test\r\n");
    xil_printf("  s: short-pulse stress suite\r\n");
    xil_printf("  q: stop\r\n> ");
}

int main(void)
{
    Xil_Out32(CPU_POLL_TEST_CTRL_BASEADDR + GPIO_TRI_OFFSET, 0x00000000u);
    Xil_Out32(CPU_POLL_TEST_CTRL_BASEADDR + GPIO2_TRI_OFFSET, 0xffffffffu);
    Xil_Out32(CPU_POLL_PROBE_BASEADDR + GPIO_TRI_OFFSET, 0x000000ffu);
    generator_clear();

    xil_printf("\r\nCPU_POLLING_REFERENCE_READY\r\n");
    xil_printf("UART=9600,8-N-1\r\n");
    for (;;) {
        char command;
        cpu_poll_trigger_config_t config;

        print_menu();
        command = (char)inbyte();
        xil_printf("%c\r\n", command);

        if (command == 'q' || command == 'Q') {
            break;
        }
        if (command == 'b' || command == 'B') {
            run_benchmarks();
        } else if (command == 'r' || command == 'R') {
            config = trigger_config(CPU_POLL_TRIGGER_RISING);
            (void)run_generator_capture(&config, CPU_POLL_TEST_ID_RISING,
                                        0u, true, false);
        } else if (command == 'f' || command == 'F') {
            config = trigger_config(CPU_POLL_TRIGGER_FALLING);
            (void)run_generator_capture(&config, CPU_POLL_TEST_ID_FALLING,
                                        0u, true, false);
        } else if (command == 'p' || command == 'P') {
            config = trigger_config(CPU_POLL_TRIGGER_PATTERN);
            (void)run_generator_capture(&config, CPU_POLL_TEST_ID_PATTERN,
                                        0u, true, false);
        } else if (command == 'h' || command == 'H') {
            config = trigger_config(CPU_POLL_TRIGGER_PATTERN);
            (void)run_generator_capture(
                &config, CPU_POLL_TEST_ID_PATTERN_HOLD, 0u, true, false);
        } else if (command == 'z' || command == 'Z') {
            run_zero_mask_test();
        } else if (command == 's' || command == 'S') {
            run_pulse_stress();
        } else {
            xil_printf("UNKNOWN_COMMAND\r\n");
        }
    }
    xil_printf("CPU_POLLING_REFERENCE_STOPPED\r\n");
    return 0;
}
