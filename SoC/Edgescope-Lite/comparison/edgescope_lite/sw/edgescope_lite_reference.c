#include "edgescope_lite_config.h"
#include "logic_analyzer_regs.h"

#include "xil_io.h"
#include "xil_printf.h"
#include "xtmrctr_l.h"

#include <stdbool.h>
#include <stdint.h>

#define GPIO_DATA_OFFSET  0x00u
#define GPIO_TRI_OFFSET   0x04u
#define GPIO2_DATA_OFFSET 0x08u
#define GPIO2_TRI_OFFSET  0x0cu

#define GEN_START_MASK       (1u << 0)
#define GEN_ID_SHIFT         1u
#define GEN_PULSE_SHIFT      5u
#define GEN_CLEAR_MASK       (1u << 25)
#define GEN_STATUS_BUSY_MASK (1u << 0)
#define GEN_STATUS_DONE_MASK (1u << 1)

/* Sampler settings this reference programs.  _CODE goes into SAMPLER_REG_CONFIG
   and _FACTOR is the matching 1/2/4/8 divide factor reported over UART; keep the
   two in step when changing the sample rate. */
#define EDGESCOPE_DIVIDER_CODE   SAMPLER_DIVIDE_BY_1
#define EDGESCOPE_DIVIDER_FACTOR 1u
#define EDGESCOPE_CHANNEL_MASK   0xffu

typedef struct {
    uint32_t mode;
    uint32_t channel;
    uint32_t pattern;
    uint32_t mask;
} trigger_config_t;

typedef struct {
    uint32_t start_addr;
    uint32_t trigger_addr;
    uint32_t write_addr;
    uint32_t sample_count;
    uint32_t trigger_count_raw;
    uint32_t trigger_count_delta;
} capture_result_t;

static void timer_start(void)
{
    XTmrCtr_SetControlStatusReg(EDGESCOPE_TIMER_BASEADDR, 0u, 0u);
    XTmrCtr_SetLoadReg(EDGESCOPE_TIMER_BASEADDR, 0u, 0u);
    XTmrCtr_SetControlStatusReg(EDGESCOPE_TIMER_BASEADDR, 0u,
                               XTC_CSR_LOAD_MASK);
    XTmrCtr_SetControlStatusReg(EDGESCOPE_TIMER_BASEADDR, 0u,
                               XTC_CSR_ENABLE_TMR_MASK);
}

static uint32_t timer_value(void)
{
    return XTmrCtr_GetTimerCounterReg(EDGESCOPE_TIMER_BASEADDR, 0u);
}

static uint32_t timer_stop(void)
{
    const uint32_t value = timer_value();
    XTmrCtr_SetControlStatusReg(EDGESCOPE_TIMER_BASEADDR, 0u, 0u);
    return value;
}

static void delay_ticks(uint32_t ticks)
{
    timer_start();
    while (timer_value() < ticks) {
    }
    (void)timer_stop();
}

static uint32_t generator_status(void)
{
    return Xil_In32(EDGESCOPE_TEST_CTRL_BASEADDR + GPIO2_DATA_OFFSET);
}

static void generator_clear(void)
{
    Xil_Out32(EDGESCOPE_TEST_CTRL_BASEADDR + GPIO_DATA_OFFSET,
              GEN_CLEAR_MASK);
    Xil_Out32(EDGESCOPE_TEST_CTRL_BASEADDR + GPIO_DATA_OFFSET, 0u);
}

static bool generator_start(uint32_t test_id, uint32_t pulse_cycles)
{
    uint32_t control;
    if (test_id == 0u || test_id > 0x0fu ||
        pulse_cycles > 0x000fffffu) {
        return false;
    }
    control = (test_id << GEN_ID_SHIFT) |
              (pulse_cycles << GEN_PULSE_SHIFT);
    Xil_Out32(EDGESCOPE_TEST_CTRL_BASEADDR + GPIO_DATA_OFFSET, control);
    Xil_Out32(EDGESCOPE_TEST_CTRL_BASEADDR + GPIO_DATA_OFFSET,
              control | GEN_START_MASK);
    Xil_Out32(EDGESCOPE_TEST_CTRL_BASEADDR + GPIO_DATA_OFFSET, control);
    return true;
}

