/******************************************************************************
 * EdgeScope-Lite Final Demonstration
 *
 * 8-bit Digital State Bus Event / Fault History Analysis
 *
 *   Demo 1: Divider 1, Rising Edge CH0, 0x00 -> 0x01
 *   Demo 2: Divider 8, Falling Edge CH1, 0x02 -> 0x00
 *   Demo 3: Divider 1, Masked Pattern 0xA0/0xF0, 0x25 -> 0xA5
 *
 * 각 Capture는 10초 AXI Timer Timeout을 사용한다. Trigger를 놓친 경우
 * Capture Abort -> Trigger Clear -> Sampler Disable 순서로 안전 복구한 뒤
 * 같은 Demo를 다시 시도한다.
 ******************************************************************************/

#include "platform.h"
#include "xil_printf.h"
#include "xstatus.h"

#include "edge_scope_lite_control.h"
#include "logic_analyzer_regs.h"

#define PRE_READY_MAX_POLLS          1000000u
#define SAMPLE_WAIT_MAX_POLLS        5000000u
#define POST_TRIGGER_MAX_POLLS       1000000u
#define CLEAR_MAX_POLLS              1000000u
#define CAPTURE_TIMEOUT_SECONDS           10u
#define TIMER_START_MARGIN_DIVISOR        100u

#define DEMO_START_KEY          's'
#define DEMO_FREEZE_KEY         'f'
#define FREEZE_FINAL_SAMPLE   0x3Cu

#define TRACE_WAITING_STATUS \
    (TRACE_STATUS_BUSY | TRACE_STATUS_PRE_READY)

#define TIMER_RUN_FORBIDDEN_BITS \
    (TIMER_CSR_CASCADE           | \
     TIMER_CSR_ENABLE_ALL        | \
     TIMER_CSR_ENABLE_PWM        | \
     TIMER_CSR_ENABLE_INTERRUPT  | \
     TIMER_CSR_LOAD              | \
     TIMER_CSR_AUTO_RELOAD       | \
     TIMER_CSR_EXTERNAL_CAPTURE  | \
     TIMER_CSR_EXTERNAL_GENERATE | \
     TIMER_CSR_CAPTURE_MODE)

#define TIMER_STOP_FORBIDDEN_BITS \
    (TIMER_RUN_FORBIDDEN_BITS  | \
     TIMER_CSR_INT_OCCURRED    | \
     TIMER_CSR_ENABLE_TIMER)

typedef struct {
    uint32_t number;
    const char *title;
    const char *meaning;
    const char *ready_instruction;
    uint32_t divider_sel;
    uint32_t divider_value;
    uint32_t trigger_mode;
    uint32_t trigger_channel;
    uint8_t before_sample;
    uint8_t after_sample;
    uint8_t pattern_value;
    uint8_t pattern_mask;
    uint32_t full_dump;
} demo_spec_t;

typedef struct {
    uint32_t passed;
    uint32_t attempts;
    uint32_t input_retries;
    uint32_t timeout_retries;
    uint32_t checksum_before;
    uint32_t checksum_after;
    uint32_t sample_511;
    uint32_t sample_512;
} demo_result_t;

static const demo_spec_t rising_demo_spec = {
    1u,
    "DEVICE START EVENT",
    "CH0 device-start signal rising",
    "Change SW[7:0] : 0x00 -> 0x01",
    SAMPLER_DIVIDE_BY_1,
    1u,
    TRIGGER_MODE_RISING,
    0u,
    0x00u,
    0x01u,
    0x00u,
    0x00u,
    0u
};

static const demo_spec_t falling_demo_spec = {
    2u,
    "ENABLE LOSS EVENT",
    "CH1 communication/enable signal falling",
    "Change SW[7:0] : 0x02 -> 0x00",
    SAMPLER_DIVIDE_BY_8,
    8u,
    TRIGGER_MODE_FALLING,
    1u,
    0x02u,
    0x00u,
    0x00u,
    0x00u,
    0u
};

static const demo_spec_t pattern_demo_spec = {
    3u,
    "FAULT CODE ENTRY",
    "SW[7:4] enters fault code 1010",
    "Change SW[7:0] : 0x25 -> 0xA5",
    SAMPLER_DIVIDE_BY_1,
    1u,
    TRIGGER_MODE_PATTERN,
    0u,
    0x25u,
    0xA5u,
    0xA0u,
    0xF0u,
    1u
};

/*
 * 4 KiB Snapshot은 작은 BSP Stack이 아니라 정적 BSS에 둔다.
 */
static uint32_t trace_snapshot[EDGE_SCOPE_CAPTURE_DEPTH];

/*
 * 함수 요약: 제어 함수 오류 코드를 UART 문자열로 출력
 */
static void print_edge_scope_error(edge_scope_result_t result)
{
    switch (result) {
    case EDGE_SCOPE_OK:
        xil_printf("OK");
        break;

    case EDGE_SCOPE_ERR_INVALID_ARG:
        xil_printf("INVALID_ARG");
        break;

    case EDGE_SCOPE_ERR_TIMEOUT:
        xil_printf("TIMEOUT");
        break;

    case EDGE_SCOPE_ERR_NOT_DONE:
        xil_printf("NOT_DONE");
        break;

    case EDGE_SCOPE_ERR_HW_STATE:
        xil_printf("HW_STATE");
        break;

    case EDGE_SCOPE_ERR_DATA_CHANGED:
        xil_printf("DATA_CHANGED");
        break;

    case EDGE_SCOPE_ERR_DATA_MISMATCH:
        xil_printf("DATA_MISMATCH");
        break;

    default:
        xil_printf("UNKNOWN(%d)", (int)result);
        break;
    }
}

/*
 * 함수 요약: 8-bit 값을 두 자리 대문자 Hex로 출력
 */
static void print_hex_byte(uint32_t value)
{
    static const char hex_table[] = "0123456789ABCDEF";

    xil_printf("%c%c",
               hex_table[(value >> 4u) & 0xFu],
               hex_table[value & 0xFu]);
}

/*
 * 함수 요약: Logical Index를 네 자리 10진수로 출력
 */
static void print_dec4(uint32_t value)
{
    xil_printf("%c", (char)('0' + ((value / 1000u) % 10u)));
    xil_printf("%c", (char)('0' + ((value / 100u) % 10u)));
    xil_printf("%c", (char)('0' + ((value / 10u) % 10u)));
    xil_printf("%c", (char)('0' + (value % 10u)));
}

/*
 * 함수 요약: Enter 없이 지정된 UART 문자 하나가 들어올 때까지 대기
 */
static void wait_for_uart_key(char expected_key)
{
    char received_key;

    do {
        received_key = inbyte();
    } while (received_key != expected_key);
}

