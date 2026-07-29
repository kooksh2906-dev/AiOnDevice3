#include "vivado_ila_config.h"

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

typedef struct {
    char command;
    uint32_t test_id;
    uint32_t pulse_cycles;
    uint32_t expect_trigger;
    const char *mode;
    const char *condition;
} ila_trial_t;

static void timer_start(void)
{
    XTmrCtr_SetControlStatusReg(VIVADO_ILA_TIMER_BASEADDR, 0u, 0u);
    XTmrCtr_SetLoadReg(VIVADO_ILA_TIMER_BASEADDR, 0u, 0u);
    XTmrCtr_SetControlStatusReg(VIVADO_ILA_TIMER_BASEADDR, 0u,
                               XTC_CSR_LOAD_MASK);
    XTmrCtr_SetControlStatusReg(VIVADO_ILA_TIMER_BASEADDR, 0u,
                               XTC_CSR_ENABLE_TMR_MASK);
}

static uint32_t timer_value(void)
{
    return XTmrCtr_GetTimerCounterReg(VIVADO_ILA_TIMER_BASEADDR, 0u);
}

static uint32_t timer_stop(void)
{
    const uint32_t value = timer_value();
    XTmrCtr_SetControlStatusReg(VIVADO_ILA_TIMER_BASEADDR, 0u, 0u);
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
    return Xil_In32(VIVADO_ILA_TEST_CTRL_BASEADDR + GPIO2_DATA_OFFSET);
}

static bool generator_clear(void)
{
    Xil_Out32(VIVADO_ILA_TEST_CTRL_BASEADDR + GPIO_DATA_OFFSET,
              GEN_CLEAR_MASK);
    delay_ticks(VIVADO_ILA_CLEAR_WAIT_TICKS);
    Xil_Out32(VIVADO_ILA_TEST_CTRL_BASEADDR + GPIO_DATA_OFFSET, 0u);
    delay_ticks(VIVADO_ILA_CLEAR_WAIT_TICKS);
    return (generator_status() &
            (GEN_STATUS_BUSY_MASK | GEN_STATUS_DONE_MASK)) == 0u;
}

static bool generator_start(uint32_t test_id, uint32_t pulse_cycles)
{
    uint32_t control;

    if (test_id < VIVADO_ILA_TEST_RISING ||
        test_id > VIVADO_ILA_TEST_PULSE ||
        pulse_cycles > VIVADO_ILA_PULSE_MAX_CYCLES) {
        return false;
    }

    control = (test_id << GEN_ID_SHIFT) |
              (pulse_cycles << GEN_PULSE_SHIFT);
    Xil_Out32(VIVADO_ILA_TEST_CTRL_BASEADDR + GPIO_DATA_OFFSET, control);
    Xil_Out32(VIVADO_ILA_TEST_CTRL_BASEADDR + GPIO_DATA_OFFSET,
              control | GEN_START_MASK);
    Xil_Out32(VIVADO_ILA_TEST_CTRL_BASEADDR + GPIO_DATA_OFFSET, control);
    return true;
}

static bool wait_generator_done(uint32_t *elapsed_ticks)
{
    bool done;

    timer_start();
    do {
        done = (generator_status() & GEN_STATUS_DONE_MASK) != 0u;
    } while (!done && timer_value() < VIVADO_ILA_TIMEOUT_TICKS);
    *elapsed_ticks = timer_stop();
    return done;
}

static bool read_pulse_width(uint32_t *pulse_cycles)
{
    uint32_t value = 0u;
    bool have_digit = false;
    bool invalid = false;

    for (;;) {
        const char input = (char)inbyte();

        if (input == '\r' || input == '\n') {
            break;
        }
        if (!have_digit &&
            (input == ' ' || input == '\t' ||
             input == ':' || input == '=')) {
            continue;
        }
        if (input >= '0' && input <= '9') {
            const uint32_t digit = (uint32_t)(input - '0');
            have_digit = true;
            if (value >
                (VIVADO_ILA_PULSE_MAX_CYCLES - digit) / 10u) {
                invalid = true;
            } else if (!invalid) {
                value = value * 10u + digit;
            }
        } else {
            invalid = true;
        }
    }

    if (!have_digit || invalid ||
        value < VIVADO_ILA_PULSE_MIN_CYCLES ||
        value > VIVADO_ILA_PULSE_MAX_CYCLES) {
        return false;
    }
    *pulse_cycles = value;
    return true;
}

static ila_trial_t trial_for_command(char command)
{
    ila_trial_t trial = {
        .command = command,
        .test_id = 0u,
        .pulse_cycles = 0u,
        .expect_trigger = 1u,
        .mode = "INVALID",
        .condition = "INVALID",
    };

    switch (command) {
    case 'r':
        trial.test_id = VIVADO_ILA_TEST_RISING;
        trial.mode = "RISING";
        trial.condition = "CH0_RISING";
        break;
    case 'f':
        trial.test_id = VIVADO_ILA_TEST_FALLING;
        trial.mode = "FALLING";
        trial.condition = "CH0_FALLING";
        break;
    case 'p':
        trial.test_id = VIVADO_ILA_TEST_PATTERN;
        trial.mode = "PATTERN";
        trial.condition = "MASK_F0_VALUE_A0";
        break;
    case 'h':
        trial.test_id = VIVADO_ILA_TEST_PATTERN_HOLD;
        trial.mode = "PATTERN_HOLD";
        trial.condition = "MASK_F0_VALUE_A0";
        break;
    case 'z':
        trial.test_id = VIVADO_ILA_TEST_NO_TRIGGER;
        trial.expect_trigger = 0u;
        trial.mode = "ZERO_MASK";
        trial.condition = "NO_TRIGGER";
        break;
    case 'u':
        trial.test_id = VIVADO_ILA_TEST_PULSE;
        trial.mode = "PULSE";
        trial.condition = "CH0_RISING";
        break;
    default:
        break;
    }
    return trial;
}