static bool wait_generator_done(uint32_t timeout_ticks)
{
    timer_start();
    while ((generator_status() & GEN_STATUS_DONE_MASK) == 0u &&
           timer_value() < timeout_ticks) {
    }
    (void)timer_stop();
    return (generator_status() & GEN_STATUS_DONE_MASK) != 0u;
}

static bool wait_register(uint32_t address, uint32_t mask,
                          uint32_t timeout_ticks)
{
    timer_start();
    while ((Xil_In32(address) & mask) != mask &&
           timer_value() < timeout_ticks) {
    }
    (void)timer_stop();
    return (Xil_In32(address) & mask) == mask;
}

static const char *mode_name(uint32_t mode)
{
    switch (mode) {
    case TRIGGER_MODE_RISING:
        return "RISING";
    case TRIGGER_MODE_FALLING:
        return "FALLING";
    case TRIGGER_MODE_PATTERN:
        return "PATTERN";
    default:
        return "DISABLED";
    }
}

static trigger_config_t config_for_mode(uint32_t mode)
{
    const trigger_config_t config = {
        .mode = mode,
        .channel = 0u,
        .pattern = 0xa0u,
        .mask = 0xf0u,
    };
    return config;
}

static void recover_capture(void)
{
    Xil_Out32(EDGESCOPE_SAMPLER_BASEADDR + SAMPLER_REG_CONTROL, 0u);
    Xil_Out32(EDGESCOPE_TRIGGER_BASEADDR + TRIGGER_REG_CONTROL,
              TRIGGER_CONTROL_CLEAR);
    Xil_Out32(EDGESCOPE_TRACE_BASEADDR + TRACE_REG_CONTROL,
              TRACE_CONTROL_ABORT);
}

static bool prepare_capture(const trigger_config_t *config,
                            uint32_t *trigger_count_before)
{
    uint32_t sampler_config;
    uint32_t trigger_config;
    uint32_t trigger_pattern;

    generator_clear();

    Xil_Out32(EDGESCOPE_SAMPLER_BASEADDR + SAMPLER_REG_CONTROL, 0u);
    Xil_Out32(EDGESCOPE_SAMPLER_BASEADDR + SAMPLER_REG_CONTROL,
              SAMPLER_CONTROL_SOFT_CLEAR);
    sampler_config =
        EDGESCOPE_DIVIDER_CODE |
        (EDGESCOPE_CHANNEL_MASK << SAMPLER_CONFIG_CHANNEL_SHIFT);
    Xil_Out32(EDGESCOPE_SAMPLER_BASEADDR + SAMPLER_REG_CONFIG,
              sampler_config);

    Xil_Out32(EDGESCOPE_TRIGGER_BASEADDR + TRIGGER_REG_CONTROL,
              TRIGGER_CONTROL_CLEAR);
    trigger_config =
        (config->mode & TRIGGER_CONFIG_MODE_MASK) |
        ((config->channel << TRIGGER_CONFIG_CHANNEL_SHIFT) &
         TRIGGER_CONFIG_CHANNEL_MASK);
    trigger_pattern =
        (config->pattern & TRIGGER_PATTERN_VALUE_MASK) |
        ((config->mask << TRIGGER_PATTERN_MASK_SHIFT) &
         TRIGGER_PATTERN_MASK_MASK);
    Xil_Out32(EDGESCOPE_TRIGGER_BASEADDR + TRIGGER_REG_CONFIG,
              trigger_config);
    Xil_Out32(EDGESCOPE_TRIGGER_BASEADDR + TRIGGER_REG_PATTERN,
              trigger_pattern);
    *trigger_count_before =
        Xil_In32(EDGESCOPE_TRIGGER_BASEADDR +
                 TRIGGER_REG_TRIGGER_COUNT);

    Xil_Out32(EDGESCOPE_TRACE_BASEADDR + TRACE_REG_CONTROL,
              TRACE_CONTROL_ABORT);
    Xil_Out32(EDGESCOPE_TRACE_BASEADDR + TRACE_REG_CONTROL,
              TRACE_CONTROL_ARM);
    Xil_Out32(EDGESCOPE_SAMPLER_BASEADDR + SAMPLER_REG_CONTROL,
              SAMPLER_CONTROL_ENABLE);

    if (!wait_register(EDGESCOPE_TRACE_BASEADDR + TRACE_REG_STATUS,
                       TRACE_STATUS_PRE_READY,
                       EDGESCOPE_TIMEOUT_TICKS)) {
        xil_printf("ERROR=PRE_READY_TIMEOUT\r\n");
        recover_capture();
        return false;
    }

    /* CLEAR and ARM must be separate writes: clear has priority in the RTL. */
    Xil_Out32(EDGESCOPE_TRIGGER_BASEADDR + TRIGGER_REG_CONTROL,
              TRIGGER_CONTROL_CLEAR);
    Xil_Out32(EDGESCOPE_TRIGGER_BASEADDR + TRIGGER_REG_CONTROL,
              TRIGGER_CONTROL_ARM);
    if (!wait_register(EDGESCOPE_TRIGGER_BASEADDR + TRIGGER_REG_STATUS,
                       TRIGGER_STATUS_ARMED, EDGESCOPE_TIMEOUT_TICKS)) {
        xil_printf("ERROR=TRIGGER_ARM_TIMEOUT\r\n");
        recover_capture();
        return false;
    }
    return true;
}