/*
 * 함수 요약: Timeout/오류 복구에 필요한 세 명령을 요구 순서로 연속 실행
 */
static void abort_clear_disable(void)
{
    capture_abort();
    trigger_clear();
    sampler_disable();
}

/*
 * 함수 요약: 두 Capture Metadata가 완전히 같은지 확인
 */
static uint32_t capture_meta_equal(const edge_scope_capture_meta_t *left,
                                   const edge_scope_capture_meta_t *right)
{
    if ((left == 0) || (right == 0)) {
        return 0u;
    }

    return ((left->status == right->status) &&
            (left->start_addr == right->start_addr) &&
            (left->trigger_addr == right->trigger_addr) &&
            (left->write_addr == right->write_addr) &&
            (left->depth == right->depth) &&
            (left->trigger_index == right->trigger_index) &&
            (left->trigger_count == right->trigger_count))
           ? 1u
           : 0u;
}

/*
 * 함수 요약: Trace/Trigger/Sampler/Timer가 다음 Capture용 IDLE인지 검사
 */
static edge_scope_result_t verify_idle_state(uint32_t expected_trigger_count,
                                             uint32_t check_trigger_count)
{
    uint32_t trace_status = capture_status_read();
    uint32_t trigger_status = trigger_status_read();
    uint32_t trace_irq = capture_irq_active_read();
    uint32_t sampler_control = sampler_control_read();
    uint32_t sampler_count = sampler_sample_count_read();
    uint32_t timer_status = timeout_timer_status_read();
    uint32_t trigger_count = trigger_count_read();

    if ((trace_status != 0u) ||
        (trigger_status != 0u) ||
        (trace_irq != 0u) ||
        (sampler_control != 0u) ||
        (sampler_count != 0u) ||
        ((timer_status & TIMER_STOP_FORBIDDEN_BITS) != 0u) ||
        ((check_trigger_count != 0u) &&
         (trigger_count != expected_trigger_count))) {
        xil_printf("[ERROR] IDLE_STATE_INVALID.\r\n");
        xil_printf(" TRACE=0x%08x, TRIGGER=0x%08x, IRQ=%d\r\n",
                   (unsigned int)trace_status,
                   (unsigned int)trigger_status,
                   (int)trace_irq);
        xil_printf(" SAMPLER_CTRL=0x%08x, SAMPLE_COUNT=0x%08x\r\n",
                   (unsigned int)sampler_control,
                   (unsigned int)sampler_count);
        xil_printf(" TIMER=0x%08x, TRIGGER_COUNT=0x%08x\r\n",
                   (unsigned int)timer_status,
                   (unsigned int)trigger_count);
        return EDGE_SCOPE_ERR_HW_STATE;
    }

    return EDGE_SCOPE_OK;
}

/*
 * 함수 요약: 이전 실행 상태를 강제로 정리하고 최초 IDLE을 확립
 */
static edge_scope_result_t force_initial_idle(void)
{
    edge_scope_result_t result;

    abort_clear_disable();
    timeout_timer_stop_and_clear();

    result = capture_wait_cleared(CLEAR_MAX_POLLS);
    if (result != EDGE_SCOPE_OK) {
        return result;
    }

    sampler_stop_and_clear();

    return verify_idle_state(0u, 0u);
}

/*
 * 함수 요약: 진행 중 Capture를 Abort하고 Trigger Count 증가 없이 IDLE 복귀
 */
static edge_scope_result_t recover_aborted_attempt(
    uint32_t trigger_count_baseline)
{
    edge_scope_result_t result;

    /*
     * 세 호출 사이에는 Timer Clear, UART 출력, IRQ Acknowledge를 넣지 않는다.
     */
    abort_clear_disable();
    timeout_timer_stop_and_clear();

    result = capture_wait_cleared(CLEAR_MAX_POLLS);
    if (result != EDGE_SCOPE_OK) {
        return result;
    }

    sampler_stop_and_clear();

    return verify_idle_state(trigger_count_baseline, 1u);
}

/*
 * 함수 요약: 정상 DONE Capture를 CLEAR_DONE으로 해제해 재ARM 상태 검증
 */
static edge_scope_result_t clear_successful_capture(
    uint32_t expected_trigger_count)
{
    edge_scope_result_t result;

    capture_clear();

    result = capture_wait_cleared(CLEAR_MAX_POLLS);
    if (result != EDGE_SCOPE_OK) {
        return result;
    }

    trigger_clear();
    sampler_stop_and_clear();
    timeout_timer_stop_and_clear();

    result = verify_idle_state(expected_trigger_count, 1u);
    if (result == EDGE_SCOPE_OK) {
        xil_printf("[PASS] CLEAR_DONE / IRQ RELEASE / RE-ARM READY\r\n");
    }

    return result;
}

/*
 * 함수 요약: Demo 설정값을 Register에 쓰고 실제 Readback을 완전 비교
 */
static edge_scope_result_t configure_demo(const demo_spec_t *spec)
{
    edge_scope_result_t result;
    uint32_t expected_sampler_config;
    uint32_t expected_trigger_config;
    uint32_t expected_trigger_pattern;
    uint32_t actual_sampler_config;
    uint32_t actual_trigger_config;
    uint32_t actual_trigger_pattern;

    if (spec == 0) {
        return EDGE_SCOPE_ERR_INVALID_ARG;
    }

    result = sampler_config(spec->divider_sel, 0xFFu);
    if (result != EDGE_SCOPE_OK) {
        return result;
    }

    result = trigger_config(spec->trigger_mode,
                            spec->trigger_channel,
                            spec->pattern_value,
                            spec->pattern_mask);
    if (result != EDGE_SCOPE_OK) {
        return result;
    }

    expected_sampler_config =
        (spec->divider_sel & SAMPLER_CONFIG_DIVIDER_MASK) |
        ((0xFFu << SAMPLER_CONFIG_CHANNEL_SHIFT) &
         SAMPLER_CONFIG_CHANNEL_MASK);
    expected_trigger_config =
        (spec->trigger_mode & TRIGGER_CONFIG_MODE_MASK) |
        ((spec->trigger_channel << TRIGGER_CONFIG_CHANNEL_SHIFT) &
         TRIGGER_CONFIG_CHANNEL_MASK);
    expected_trigger_pattern =
        ((uint32_t)spec->pattern_value & TRIGGER_PATTERN_VALUE_MASK) |
        (((uint32_t)spec->pattern_mask << TRIGGER_PATTERN_MASK_SHIFT) &
         TRIGGER_PATTERN_MASK_MASK);

    actual_sampler_config = sampler_config_read();
    actual_trigger_config = trigger_config_read();
    actual_trigger_pattern = trigger_pattern_read();

    if ((actual_sampler_config != expected_sampler_config) ||
        (actual_trigger_config != expected_trigger_config) ||
        (actual_trigger_pattern != expected_trigger_pattern)) {
        xil_printf("[ERROR] CONFIG_READBACK_MISMATCH.\r\n");
        xil_printf(" SAMPLER expected=0x%08x, actual=0x%08x\r\n",
                   (unsigned int)expected_sampler_config,
                   (unsigned int)actual_sampler_config);
        xil_printf(" TRIGGER expected=0x%08x, actual=0x%08x\r\n",
                   (unsigned int)expected_trigger_config,
                   (unsigned int)actual_trigger_config);
        xil_printf(" PATTERN expected=0x%08x, actual=0x%08x\r\n",
                   (unsigned int)expected_trigger_pattern,
                   (unsigned int)actual_trigger_pattern);
        return EDGE_SCOPE_ERR_HW_STATE;
    }

    return EDGE_SCOPE_OK;
}