static void run_trial(const ila_trial_t *trial)
{
    uint32_t elapsed_ticks = 0u;
    bool done;

    if (!generator_clear()) {
        xil_printf("ILA_TRIAL_ERROR,ANALYZER=VIVADO_ILA,"
                   "COMMAND=%c,ERROR=GENERATOR_CLEAR_FAILED,"
                   "GEN_STATUS=0x%08X\r\n",
                   trial->command, generator_status());
        return;
    }

    /*
     * The host must arm the ILA before sending the command.  This BEGIN line
     * is a protocol acknowledgement only; samples are captured and exported
     * over JTAG by Vivado, never dumped through this UART application.
     */
    xil_printf("ILA_TRIAL_BEGIN,ANALYZER=VIVADO_ILA,COMMAND=%c,"
               "MODE=%s,TEST_ID=%u,PULSE_WIDTH_CYCLES=%u,"
               "EXPECT_TRIGGER=%u,CONDITION=%s\r\n",
               trial->command, trial->mode, trial->test_id,
               trial->pulse_cycles, trial->expect_trigger,
               trial->condition);

    if (!generator_start(trial->test_id, trial->pulse_cycles)) {
        xil_printf("ILA_TRIAL_ERROR,ANALYZER=VIVADO_ILA,"
                   "COMMAND=%c,ERROR=GENERATOR_START_REJECTED\r\n",
                   trial->command);
        return;
    }

    done = wait_generator_done(&elapsed_ticks);
    xil_printf("ILA_TRIAL_COMPLETE,ANALYZER=VIVADO_ILA,COMMAND=%c,"
               "MODE=%s,TEST_ID=%u,PULSE_WIDTH_CYCLES=%u,"
               "EXPECT_TRIGGER=%u,GENERATOR_DONE=%u,"
               "ELAPSED_TICKS=%u,STATUS=%s\r\n",
               trial->command, trial->mode, trial->test_id,
               trial->pulse_cycles, trial->expect_trigger,
               done ? 1u : 0u, elapsed_ticks,
               done ? "GENERATOR_DONE" : "GENERATOR_TIMEOUT");
}

static void print_menu(void)
{
    xil_printf("\r\nCommands (arm Vivado ILA before each trial):\r\n");
    xil_printf("  r<Enter>: rising-edge generator trial\r\n");
    xil_printf("  f<Enter>: falling-edge generator trial\r\n");
    xil_printf("  p<Enter>: masked-pattern generator trial\r\n");
    xil_printf("  h<Enter>: pattern-hold generator trial\r\n");
    xil_printf("  z<Enter>: no-trigger generator trial\r\n");
    xil_printf("  u<CYCLES><Enter>: one pulse trial, 1..1048575 cycles\r\n");
    xil_printf("  q<Enter>: stop\r\n> ");
}

int main(void)
{
    Xil_Out32(VIVADO_ILA_TEST_CTRL_BASEADDR + GPIO_TRI_OFFSET, 0u);
    Xil_Out32(VIVADO_ILA_TEST_CTRL_BASEADDR + GPIO2_TRI_OFFSET,
              0xffffffffu);
    (void)generator_clear();

    xil_printf("\r\nVIVADO_ILA_REFERENCE_READY\r\n");
    xil_printf("ANALYZER=VIVADO_ILA\r\n");
    xil_printf("UART=%u,8-N-1\r\n", VIVADO_ILA_UART_BAUD);
    xil_printf("SAMPLE_HZ=%u\r\n", VIVADO_ILA_CLOCK_HZ);
    xil_printf("CAPTURE_DEPTH=%u\r\n", VIVADO_ILA_CAPTURE_DEPTH);
    xil_printf("TRIGGER_INDEX=%u\r\n", VIVADO_ILA_TRIGGER_INDEX);
    xil_printf("CAPTURE_TRANSPORT=VIVADO_JTAG_CSV\r\n");
    xil_printf("UART_SAMPLE_DUMP=DISABLED\r\n");
    xil_printf("COMMANDS=r,f,p,h,z,u<CYCLES>,q\r\n");
    xil_printf("PULSE_CYCLES_MIN=%u\r\n", VIVADO_ILA_PULSE_MIN_CYCLES);
    xil_printf("PULSE_CYCLES_MAX=%u\r\n", VIVADO_ILA_PULSE_MAX_CYCLES);

    for (;;) {
        char command;
        ila_trial_t trial;

        print_menu();
        command = (char)inbyte();
        if (command >= 'A' && command <= 'Z') {
            command = (char)(command - 'A' + 'a');
        }
        if (command == '\r' || command == '\n' ||
            command == ' ' || command == '\t') {
            continue;
        }
        xil_printf("%c\r\n", command);

        if (command == 'q') {
            break;
        }

        trial = trial_for_command(command);
        if (trial.test_id == 0u) {
            xil_printf("UNKNOWN_COMMAND=%c\r\n", command);
            continue;
        }
        if (command == 'u') {
            xil_printf("PULSE_WIDTH_INPUT=DECIMAL_CYCLES\r\n");
            if (!read_pulse_width(&trial.pulse_cycles)) {
                xil_printf("ILA_TRIAL_ERROR,ANALYZER=VIVADO_ILA,"
                           "COMMAND=u,ERROR=INVALID_PULSE_WIDTH,"
                           "VALID_RANGE=1..1048575\r\n");
                continue;
            }
        }
        run_trial(&trial);
    }

    (void)generator_clear();
    xil_printf("VIVADO_ILA_REFERENCE_STOPPED\r\n");
    return 0;
}