static bool validate_capture(capture_result_t *result,
                             uint32_t trigger_count_before)
{
    const uint32_t info =
        Xil_In32(EDGESCOPE_TRACE_BASEADDR + TRACE_REG_CAPTURE_INFO);
    const uint32_t depth = info & TRACE_CAPTURE_INFO_DEPTH_MASK;
    const uint32_t trigger_index =
        (info & TRACE_CAPTURE_INFO_TRIG_MASK) >>
        TRACE_CAPTURE_INFO_TRIG_SHIFT;
    bool words_valid = true;

    result->start_addr =
        Xil_In32(EDGESCOPE_TRACE_BASEADDR + TRACE_REG_START_ADDR) &
        TRACE_ADDR_MASK;
    result->trigger_addr =
        Xil_In32(EDGESCOPE_TRACE_BASEADDR + TRACE_REG_TRIGGER_ADDR) &
        TRACE_ADDR_MASK;
    result->write_addr =
        Xil_In32(EDGESCOPE_TRACE_BASEADDR + TRACE_REG_WRITE_ADDR) &
        TRACE_ADDR_MASK;
    result->sample_count =
        Xil_In32(EDGESCOPE_SAMPLER_BASEADDR +
                 SAMPLER_REG_SAMPLE_COUNT);
    result->trigger_count_raw =
        Xil_In32(EDGESCOPE_TRIGGER_BASEADDR +
                 TRIGGER_REG_TRIGGER_COUNT);
    result->trigger_count_delta =
        result->trigger_count_raw - trigger_count_before;

    for (uint32_t i = 0u; i < EDGE_SCOPE_CAPTURE_DEPTH; ++i) {
        const uint32_t word =
            Xil_In32(EDGESCOPE_BRAM_BASEADDR + i * sizeof(uint32_t));
        if ((word & 0xffffff00u) != 0u) {
            words_valid = false;
        }
    }

    if (depth != EDGE_SCOPE_CAPTURE_DEPTH ||
        trigger_index != EDGE_SCOPE_TRIGGER_INDEX ||
        ((result->start_addr + EDGE_SCOPE_TRIGGER_INDEX) &
         TRACE_ADDR_MASK) != result->trigger_addr ||
        ((result->start_addr + EDGE_SCOPE_CAPTURE_DEPTH - 1u) &
         TRACE_ADDR_MASK) != result->write_addr ||
        result->trigger_count_delta != 1u ||
        !words_valid) {
        xil_printf("CAPTURE_INVARIANT_FAIL,DEPTH=%u,TRIGGER_INDEX=%u,"
                   "START_ADDR=%u,TRIGGER_ADDR=%u,WRITE_ADDR=%u,"
                   "TRIGGER_DELTA=%u,WORDS_VALID=%u\r\n",
                   depth, trigger_index, result->start_addr,
                   result->trigger_addr, result->write_addr,
                   result->trigger_count_delta, words_valid ? 1u : 0u);
        return false;
    }
    return true;
}