/*
 * 함수 요약: 10초를 현재 AXI Timer Clock의 Tick 수로 변환
 */
static edge_scope_result_t capture_timeout_ticks_read(uint32_t *timeout_ticks)
{
    uint32_t timer_clock_hz;

    if (timeout_ticks == 0) {
        return EDGE_SCOPE_ERR_INVALID_ARG;
    }

    timer_clock_hz = timeout_timer_clock_hz_read();

    if ((timer_clock_hz == 0u) ||
        (CAPTURE_TIMEOUT_SECONDS > (0xFFFFFFFFu / timer_clock_hz))) {
        return EDGE_SCOPE_ERR_INVALID_ARG;
    }

    *timeout_ticks = timer_clock_hz * CAPTURE_TIMEOUT_SECONDS;

    return EDGE_SCOPE_OK;
}

/*
 * 함수 요약: 10초 Timer를 실제 시작하고 TLR/TCR 시작값까지 검증
 *
 * 허용 Margin은 Timer Clock의 1/100(10 ms)이다. 정상 MMIO 시작은 이보다
 * 훨씬 짧으므로 TLR Load 실패나 지나치게 작은 이전 Counter 사용을 검출한다.
 */
static edge_scope_result_t start_capture_timeout(
    uint32_t *initial_timer_count)
{
    edge_scope_result_t result;
    uint32_t timeout_ticks;
    uint32_t timer_clock_hz;
    uint32_t timer_load_value;
    uint32_t timer_count;
    uint32_t timer_status;
    uint32_t timer_start_margin;

    if (initial_timer_count == 0) {
        return EDGE_SCOPE_ERR_INVALID_ARG;
    }

    result = capture_timeout_ticks_read(&timeout_ticks);
    if (result != EDGE_SCOPE_OK) {
        return result;
    }

    result = timeout_timer_start(timeout_ticks);
    if (result != EDGE_SCOPE_OK) {
        return result;
    }

    timer_clock_hz = timeout_timer_clock_hz_read();
    timer_load_value = timeout_timer_load_read();
    timer_count = timeout_timer_count_read();
    timer_status = timeout_timer_status_read();
    timer_start_margin =
        timer_clock_hz / TIMER_START_MARGIN_DIVISOR;

    if (timer_start_margin == 0u) {
        timer_start_margin = 1u;
    }

    if ((timer_load_value != (timeout_ticks - 2u)) ||
        (timer_count > timer_load_value) ||
        ((timer_load_value - timer_count) > timer_start_margin) ||
        ((timer_status & TIMER_CSR_TIMEOUT_RUN) !=
         TIMER_CSR_TIMEOUT_RUN) ||
        ((timer_status & (TIMER_RUN_FORBIDDEN_BITS |
                          TIMER_CSR_INT_OCCURRED)) != 0u)) {
        xil_printf("[ERROR] TIMER_START_READBACK_INVALID.\r\n");
        xil_printf(" TLR0=0x%08x, TCR0=0x%08x, TCSR0=0x%08x\r\n",
                   (unsigned int)timer_load_value,
                   (unsigned int)timer_count,
                   (unsigned int)timer_status);
        timeout_timer_stop_and_clear();
        return EDGE_SCOPE_ERR_HW_STATE;
    }

    *initial_timer_count = timer_count;

    return EDGE_SCOPE_OK;
}

/*
 * 함수 요약: Trigger 증거가 보이면 Timer를 끄고 짧은 Post-fill 완료를 대기
 */
static edge_scope_result_t finish_triggered_capture(void)
{
    edge_scope_result_t result;

    timeout_timer_stop_and_clear();

    result = capture_wait_done(POST_TRIGGER_MAX_POLLS);
    if (result == EDGE_SCOPE_ERR_TIMEOUT) {
        xil_printf("[ERROR] Post-trigger 512-sample fill did not finish.\r\n");
        return EDGE_SCOPE_ERR_HW_STATE;
    }

    return result;
}

/*
 * 함수 요약: 정상 Trigger/DONE 또는 clean 10초 Timeout까지 Polling
 *
 * 호출 전에 start_capture_timeout()이 Timer를 시작하고 initial_timer_count를
 * 검증해야 한다.
 *
 * 반환값:
 *   OK      : Trigger 후 DONE 완료, Timer 정지
 *   TIMEOUT : Trigger 증거 없이 10초 경과, Capture/Timer는 Caller가 복구
 *   그 외   : Hardware 상태 오류, Timer 정지
 */
static edge_scope_result_t wait_for_capture_or_timeout(
    uint32_t trigger_count_baseline,
    uint32_t initial_timer_count)
{
    uint32_t previous_timer_count = initial_timer_count;

    while (1) {
        uint32_t trace_status = capture_status_read();
        uint32_t trigger_status = trigger_status_read();
        uint32_t trigger_count = trigger_count_read();
        uint32_t trigger_delta =
            trigger_count - trigger_count_baseline;
        uint32_t trace_irq = capture_irq_active_read();
        uint32_t timer_status;
        uint32_t current_timer_count;

        if ((trace_status & TRACE_STATUS_DONE) != 0u) {
            timeout_timer_stop_and_clear();

            if (((trace_status & TRACE_STATUS_BUSY) != 0u) ||
                (trigger_delta != 1u)) {
                return EDGE_SCOPE_ERR_HW_STATE;
            }

            return EDGE_SCOPE_OK;
        }

        if (trigger_delta > 1u) {
            timeout_timer_stop_and_clear();
            return EDGE_SCOPE_ERR_HW_STATE;
        }

        if (((trace_status & TRACE_STATUS_TRIGGERED) != 0u) ||
            ((trigger_status & TRIGGER_STATUS_TRIGGERED) != 0u) ||
            (trigger_delta == 1u)) {
            return finish_triggered_capture();
        }

        if ((trace_status != TRACE_WAITING_STATUS) ||
            (trigger_status != TRIGGER_STATUS_ARMED) ||
            (trigger_delta != 0u) ||
            (trace_irq != 0u)) {
            timeout_timer_stop_and_clear();
            return EDGE_SCOPE_ERR_HW_STATE;
        }

        timer_status = timeout_timer_status_read();

        if ((timer_status & TIMER_CSR_INT_OCCURRED) != 0u) {
            /*
             * TINT 직후 상태를 다시 읽어 경계 시점의 Trigger/DONE을 우선한다.
             */
            trace_status = capture_status_read();
            trigger_status = trigger_status_read();
            trigger_count = trigger_count_read();
            trigger_delta = trigger_count - trigger_count_baseline;
            trace_irq = capture_irq_active_read();

            if ((trace_status & TRACE_STATUS_DONE) != 0u) {
                timeout_timer_stop_and_clear();
                return (((trace_status & TRACE_STATUS_BUSY) == 0u) &&
                        (trigger_delta == 1u))
                       ? EDGE_SCOPE_OK
                       : EDGE_SCOPE_ERR_HW_STATE;
            }

            if (((trace_status & TRACE_STATUS_TRIGGERED) != 0u) ||
                ((trigger_status & TRIGGER_STATUS_TRIGGERED) != 0u) ||
                (trigger_delta == 1u)) {
                return finish_triggered_capture();
            }

            if ((trace_status == TRACE_WAITING_STATUS) &&
                (trigger_status == TRIGGER_STATUS_ARMED) &&
                (trigger_delta == 0u) &&
                (trace_irq == 0u)) {
                return EDGE_SCOPE_ERR_TIMEOUT;
            }

            timeout_timer_stop_and_clear();
            return EDGE_SCOPE_ERR_HW_STATE;
        }

        if (((timer_status & TIMER_CSR_TIMEOUT_RUN) !=
             TIMER_CSR_TIMEOUT_RUN) ||
            ((timer_status & TIMER_RUN_FORBIDDEN_BITS) != 0u)) {
            timeout_timer_stop_and_clear();
            return EDGE_SCOPE_ERR_HW_STATE;
        }

        current_timer_count = timeout_timer_count_read();

        if (current_timer_count >= previous_timer_count) {
            /*
             * TCSR와 TCR Read 사이 Terminal Count가 발생한 경우 다음 회차가
             * Capture 상태를 먼저 검사하도록 한다.
             */
            timer_status = timeout_timer_status_read();
            if ((timer_status & TIMER_CSR_INT_OCCURRED) != 0u) {
                continue;
            }

            timeout_timer_stop_and_clear();
            return EDGE_SCOPE_ERR_HW_STATE;
        }

        previous_timer_count = current_timer_count;
    }
}

/*
 * 함수 요약: Metadata, 주소 관계, Trigger Engine과 IRQ를 공통 검증
 */
static edge_scope_result_t validate_capture_metadata(
    uint32_t trigger_count_baseline,
    edge_scope_capture_meta_t *meta)
{
    uint32_t logical_trigger_index;
    uint32_t expected_start_addr;
    uint32_t trigger_status;

    if (meta == 0) {
        return EDGE_SCOPE_ERR_INVALID_ARG;
    }

    capture_read_meta(meta);

    if (((meta->status & TRACE_STATUS_DONE) == 0u) ||
        ((meta->status & TRACE_STATUS_TRIGGERED) == 0u) ||
        ((meta->status & TRACE_STATUS_BUSY) != 0u)) {
        xil_printf("[ERROR] Final Trace state is invalid:");
        xil_printf(" 0x%08x\r\n", (unsigned int)meta->status);
        return EDGE_SCOPE_ERR_HW_STATE;
    }

    if ((meta->depth != EDGE_SCOPE_CAPTURE_DEPTH) ||
        (meta->trigger_index != EDGE_SCOPE_TRIGGER_INDEX)) {
        xil_printf("[ERROR] CAPTURE_INFO invalid: DEPTH=%d, INDEX=%d\r\n",
                   (int)meta->depth,
                   (int)meta->trigger_index);
        return EDGE_SCOPE_ERR_HW_STATE;
    }

    logical_trigger_index =
        (meta->trigger_addr - meta->start_addr) & TRACE_ADDR_MASK;
    expected_start_addr =
        (meta->write_addr + 1u) & TRACE_ADDR_MASK;

    if ((logical_trigger_index != EDGE_SCOPE_TRIGGER_INDEX) ||
        (meta->start_addr != expected_start_addr)) {
        xil_printf("[ERROR] Circular address relation invalid.\r\n");
        xil_printf(" START=0x%08x, TRIGGER=0x%08x, WRITE=0x%08x\r\n",
                   (unsigned int)meta->start_addr,
                   (unsigned int)meta->trigger_addr,
                   (unsigned int)meta->write_addr);
        return EDGE_SCOPE_ERR_HW_STATE;
    }

    trigger_status = trigger_status_read();

    if (trigger_status !=
        (TRIGGER_STATUS_ARMED | TRIGGER_STATUS_TRIGGERED)) {
        xil_printf("[ERROR] Trigger final status=0x%08x\r\n",
                   (unsigned int)trigger_status);
        return EDGE_SCOPE_ERR_HW_STATE;
    }

    if ((meta->trigger_count - trigger_count_baseline) != 1u) {
        xil_printf("[ERROR] Trigger Count delta is not 1.\r\n");
        return EDGE_SCOPE_ERR_HW_STATE;
    }

    if (capture_irq_active_read() == 0u) {
        xil_printf("[ERROR] DONE did not assert Trace IRQ.\r\n");
        return EDGE_SCOPE_ERR_HW_STATE;
    }

    return EDGE_SCOPE_OK;
}

/*
 * 함수 요약: Logical 511 -> 512가 각 Demo Trigger 조건과 일치하는지 확인
 */