static void dump_capture(const trigger_config_t *config,
                         const capture_result_t *result)
{
    xil_printf("EDGESCOPE_LITE_REFERENCE\r\n");
    xil_printf("SAMPLE_HZ=%u\r\n", EDGESCOPE_CLOCK_HZ);
    xil_printf("OBS_PER_SEC=%u\r\n", EDGESCOPE_CLOCK_HZ);
    xil_printf("OBSERVATIONS=%u\r\n", EDGE_SCOPE_CAPTURE_DEPTH);
    xil_printf("TRIGGER_INDEX=%u\r\n", EDGE_SCOPE_TRIGGER_INDEX);
    xil_printf("START_ADDR=%u\r\n", result->start_addr);
    xil_printf("TRIGGER_ADDR=%u\r\n", result->trigger_addr);
    xil_printf("WRITE_ADDR=%u\r\n", result->write_addr);
    xil_printf("SAMPLE_COUNT=%u\r\n", result->sample_count);
    /* Report the settings actually programmed into the sampler and trigger so
       the GUI can display them as measured instead of assuming the frozen
       firmware profile.  SAMPLE_DIVIDER is the divide factor (1/2/4/8), not
       the raw SAMPLER_CONFIG_DIVIDER_MASK code. */
    xil_printf("SAMPLE_DIVIDER=%u\r\n", EDGESCOPE_DIVIDER_FACTOR);
    xil_printf("CHANNEL_MASK=%u\r\n", EDGESCOPE_CHANNEL_MASK);
    xil_printf("TRIGGER_CHANNEL=%u\r\n", config->channel);
    xil_printf("PATTERN_VALUE=%u\r\n", config->pattern);
    xil_printf("PATTERN_MASK=%u\r\n", config->mask);
    for (uint32_t i = 0u; i < EDGE_SCOPE_CAPTURE_DEPTH; ++i) {
        const uint32_t physical =
            (result->start_addr + i) & TRACE_ADDR_MASK;
        const uint8_t sample = (uint8_t)(
            Xil_In32(EDGESCOPE_BRAM_BASEADDR +
                     physical * sizeof(uint32_t)) & 0xffu);
        xil_printf("%04u: %02X%s\r\n", i, sample,
                   i == EDGE_SCOPE_TRIGGER_INDEX
                       ? "  <TRIGGER>" : "");
    }
    xil_printf("CAPTURE_END\r\n");
}