static edge_scope_result_t validate_trigger_condition(
    const demo_spec_t *spec,
    const uint8_t *window)
{
    uint32_t sample_511;
    uint32_t sample_512;
    uint32_t condition_ok = 0u;

    if ((spec == 0) || (window == 0)) {
        return EDGE_SCOPE_ERR_INVALID_ARG;
    }

    sample_511 =
        window[(EDGE_SCOPE_TRIGGER_INDEX - 1u) -
               EDGE_SCOPE_DEMO_WINDOW_FIRST];
    sample_512 =
        window[EDGE_SCOPE_TRIGGER_INDEX -
               EDGE_SCOPE_DEMO_WINDOW_FIRST];

    if (spec->trigger_mode == TRIGGER_MODE_RISING) {
        uint32_t channel_mask = 1u << spec->trigger_channel;

        condition_ok =
            (((sample_511 & channel_mask) == 0u) &&
             ((sample_512 & channel_mask) != 0u))
            ? 1u
            : 0u;
    } else if (spec->trigger_mode == TRIGGER_MODE_FALLING) {
        uint32_t channel_mask = 1u << spec->trigger_channel;

        condition_ok =
            (((sample_511 & channel_mask) != 0u) &&
             ((sample_512 & channel_mask) == 0u))
            ? 1u
            : 0u;
    } else if (spec->trigger_mode == TRIGGER_MODE_PATTERN) {
        condition_ok =
            (((sample_511 & spec->pattern_mask) !=
              (spec->pattern_value & spec->pattern_mask)) &&
             ((sample_512 & spec->pattern_mask) ==
              (spec->pattern_value & spec->pattern_mask)))
            ? 1u
            : 0u;
    } else {
        return EDGE_SCOPE_ERR_INVALID_ARG;
    }

    if ((condition_ok == 0u) ||
        (sample_511 != spec->before_sample) ||
        (sample_512 != spec->after_sample)) {
        xil_printf("[ERROR] Logical 511 -> 512 condition mismatch.\r\n");
        xil_printf(" Expected 0x");
        print_hex_byte(spec->before_sample);
        xil_printf(" -> 0x");
        print_hex_byte(spec->after_sample);
        xil_printf(", actual 0x");
        print_hex_byte(sample_511);
        xil_printf(" -> 0x");
        print_hex_byte(sample_512);
        xil_printf("\r\n");
        return EDGE_SCOPE_ERR_DATA_MISMATCH;
    }

    return EDGE_SCOPE_OK;
}

/*
 * 함수 요약: Logical 508~516 Compact Window 출력
 */
static void print_trigger_window(const uint8_t *window)
{
    uint32_t offset;

    xil_printf("\r\n[LOGICAL 0508..0516]\r\n");

    for (offset = 0u;
         offset < EDGE_SCOPE_DEMO_WINDOW_COUNT;
         ++offset) {
        uint32_t logical_index =
            EDGE_SCOPE_DEMO_WINDOW_FIRST + offset;

        print_dec4(logical_index);
        xil_printf(": ");
        print_hex_byte(window[offset]);

        if (logical_index == EDGE_SCOPE_TRIGGER_INDEX) {
            xil_printf(" <TRIGGER>");
        }

        xil_printf("\r\n");
    }
}

/*
 * 함수 요약: DONE/One-shot 상태를 유지한 채 지정한 Live Sample을 기다림
 */
static edge_scope_result_t wait_for_frozen_live_sample(
    uint8_t expected_sample,
    uint32_t expected_trigger_count)
{
    while (1) {
        uint32_t trace_status = capture_status_read();
        uint32_t trigger_status = trigger_status_read();

        if (trigger_count_read() != expected_trigger_count) {
            xil_printf("[ERROR] Trigger Count changed during one-shot replay.\r\n");
            return EDGE_SCOPE_ERR_DATA_CHANGED;
        }

        if (((trace_status &
              (TRACE_STATUS_TRIGGERED | TRACE_STATUS_DONE)) !=
             (TRACE_STATUS_TRIGGERED | TRACE_STATUS_DONE)) ||
            ((trace_status & TRACE_STATUS_BUSY) != 0u) ||
            (trigger_status !=
             (TRIGGER_STATUS_ARMED | TRIGGER_STATUS_TRIGGERED)) ||
            (capture_irq_active_read() == 0u) ||
            (sampler_control_read() != SAMPLER_CONTROL_ENABLE)) {
            xil_printf("[ERROR] Capture state changed during one-shot replay.\r\n");
            return EDGE_SCOPE_ERR_HW_STATE;
        }

        if (sampler_last_sample_read() == expected_sample) {
            return EDGE_SCOPE_OK;
        }
    }
}

/*
 * 함수 요약: DONE 중 Sampler를 계속 돌려 BRAM Freeze와 One-shot을 검증
 */
static edge_scope_result_t verify_bram_freeze_and_one_shot(
    const demo_spec_t *spec,
    uint32_t expected_trigger_count,
    const edge_scope_capture_meta_t *meta_before,
    demo_result_t *demo_result)
{
    edge_scope_capture_meta_t meta_after;
    edge_scope_trace_diff_t difference;
    edge_scope_result_t result;
    uint32_t observed_guard_samples;
    uint32_t observed_replay_samples;
    uint32_t checksum_before;
    uint32_t checksum_after;
    uint32_t live_sample;

    if ((spec == 0) || (meta_before == 0) || (demo_result == 0)) {
        return EDGE_SCOPE_ERR_INVALID_ARG;
    }

    result = trace_snapshot_read(trace_snapshot,
                                 EDGE_SCOPE_CAPTURE_DEPTH);
    if (result != EDGE_SCOPE_OK) {
        return result;
    }

    result = trace_checksum_read(&checksum_before);
    if (result != EDGE_SCOPE_OK) {
        return result;
    }

    /*
     * DONE 뒤에도 Sampler는 Enable 상태이다. Snapshot을 먼저 고정한 뒤
     * Trigger 조건을 실제로 한 번 더 재현하여 One-shot을 자동 검증한다.
     */
    xil_printf("\r\n[FREEZE CHECK] Capture is DONE.\r\n");
    xil_printf("[ONE-SHOT REPLAY] Set SW[7:0] = 0x");
    print_hex_byte(spec->before_sample);
    xil_printf(" and hold it.\r\n");

    result = wait_for_frozen_live_sample(
        spec->before_sample,
        expected_trigger_count);
    if (result != EDGE_SCOPE_OK) {
        return result;
    }

    xil_printf("[OBSERVED] LAST_SAMPLE=0x");
    print_hex_byte(spec->before_sample);
    xil_printf("\r\n");
    xil_printf("[ONE-SHOT REPLAY] Now set SW[7:0] = 0x");
    print_hex_byte(spec->after_sample);
    xil_printf(" and hold it.\r\n");

    result = wait_for_frozen_live_sample(
        spec->after_sample,
        expected_trigger_count);
    if (result != EDGE_SCOPE_OK) {
        return result;
    }

    result = sampler_wait_samples(1u,
                                  SAMPLE_WAIT_MAX_POLLS,
                                  &observed_replay_samples);
    if (result != EDGE_SCOPE_OK) {
        return result;
    }

    result = wait_for_frozen_live_sample(
        spec->after_sample,
        expected_trigger_count);
    if (result != EDGE_SCOPE_OK) {
        return result;
    }

    xil_printf("[PASS] ONE-SHOT CONDITION REPLAYED, COUNT UNCHANGED");
    xil_printf(" (%u verification samples)\r\n",
               (unsigned int)observed_replay_samples);
    xil_printf("Then try several values and finish at SW[7:0] = 0x");
    print_hex_byte(FREEZE_FINAL_SAMPLE);
    xil_printf(".\r\n");
    xil_printf("Keep 0x");
    print_hex_byte(FREEZE_FINAL_SAMPLE);
    xil_printf(" stable and send lowercase '%c'.\r\n",
               DEMO_FREEZE_KEY);

    while (1) {
        wait_for_uart_key(DEMO_FREEZE_KEY);

        /*
         * 키 입력 뒤 1 Wrap + 37 valid Sample을 더 기다린다. 잘못된 구현이
         * 계속 Write하더라도 주소가 정확히 한 바퀴 돌아 원위치가 되는
         * 사각지대를 37 Sample Offset으로 제거한다.
         */
        result = sampler_wait_samples(EDGE_SCOPE_FREEZE_GUARD_SAMPLES,
                                      SAMPLE_WAIT_MAX_POLLS,
                                      &observed_guard_samples);
        if (result != EDGE_SCOPE_OK) {
            return result;
        }

        live_sample = sampler_last_sample_read();

        if (live_sample == FREEZE_FINAL_SAMPLE) {
            break;
        }

        xil_printf("[RETRY] Sampler LAST_SAMPLE is 0x");
        print_hex_byte(live_sample);
        xil_printf(", not 0x");
        print_hex_byte(FREEZE_FINAL_SAMPLE);
        xil_printf(".\r\n");
        xil_printf("Set SW[7:0] = 0x");
        print_hex_byte(FREEZE_FINAL_SAMPLE);
        xil_printf(" and send '%c' again.\r\n", DEMO_FREEZE_KEY);
    }

    result = trace_snapshot_verify(trace_snapshot,
                                   EDGE_SCOPE_CAPTURE_DEPTH,
                                   &difference);
    if (result != EDGE_SCOPE_OK) {
        if (result == EDGE_SCOPE_ERR_DATA_CHANGED) {
            xil_printf("[ERROR] BRAM changed after DONE:");
            xil_printf(" mismatches=%d, first=%d\r\n",
                       (int)difference.mismatch_count,
                       (int)difference.first_mismatch_index);
        }

        return result;
    }

    result = trace_checksum_read(&checksum_after);
    if (result != EDGE_SCOPE_OK) {
        return result;
    }

    capture_read_meta(&meta_after);

    if ((checksum_before != checksum_after) ||
        (capture_meta_equal(meta_before, &meta_after) == 0u) ||
        (trigger_count_read() != expected_trigger_count) ||
        (trigger_status_read() !=
         (TRIGGER_STATUS_ARMED | TRIGGER_STATUS_TRIGGERED)) ||
        (capture_irq_active_read() == 0u)) {
        xil_printf("[ERROR] BRAM Freeze/One-shot state changed.\r\n");
        xil_printf(" CHECKSUM 0x%08x -> 0x%08x\r\n",
                   (unsigned int)checksum_before,
                   (unsigned int)checksum_after);
        return EDGE_SCOPE_ERR_DATA_CHANGED;
    }

    demo_result->checksum_before = checksum_before;
    demo_result->checksum_after = checksum_after;

    xil_printf("[PASS] BRAM FROZEN AFTER DONE\r\n");
    xil_printf("       CHECKSUM 0x%08x == 0x%08x\r\n",
               (unsigned int)checksum_before,
               (unsigned int)checksum_after);
    xil_printf("[PASS] LIVE INPUT CHANGED AFTER DONE: LAST_SAMPLE=0x");
    print_hex_byte(FREEZE_FINAL_SAMPLE);
    xil_printf("\r\n");
    xil_printf("[PASS] BRAM TIME ORDER: 1,024 logical samples scanned\r\n");
    xil_printf("[PASS] ONE-SHOT TRIGGER COUNT remained +1");
    xil_printf(" during %u additional samples\r\n",
               (unsigned int)observed_guard_samples);

    return EDGE_SCOPE_OK;
}

/*
 * 함수 요약: 성공 Capture의 모든 자동 PASS 조건과 UART 출력을 수행
 */
static edge_scope_result_t validate_and_report_capture(
    const demo_spec_t *spec,
    uint32_t trigger_count_baseline,
    demo_result_t *demo_result)
{
    edge_scope_capture_meta_t meta;
    edge_scope_result_t result;
    uint8_t window[EDGE_SCOPE_DEMO_WINDOW_COUNT];
    uint32_t checksum_after_dump;

    result = validate_capture_metadata(trigger_count_baseline, &meta);
    if (result != EDGE_SCOPE_OK) {
        return result;
    }

    result = trace_logical_window_read(EDGE_SCOPE_DEMO_WINDOW_FIRST,
                                       EDGE_SCOPE_DEMO_WINDOW_COUNT,
                                       window);
    if (result != EDGE_SCOPE_OK) {
        return result;
    }

    result = validate_trigger_condition(spec, window);
    if (result != EDGE_SCOPE_OK) {
        return result;
    }

    demo_result->sample_511 =
        window[(EDGE_SCOPE_TRIGGER_INDEX - 1u) -
               EDGE_SCOPE_DEMO_WINDOW_FIRST];
    demo_result->sample_512 =
        window[EDGE_SCOPE_TRIGGER_INDEX -
               EDGE_SCOPE_DEMO_WINDOW_FIRST];

    xil_printf("[PASS] TRIGGER CONDITION\r\n");
    xil_printf("[PASS] TRIGGER AT LOGICAL INDEX 512\r\n");
    xil_printf("[PASS] CIRCULAR ADDRESS ORDER\r\n");
    xil_printf("[PASS] TRIGGER COUNT DELTA = 1\r\n");
    xil_printf("[PASS] CAPTURE DEPTH=1024, PRE:POST=512:512\r\n");
    xil_printf("[PASS] DIVIDER SETTING = %d\r\n",
               (int)spec->divider_value);
    xil_printf("[PASS] 8-CHANNEL SAMPLER MASK = 0xFF\r\n");

    result = verify_bram_freeze_and_one_shot(
        spec,
        trigger_count_baseline + 1u,
        &meta,
        demo_result);
    if (result != EDGE_SCOPE_OK) {
        return result;
    }

    /*
     * Freeze/One-shot의 인과성을 확인한 뒤에만 Sampler를 정지하고 UART 출력.
     */
    sampler_disable();

    if (sampler_control_read() != 0u) {
        return EDGE_SCOPE_ERR_HW_STATE;
    }

    print_trigger_window(window);

    if (spec->full_dump != 0u) {
        xil_printf("\r\n[UART] Full 1,024-sample chronological dump");
        xil_printf(" starts now.\r\n");
        xil_printf("[UART] At 9,600 baud this takes about 11 seconds.\r\n");

        result = trace_dump_hex();
        if (result != EDGE_SCOPE_OK) {
            return result;
        }

        result = trace_checksum_read(&checksum_after_dump);
        if (result != EDGE_SCOPE_OK) {
            return result;
        }

        if (checksum_after_dump != demo_result->checksum_after) {
            xil_printf("[ERROR] Checksum changed during UART dump.\r\n");
            return EDGE_SCOPE_ERR_DATA_CHANGED;
        }

        xil_printf("[PASS] UART 1,024-SAMPLE DUMP / BRAM READ-ONLY\r\n");
    }

    return EDGE_SCOPE_OK;
}