static bool run_capture(const trigger_config_t *config, uint32_t test_id,
                        uint32_t pulse_cycles, bool dump_on_success)
{
    uint32_t trigger_count_before;
    capture_result_t result;

    if (!prepare_capture(config, &trigger_count_before)) {
        return false;
    }
    if (!generator_start(test_id, pulse_cycles)) {
        xil_printf("ERROR=GENERATOR_START_REJECTED\r\n");
        recover_capture();
        return false;
    }
    if (!wait_register(EDGESCOPE_TRACE_BASEADDR + TRACE_REG_STATUS,
                       TRACE_STATUS_DONE, EDGESCOPE_TIMEOUT_TICKS)) {
        xil_printf("CAPTURE_TIMEOUT,ANALYZER=EDGE_SCOPE_LITE,"
                   "TRIGGER_STATUS=0x%08X,TRACE_STATUS=0x%08X,"
                   "GEN_STATUS=0x%08X\r\n",
                   Xil_In32(EDGESCOPE_TRIGGER_BASEADDR +
                            TRIGGER_REG_STATUS),
                   Xil_In32(EDGESCOPE_TRACE_BASEADDR + TRACE_REG_STATUS),
                   generator_status());
        recover_capture();
        return false;
    }
    Xil_Out32(EDGESCOPE_SAMPLER_BASEADDR + SAMPLER_REG_CONTROL, 0u);

    if (!validate_capture(&result, trigger_count_before)) {
        return false;
    }
    xil_printf("CAPTURE_PASS,ANALYZER=EDGE_SCOPE_LITE,MODE=%s,"
               "TRIGGER_COUNT=%u,TRIGGER_COUNT_RAW=%u,"
               "TOTAL_SAMPLES=%u\r\n",
               mode_name(config->mode), result.trigger_count_delta,
               result.trigger_count_raw, result.sample_count);
    if (dump_on_success) {
        dump_capture(config, &result);
    }
    return true;
}

static void run_hardware_benchmark(void)
{
    static const char *const modes[] = {
        "RISING", "FALLING", "PATTERN",
    };
    xil_printf("BENCHMARK_BEGIN\r\n");
    for (unsigned i = 0u; i < 3u; ++i) {
        xil_printf("MODE_SUMMARY,ANALYZER=EDGE_SCOPE_LITE,MODE=%s,"
                   "AVG_OBS_PER_SEC=%u,AVG_PERIOD_PS=10000,"
                   "VALID_TRIALS=HARDWARE_CLOCK\r\n",
                   modes[i], EDGESCOPE_CLOCK_HZ);
    }
    xil_printf("REPRESENTATIVE_LOWEST_MODE_AVG_OBS_PER_SEC=%u\r\n",
               EDGESCOPE_CLOCK_HZ);
    xil_printf("BENCHMARK_END\r\n");
}

static void run_zero_mask(void)
{
    trigger_config_t config = config_for_mode(TRIGGER_MODE_PATTERN);
    uint32_t trigger_count_before;
    uint32_t trigger_count_after;

    config.mask = 0u;
    xil_printf("P-05_BEGIN\r\n");
    if (!prepare_capture(&config, &trigger_count_before)) {
        xil_printf("P-05_FAIL=PREPARE\r\n");
        return;
    }
    if (!generator_start(EDGESCOPE_TEST_NO_TRIGGER, 0u) ||
        !wait_generator_done(EDGESCOPE_TIMEOUT_TICKS)) {
        xil_printf("P-05_FAIL=GENERATOR_TIMEOUT\r\n");
        recover_capture();
        return;
    }
    trigger_count_after =
        Xil_In32(EDGESCOPE_TRIGGER_BASEADDR +
                 TRIGGER_REG_TRIGGER_COUNT);
    if ((Xil_In32(EDGESCOPE_TRIGGER_BASEADDR + TRIGGER_REG_STATUS) &
         TRIGGER_STATUS_TRIGGERED) == 0u &&
        (Xil_In32(EDGESCOPE_TRACE_BASEADDR + TRACE_REG_STATUS) &
         TRACE_STATUS_DONE) == 0u &&
        trigger_count_after == trigger_count_before) {
        xil_printf("P-05_PASS=NO_TRIGGER\r\n");
    } else {
        xil_printf("P-05_FAIL=UNEXPECTED_TRIGGER\r\n");
    }
    recover_capture();
}