/*
 * 함수 요약: Demo Header와 사용자 조작 안내 출력
 */
static void print_demo_prompt(const demo_spec_t *spec,
                              uint32_t attempt)
{
    xil_printf("\r\n");
    xil_printf("================================================\r\n");
    xil_printf(" [DEMO %d/3] %s\r\n",
               (int)spec->number,
               spec->title);
    xil_printf("================================================\r\n");
    xil_printf("Meaning : %s\r\n", spec->meaning);
    xil_printf("Attempt : %d\r\n", (int)attempt);

    if (spec->trigger_mode == TRIGGER_MODE_PATTERN) {
        xil_printf("Trigger condition : SW[7:4] == 1010\r\n");
        xil_printf("Pattern Value=0xA0, Mask=0xF0\r\n");
    }

    if (spec->divider_value == 1u) {
        xil_printf("Sampler : Divider 1, 100 MS/s\r\n");
    } else {
        xil_printf("Sampler : Divider 8, 12.5 MS/s\r\n");
    }

    xil_printf("Set SW[7:0] = 0x");
    print_hex_byte(spec->before_sample);
    xil_printf("\r\n");
    xil_printf("Send lowercase '%c' when the initial state is stable.\r\n",
               DEMO_START_KEY);
}

/*
 * 함수 요약: 하나의 Demo를 성공할 때까지 clean Timeout/Input 오류만 재시도
 */
static edge_scope_result_t run_demo(const demo_spec_t *spec,
                                    demo_result_t *demo_result)
{
    edge_scope_result_t result;

    if ((spec == 0) || (demo_result == 0)) {
        return EDGE_SCOPE_ERR_INVALID_ARG;
    }

    demo_result->passed = 0u;
    demo_result->attempts = 0u;
    demo_result->input_retries = 0u;
    demo_result->timeout_retries = 0u;
    demo_result->checksum_before = 0u;
    demo_result->checksum_after = 0u;
    demo_result->sample_511 = 0u;
    demo_result->sample_512 = 0u;

    while (1) {
        uint32_t trigger_count_baseline;
        uint32_t last_sample;
        uint32_t trace_status;
        uint32_t trigger_status;
        uint32_t observed_baseline_samples;
        uint32_t initial_timer_count;

        ++demo_result->attempts;

        result = verify_idle_state(0u, 0u);
        if (result != EDGE_SCOPE_OK) {
            return result;
        }

        trigger_count_baseline = trigger_count_read();

        result = configure_demo(spec);
        if (result != EDGE_SCOPE_OK) {
            return result;
        }

        print_demo_prompt(spec, demo_result->attempts);
        wait_for_uart_key(DEMO_START_KEY);

        xil_printf("Waiting for PRE-TRIGGER samples...\r\n");

        sampler_enable();
        capture_arm();

        result = capture_wait_pre_ready(PRE_READY_MAX_POLLS);
        if (result != EDGE_SCOPE_OK) {
            return result;
        }

        last_sample = sampler_last_sample_read();
        trace_status = capture_status_read();
        trigger_status = trigger_status_read();

        if (last_sample != spec->before_sample) {
            xil_printf("[RETRY] Initial SW mismatch: expected 0x");
            print_hex_byte(spec->before_sample);
            xil_printf(", sampled 0x");
            print_hex_byte(last_sample);
            xil_printf("\r\n");

            result = recover_aborted_attempt(trigger_count_baseline);
            if (result != EDGE_SCOPE_OK) {
                return result;
            }

            ++demo_result->input_retries;
            continue;
        }

        if ((trace_status != TRACE_WAITING_STATUS) ||
            (trigger_status != 0u) ||
            (trigger_count_read() != trigger_count_baseline) ||
            (capture_irq_active_read() != 0u)) {
            return EDGE_SCOPE_ERR_HW_STATE;
        }

        trigger_arm();

        result = sampler_wait_samples(1u,
                                      SAMPLE_WAIT_MAX_POLLS,
                                      &observed_baseline_samples);
        if (result != EDGE_SCOPE_OK) {
            return result;
        }

        last_sample = sampler_last_sample_read();
        trace_status = capture_status_read();
        trigger_status = trigger_status_read();

        if ((last_sample != spec->before_sample) ||
            (trace_status != TRACE_WAITING_STATUS) ||
            (trigger_status != TRIGGER_STATUS_ARMED) ||
            (trigger_count_read() != trigger_count_baseline) ||
            (capture_irq_active_read() != 0u)) {
            xil_printf("[ERROR] Trigger baseline changed before READY.\r\n");
            return EDGE_SCOPE_ERR_HW_STATE;
        }

        if ((spec->trigger_mode == TRIGGER_MODE_PATTERN) &&
            ((last_sample & spec->pattern_mask) ==
             (spec->pattern_value & spec->pattern_mask))) {
            xil_printf("[ERROR] Pattern baseline already matches.\r\n");
            return EDGE_SCOPE_ERR_HW_STATE;
        }

        xil_printf("[READY] Trigger baseline is stable.\r\n");
        xil_printf("        After [GO], %s\r\n",
                   spec->ready_instruction);
        xil_printf("        Hold the new state until CAPTURE DONE.\r\n");
        xil_printf("        A BRAM Freeze switch-change check follows.\r\n");
        xil_printf("[TIMER] Starting and verifying 10-second Timer...\r\n");

        result = start_capture_timeout(&initial_timer_count);
        if (result != EDGE_SCOPE_OK) {
            return result;
        }

        /*
         * Timer 시작 후 GO 직전에도 아직 Trigger 전 상태인지 확인한다.
         */
        if ((capture_status_read() != TRACE_WAITING_STATUS) ||
            (trigger_status_read() != TRIGGER_STATUS_ARMED) ||
            (trigger_count_read() != trigger_count_baseline) ||
            (capture_irq_active_read() != 0u)) {
            timeout_timer_stop_and_clear();
            xil_printf("[ERROR] Trigger occurred before [GO].\r\n");
            return EDGE_SCOPE_ERR_HW_STATE;
        }

        xil_printf("[GO] %s\r\n", spec->ready_instruction);

        result = wait_for_capture_or_timeout(trigger_count_baseline,
                                             initial_timer_count);

        if (result == EDGE_SCOPE_ERR_TIMEOUT) {
            edge_scope_result_t recovery_result =
                recover_aborted_attempt(trigger_count_baseline);

            if (recovery_result != EDGE_SCOPE_OK) {
                xil_printf("[ERROR] Timeout recovery failed: ");
                print_edge_scope_error(recovery_result);
                xil_printf("\r\n");
                return recovery_result;
            }

            ++demo_result->timeout_retries;

            xil_printf("[TIMEOUT] No Trigger within 10 seconds.\r\n");
            xil_printf("[RECOVERY] capture_abort -> trigger_clear");
            xil_printf(" -> sampler_disable completed.\r\n");
            xil_printf("[RETRY] Restore the initial SW state");
            xil_printf(" and start this Demo again.\r\n");
            continue;
        }

        if (result != EDGE_SCOPE_OK) {
            return result;
        }

        result = validate_and_report_capture(spec,
                                             trigger_count_baseline,
                                             demo_result);
        if (result != EDGE_SCOPE_OK) {
            return result;
        }

        result = clear_successful_capture(trigger_count_baseline + 1u);
        if (result != EDGE_SCOPE_OK) {
            return result;
        }

        demo_result->passed = 1u;

        xil_printf("[PASS] DEMO %d/3 %s COMPLETE\r\n",
                   (int)spec->number,
                   spec->title);

        return EDGE_SCOPE_OK;
    }
}

static edge_scope_result_t run_rising_demo(demo_result_t *result)
{
    return run_demo(&rising_demo_spec, result);
}

static edge_scope_result_t run_falling_demo(demo_result_t *result)
{
    return run_demo(&falling_demo_spec, result);
}

static edge_scope_result_t run_pattern_demo(demo_result_t *result)
{
    return run_demo(&pattern_demo_spec, result);
}

/*
 * 함수 요약: 세 Demo 결과와 전체 공통 기능 PASS Summary 출력
 */
static void print_final_summary(const demo_result_t *rising,
                                const demo_result_t *falling,
                                const demo_result_t *pattern)
{
    xil_printf("\r\n");
    xil_printf("========================================\r\n");
    xil_printf(" EDGE_SCOPE-LITE FINAL DEMO RESULT\r\n");
    xil_printf("========================================\r\n");
    xil_printf("DEMO 1 : RISING CH0       PASS");
    xil_printf(" (attempts=%d, input-retries=%d, timeouts=%d)\r\n",
               (int)rising->attempts,
               (int)rising->input_retries,
               (int)rising->timeout_retries);
    xil_printf("DEMO 2 : FALLING CH1      PASS");
    xil_printf(" (attempts=%d, input-retries=%d, timeouts=%d)\r\n",
               (int)falling->attempts,
               (int)falling->input_retries,
               (int)falling->timeout_retries);
    xil_printf("DEMO 3 : MASKED PATTERN   PASS");
    xil_printf(" (attempts=%d, input-retries=%d, timeouts=%d)\r\n",
               (int)pattern->attempts,
               (int)pattern->input_retries,
               (int)pattern->timeout_retries);
    xil_printf("RE-ARM / RE-CAPTURE       PASS\r\n");
    xil_printf("BRAM TIME ORDER           PASS\r\n");
    xil_printf("BRAM FREEZE / ONE-SHOT    PASS\r\n");
    xil_printf("UART 1024-SAMPLE DUMP     PASS\r\n");
    xil_printf("\r\n");
    xil_printf("[PASS] FINAL DEMONSTRATION COMPLETE\r\n");
    xil_printf("========================================\r\n");
}

int main(void)
{
    edge_scope_result_t result;
    demo_result_t rising_result;
    demo_result_t falling_result;
    demo_result_t pattern_result;
    uint32_t global_trigger_count_baseline;

    init_platform();

    xil_printf("\r\n");
    xil_printf("================================================\r\n");
    xil_printf(" EdgeScope-Lite Final Demonstration\r\n");
    xil_printf(" 8-bit Digital State Bus Event/Fault History\r\n");
    xil_printf("================================================\r\n");
    xil_printf("8-channel HW sampling, 512:512 circular capture,");
    xil_printf(" MicroBlaze UART analysis\r\n");

    result = capture_irq_monitor_enable();
    if (result != EDGE_SCOPE_OK) {
        xil_printf("[ERROR] Trace IRQ monitor setup: ");
        print_edge_scope_error(result);
        xil_printf("\r\n");
        cleanup_platform();
        return XST_FAILURE;
    }

    result = force_initial_idle();
    if (result != EDGE_SCOPE_OK) {
        xil_printf("[ERROR] Initial cleanup: ");
        print_edge_scope_error(result);
        xil_printf("\r\n");
        cleanup_platform();
        return XST_FAILURE;
    }

    global_trigger_count_baseline = trigger_count_read();

    result = run_rising_demo(&rising_result);
    if (result == EDGE_SCOPE_OK) {
        result = run_falling_demo(&falling_result);
    }
    if (result == EDGE_SCOPE_OK) {
        result = run_pattern_demo(&pattern_result);
    }

    if ((result == EDGE_SCOPE_OK) &&
        ((trigger_count_read() - global_trigger_count_baseline) != 3u)) {
        xil_printf("[ERROR] Global Trigger Count delta is not 3.\r\n");
        result = EDGE_SCOPE_ERR_HW_STATE;
    }

    if ((result == EDGE_SCOPE_OK) &&
        ((rising_result.passed == 0u) ||
         (falling_result.passed == 0u) ||
         (pattern_result.passed == 0u))) {
        xil_printf("[ERROR] One or more Demo PASS flags are not set.\r\n");
        result = EDGE_SCOPE_ERR_HW_STATE;
    }

    if (result != EDGE_SCOPE_OK) {
        xil_printf("\r\nFINAL DEMONSTRATION FAILED: ");
        print_edge_scope_error(result);
        xil_printf("\r\n");

        abort_clear_disable();
        timeout_timer_stop_and_clear();
        (void)capture_wait_cleared(CLEAR_MAX_POLLS);
        sampler_stop_and_clear();

        cleanup_platform();
        return XST_FAILURE;
    }

    print_final_summary(&rising_result,
                        &falling_result,
                        &pattern_result);

    cleanup_platform();
    return XST_SUCCESS;
}