static void run_pulse_stress(void)
{
    static const uint32_t widths[] = {
        1u, 10u, 100u, 1000u, 10000u, 100000u,
    };
    const trigger_config_t config =
        config_for_mode(TRIGGER_MODE_RISING);

    xil_printf("PULSE_STRESS_BEGIN\r\n");
    for (unsigned width_index = 0u;
         width_index < sizeof(widths) / sizeof(widths[0]);
         ++width_index) {
        uint32_t detected = 0u;
        for (uint32_t trial = 0u; trial < 10u; ++trial) {
            if (run_capture(&config, EDGESCOPE_TEST_PULSE,
                            widths[width_index], false)) {
                detected++;
            }
            if (!wait_generator_done(EDGESCOPE_TIMEOUT_TICKS)) {
                xil_printf("PULSE_STRESS_ABORTED=GENERATOR_TIMEOUT\r\n");
                return;
            }
            delay_ticks(EDGESCOPE_INTER_TRIAL_TICKS);
        }
        xil_printf("PULSE_WIDTH_CYCLES=%u,DETECTED=%u,TRIALS=10\r\n",
                   widths[width_index], detected);
    }
    xil_printf("PULSE_STRESS_END\r\n");
}

static void print_menu(void)
{
    xil_printf("\r\nCommands:\r\n");
    xil_printf("  b: hardware sample-rate summary\r\n");
    xil_printf("  r: rising capture and waveform dump\r\n");
    xil_printf("  f: falling capture and waveform dump\r\n");
    xil_printf("  p: masked-pattern capture and waveform dump\r\n");
    xil_printf("  h: pattern-hold capture and waveform dump\r\n");
    xil_printf("  z: zero-mask no-trigger test\r\n");
    xil_printf("  s: hardware pulse stress suite\r\n");
    xil_printf("  q: stop\r\n> ");
}

int main(void)
{
    Xil_Out32(EDGESCOPE_TEST_CTRL_BASEADDR + GPIO_TRI_OFFSET, 0u);
    Xil_Out32(EDGESCOPE_TEST_CTRL_BASEADDR + GPIO2_TRI_OFFSET,
              0xffffffffu);
    generator_clear();
    recover_capture();

    xil_printf("\r\nEDGESCOPE_LITE_REFERENCE_READY\r\n");
    xil_printf("ANALYZER=EDGE_SCOPE_LITE\r\n");
    xil_printf("UART=9600,8-N-1\r\n");
    xil_printf("SAMPLE_HZ=%u\r\n", EDGESCOPE_CLOCK_HZ);

    for (;;) {
        char command;
        trigger_config_t config;
        print_menu();
        command = (char)inbyte();
        xil_printf("%c\r\n", command);

        if (command == 'q' || command == 'Q') {
            break;
        } else if (command == 'b' || command == 'B') {
            run_hardware_benchmark();
        } else if (command == 'r' || command == 'R') {
            config = config_for_mode(TRIGGER_MODE_RISING);
            (void)run_capture(&config, EDGESCOPE_TEST_RISING, 0u, true);
        } else if (command == 'f' || command == 'F') {
            config = config_for_mode(TRIGGER_MODE_FALLING);
            (void)run_capture(&config, EDGESCOPE_TEST_FALLING, 0u, true);
        } else if (command == 'p' || command == 'P') {
            config = config_for_mode(TRIGGER_MODE_PATTERN);
            (void)run_capture(&config, EDGESCOPE_TEST_PATTERN, 0u, true);
        } else if (command == 'h' || command == 'H') {
            config = config_for_mode(TRIGGER_MODE_PATTERN);
            (void)run_capture(&config, EDGESCOPE_TEST_PATTERN_HOLD,
                              0u, true);
        } else if (command == 'z' || command == 'Z') {
            run_zero_mask();
        } else if (command == 's' || command == 'S') {
            run_pulse_stress();
        } else {
            xil_printf("UNKNOWN_COMMAND\r\n");
        }
    }
    recover_capture();
    xil_printf("EDGESCOPE_LITE_REFERENCE_STOPPED\r\n");
    return 0;
}
