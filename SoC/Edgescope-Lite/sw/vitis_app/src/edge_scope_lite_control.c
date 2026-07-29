#include "edge_scope_lite_control.h"

#include "logic_analyzer_regs.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "xparameters.h"

/*
 * ============================================================================
 * 1. Vivado Address Editor와 Vitis xparameters.h 연결
 * ============================================================================
 *
 * 아래 후보 이름은 일반적인 IP Instance 이름을 기준으로 작성했다.
 * 현재 프로젝트의 xparameters.h에서 이름이 다르면 이 구역만 수정하면 된다.
 *
 * 예:
 * #define EDGE_SCOPE_SAMPLER_BASEADDR XPAR_실제_SAMPLER_이름_BASEADDR
 */
#ifndef EDGE_SCOPE_SAMPLER_BASEADDR
#if defined(XPAR_PROBE_SAMPLER_AXI_0_BASEADDR)
#define EDGE_SCOPE_SAMPLER_BASEADDR XPAR_PROBE_SAMPLER_AXI_0_BASEADDR
#elif defined(XPAR_PROBE_SAMPLER_0_BASEADDR)
#define EDGE_SCOPE_SAMPLER_BASEADDR XPAR_PROBE_SAMPLER_0_BASEADDR
#else
#error "Sampler BASEADDR: xparameters.h의 실제 매크로 이름으로 수정하세요."
#endif
#endif

#ifndef EDGE_SCOPE_TRIGGER_BASEADDR
#if defined(XPAR_BASIC_TRIGGER_ENGINE_AXI_0_BASEADDR)
#define EDGE_SCOPE_TRIGGER_BASEADDR XPAR_BASIC_TRIGGER_ENGINE_AXI_0_BASEADDR
#elif defined(XPAR_BASIC_TRIGGER_ENGINE_0_BASEADDR)
#define EDGE_SCOPE_TRIGGER_BASEADDR XPAR_BASIC_TRIGGER_ENGINE_0_BASEADDR
#else
#error "Trigger BASEADDR: xparameters.h의 실제 매크로 이름으로 수정하세요."
#endif
#endif

#ifndef EDGE_SCOPE_TRACE_BASEADDR
#if defined(XPAR_CIRCULAR_TRACE_BUFFER_AXI_0_BASEADDR)
#define EDGE_SCOPE_TRACE_BASEADDR XPAR_CIRCULAR_TRACE_BUFFER_AXI_0_BASEADDR
#elif defined(XPAR_CIRCULAR_TRACE_BUFFER_0_BASEADDR)
#define EDGE_SCOPE_TRACE_BASEADDR XPAR_CIRCULAR_TRACE_BUFFER_0_BASEADDR
#else
#error "Trace Buffer BASEADDR: xparameters.h의 실제 매크로 이름으로 수정하세요."
#endif
#endif

#ifndef EDGE_SCOPE_INTC_BASEADDR
#if defined(XPAR_XINTC_0_BASEADDR)
#define EDGE_SCOPE_INTC_BASEADDR XPAR_XINTC_0_BASEADDR
#elif defined(XPAR_MICROBLAZE_RISCV_0_AXI_INTC_BASEADDR)
#define EDGE_SCOPE_INTC_BASEADDR \
    XPAR_MICROBLAZE_RISCV_0_AXI_INTC_BASEADDR
#else
#error "AXI INTC BASEADDR: xparameters.h의 실제 매크로 이름으로 수정하세요."
#endif
#endif

#ifndef EDGE_SCOPE_TIMER_BASEADDR
#if defined(XPAR_XTMRCTR_0_BASEADDR)
#define EDGE_SCOPE_TIMER_BASEADDR XPAR_XTMRCTR_0_BASEADDR
#elif defined(XPAR_AXI_TIMER_0_BASEADDR)
#define EDGE_SCOPE_TIMER_BASEADDR XPAR_AXI_TIMER_0_BASEADDR
#else
#error "AXI Timer BASEADDR: xparameters.h의 실제 매크로 이름으로 수정하세요."
#endif
#endif

#ifndef EDGE_SCOPE_TIMER_CLOCK_HZ
#if defined(XPAR_XTMRCTR_0_CLOCK_FREQUENCY)
#define EDGE_SCOPE_TIMER_CLOCK_HZ XPAR_XTMRCTR_0_CLOCK_FREQUENCY
#elif defined(XPAR_AXI_TIMER_0_CLOCK_FREQUENCY)
#define EDGE_SCOPE_TIMER_CLOCK_HZ XPAR_AXI_TIMER_0_CLOCK_FREQUENCY
#else
#error "AXI Timer clock: xparameters.h의 실제 매크로 이름으로 수정하세요."
#endif
#endif

#ifndef EDGE_SCOPE_BRAM_BASEADDR
#if defined(XPAR_AXI_BRAM_CTRL_0_BASEADDR)
#define EDGE_SCOPE_BRAM_BASEADDR XPAR_AXI_BRAM_CTRL_0_BASEADDR
#else
/*
 * Day 2에서 확인한 BRAM 주소. Address Editor가 바뀌었다면 반드시 함께 수정한다.
 */
#define EDGE_SCOPE_BRAM_BASEADDR 0xC0000000u
#endif
#endif

/*
 * ============================================================================
 * 2. 내부 MMIO 보조 함수
 * ============================================================================
 *
 * AXI4-Lite Register의 실제 byte 주소는 BASEADDR + OFFSET으로 계산한다.
 * Xil_In32/Xil_Out32를 한곳에서 사용해 상위 제어 함수의 의미를 명확히 한다.
 */
static uint32_t reg_read(uint32_t base_addr, uint32_t offset)
{
    return Xil_In32(base_addr + offset);
}

static void reg_write(uint32_t base_addr, uint32_t offset, uint32_t value)
{
    Xil_Out32(base_addr + offset, value);
}

/*
 * 함수 요약: 지정한 Physical BRAM Word를 32-bit 원본 그대로 읽음
 */
static uint32_t trace_bram_word_read(uint32_t physical_index)
{
    uint32_t byte_offset =
        physical_index * (EDGE_SCOPE_BRAM_WORD_BITS / 8u);

    return Xil_In32(EDGE_SCOPE_BRAM_BASEADDR + byte_offset);
}

/*
 * 함수 요약: Sampler를 정지시키면서 Divider Counter와 최근 Sample을 초기화
 *
 * CONTROL[0] ENABLE은 저장 비트이고 CONTROL[1] SOFT_CLEAR는 W1P 비트이다.
 * SOFT_CLEAR만 쓰면 ENABLE에는 0이 쓰이므로 Sampler가 정지된 상태에서
 * 1-clock Clear Pulse가 발생한다.
 */
void sampler_stop_and_clear(void)
{
    reg_write(EDGE_SCOPE_SAMPLER_BASEADDR,
              SAMPLER_REG_CONTROL,
              SAMPLER_CONTROL_SOFT_CLEAR);
}

/*
 * 함수 요약: Sample Divider와 8-bit Channel Mask를 CONFIG에 설정
 *
 * 이 함수는 설정만 저장하며 Sampler를 시작하지 않는다.
 * Divider와 Mask를 먼저 확정한 뒤 sampler_enable()을 호출해야 한다.
 */
edge_scope_result_t sampler_config(uint32_t divider_sel,
                                   uint8_t channel_mask)
{
    uint32_t config;

    if (divider_sel > SAMPLER_DIVIDE_BY_8) {
        return EDGE_SCOPE_ERR_INVALID_ARG;
    }

    config = (divider_sel & SAMPLER_CONFIG_DIVIDER_MASK)
           | (((uint32_t)channel_mask << SAMPLER_CONFIG_CHANNEL_SHIFT)
              & SAMPLER_CONFIG_CHANNEL_MASK);

    reg_write(EDGE_SCOPE_SAMPLER_BASEADDR, SAMPLER_REG_CONFIG, config);

    return EDGE_SCOPE_OK;
}

/*
 * 함수 요약: 저장된 Divider/Mask 설정으로 Sample 생성을 시작
 */
void sampler_enable(void)
{
    reg_write(EDGE_SCOPE_SAMPLER_BASEADDR,
              SAMPLER_REG_CONTROL,
              SAMPLER_CONTROL_ENABLE);
}

/*
 * 함수 요약: Sampler를 정지하되 누적 Counter와 설정값은 유지
 */
void sampler_disable(void)
{
    reg_write(EDGE_SCOPE_SAMPLER_BASEADDR, SAMPLER_REG_CONTROL, 0u);
}

/*
 * 함수 요약: Sampler CONTROL Register 원본 반환
 */
uint32_t sampler_control_read(void)
{
    return reg_read(EDGE_SCOPE_SAMPLER_BASEADDR, SAMPLER_REG_CONTROL);
}

/*
 * 함수 요약: Sampler CONFIG Register 원본 반환
 */
uint32_t sampler_config_read(void)
{
    return reg_read(EDGE_SCOPE_SAMPLER_BASEADDR, SAMPLER_REG_CONFIG);
}

/*
 * 함수 요약: 가장 최근 유효 Sample의 8-bit 값을 반환
 */
uint32_t sampler_last_sample_read(void)
{
    return reg_read(EDGE_SCOPE_SAMPLER_BASEADDR,
                    SAMPLER_REG_LAST_SAMPLE) & 0xFFu;
}

/*
 * 함수 요약: SOFT_CLEAR 이후 생성된 유효 Sample의 누적 횟수를 반환
 */
uint32_t sampler_sample_count_read(void)
{
    return reg_read(EDGE_SCOPE_SAMPLER_BASEADDR,
                    SAMPLER_REG_SAMPLE_COUNT);
}

/*
 * 함수 요약: 현재 Sample Count를 기준으로 추가 valid Sample 수만큼 대기
 *
 * 32-bit Counter의 unsigned 차이를 사용하므로 대기 중 한 번의 Counter
 * Wrap이 발생해도 정상 동작한다. max_poll_count가 0이면 무제한 대기한다.
 * observed_sample_count가 NULL이 아니면 실제 증가량(overshoot 포함)을 돌려준다.
 */
edge_scope_result_t sampler_wait_samples(uint32_t additional_sample_count,
                                         uint32_t max_poll_count,
                                         uint32_t *observed_sample_count)
{
    uint32_t start_count = sampler_sample_count_read();
    uint32_t sample_delta = 0u;
    uint32_t poll_count = 0u;

    if (observed_sample_count != 0) {
        *observed_sample_count = 0u;
    }

    while (sample_delta < additional_sample_count) {
        sample_delta = sampler_sample_count_read() - start_count;

        if ((sample_delta < additional_sample_count) &&
            (max_poll_count != 0u) &&
            (++poll_count >= max_poll_count)) {
            if (observed_sample_count != 0) {
                *observed_sample_count = sample_delta;
            }

            return EDGE_SCOPE_ERR_TIMEOUT;
        }
    }

    if (observed_sample_count != 0) {
        *observed_sample_count = sample_delta;
    }

    return EDGE_SCOPE_OK;
}

/*
 * 함수 요약: Trigger의 Armed/Triggered 상태와 이전 Sample 비교 기준을 초기화
 *
 * CLEAR는 W1P이므로 1을 한 번 쓰는 것만으로 1-clock Pulse가 만들어진다.
 */
void trigger_clear(void)
{
    reg_write(EDGE_SCOPE_TRIGGER_BASEADDR,
              TRIGGER_REG_CONTROL,
              TRIGGER_CONTROL_CLEAR);
}

/*
 * 함수 요약: Rising/Falling/Pattern 중 한 Trigger 조건을 Register에 설정
 *
 * Edge Mode에서는 edge_channel을 사용한다.
 * Pattern Mode에서는 pattern_value와 pattern_mask를 사용하며,
 * pattern_mask=0은 모든 비트를 무시하므로 잘못된 조건으로 처리한다.
 *
 * PATTERN을 먼저 쓰고 CONFIG를 나중에 써서 Trigger Mode가 마지막에 확정되게 한다.
 * 이 함수는 Trigger를 Arm하지 않는다.
 */
edge_scope_result_t trigger_config(uint32_t mode,
                                   uint32_t edge_channel,
                                   uint8_t pattern_value,
                                   uint8_t pattern_mask)
{
    uint32_t config;
    uint32_t pattern;

    if ((mode > TRIGGER_MODE_PATTERN) || (edge_channel >= 8u)) {
        return EDGE_SCOPE_ERR_INVALID_ARG;
    }

    if ((mode == TRIGGER_MODE_PATTERN) && (pattern_mask == 0u)) {
        return EDGE_SCOPE_ERR_INVALID_ARG;
    }

    config = (mode & TRIGGER_CONFIG_MODE_MASK)
           | ((edge_channel << TRIGGER_CONFIG_CHANNEL_SHIFT)
              & TRIGGER_CONFIG_CHANNEL_MASK);

    pattern = ((uint32_t)pattern_value & TRIGGER_PATTERN_VALUE_MASK)
            | (((uint32_t)pattern_mask << TRIGGER_PATTERN_MASK_SHIFT)
               & TRIGGER_PATTERN_MASK_MASK);

    reg_write(EDGE_SCOPE_TRIGGER_BASEADDR, TRIGGER_REG_PATTERN, pattern);
    reg_write(EDGE_SCOPE_TRIGGER_BASEADDR, TRIGGER_REG_CONFIG, config);

    return EDGE_SCOPE_OK;
}

/*
 * 함수 요약: 현재 설정된 Trigger 조건으로 감시 시작
 *
 * ARM은 W1P이므로 별도의 0 쓰기가 필요 없다.
 */
void trigger_arm(void)
{
    reg_write(EDGE_SCOPE_TRIGGER_BASEADDR,
              TRIGGER_REG_CONTROL,
              TRIGGER_CONTROL_ARM);
}

/*
 * 함수 요약: Trigger CONFIG Register 원본 반환
 */
uint32_t trigger_config_read(void)
{
    return reg_read(EDGE_SCOPE_TRIGGER_BASEADDR, TRIGGER_REG_CONFIG);
}

/*
 * 함수 요약: Trigger PATTERN Register 원본 반환
 */
uint32_t trigger_pattern_read(void)
{
    return reg_read(EDGE_SCOPE_TRIGGER_BASEADDR, TRIGGER_REG_PATTERN);
}

/*
 * 함수 요약: Trigger Engine의 ARMED/TRIGGERED 상태 반환
 */
uint32_t trigger_status_read(void)
{
    return reg_read(EDGE_SCOPE_TRIGGER_BASEADDR, TRIGGER_REG_STATUS);
}

/*
 * 함수 요약: Hardware Reset 이후 누적 Trigger 횟수 반환
 *
 * Trigger CLEAR/ARM은 이 Counter를 지우지 않으므로 Capture 전후의 unsigned
 * 차이를 사용해 이번 실행에서 발생한 Trigger 수를 확인해야 한다.
 */
uint32_t trigger_count_read(void)
{
    return reg_read(EDGE_SCOPE_TRIGGER_BASEADDR,
                    TRIGGER_REG_TRIGGER_COUNT);
}

/*
 * 함수 요약: AXI Timer0를 정지시키고 이전 Timeout 상태를 제거
 *
 * TINT는 Write-1-to-Clear이고 LOAD는 TLR0 값을 Counter에 옮기는 명령이다.
 * LOAD 상태에서 정지/초기화한 뒤 LOAD를 내린 DOWN_COUNT 정지 상태로 둔다.
 * ENIT는 쓰지 않으므로 Timer IRQ가 AXI INTC에 발생하지 않는다.
 */
void timeout_timer_stop_and_clear(void)
{
    reg_write(EDGE_SCOPE_TIMER_BASEADDR,
              TIMER_REG_TCSR0,
              TIMER_CSR_TIMEOUT_LOAD);
    reg_write(EDGE_SCOPE_TIMER_BASEADDR,
              TIMER_REG_TCSR0,
              TIMER_CSR_DOWN_COUNT);
}

/*
 * 함수 요약: AXI Timer0를 Polling용 one-shot down counter로 시작
 *
 * AXI Timer down-count interval은 (TLR0 + 2) clock이므로 timeout_ticks - 2를
 * Load한다. 시작 전에 stale TINT를 W1C로 제거하고, 실행 직후 Control 상태와
 * Counter 감소를 확인해 즉시 발생하는 거짓 Timeout을 차단한다.
 */
edge_scope_result_t timeout_timer_start(uint32_t timeout_ticks)
{
    uint32_t status;
    uint32_t count_before;
    uint32_t count_after;

    if (timeout_ticks < 2u) {
        return EDGE_SCOPE_ERR_INVALID_ARG;
    }

    reg_write(EDGE_SCOPE_TIMER_BASEADDR, TIMER_REG_TCSR0, 0u);
    reg_write(EDGE_SCOPE_TIMER_BASEADDR,
              TIMER_REG_TLR0,
              timeout_ticks - 2u);

    if (reg_read(EDGE_SCOPE_TIMER_BASEADDR, TIMER_REG_TLR0) !=
        (timeout_ticks - 2u)) {
        timeout_timer_stop_and_clear();
        return EDGE_SCOPE_ERR_HW_STATE;
    }

    reg_write(EDGE_SCOPE_TIMER_BASEADDR,
              TIMER_REG_TCSR0,
              TIMER_CSR_TIMEOUT_LOAD);

    status = reg_read(EDGE_SCOPE_TIMER_BASEADDR, TIMER_REG_TCSR0);
    if ((status & TIMER_CSR_INT_OCCURRED) != 0u) {
        timeout_timer_stop_and_clear();
        return EDGE_SCOPE_ERR_HW_STATE;
    }

    reg_write(EDGE_SCOPE_TIMER_BASEADDR,
              TIMER_REG_TCSR0,
              TIMER_CSR_TIMEOUT_RUN);

    status = reg_read(EDGE_SCOPE_TIMER_BASEADDR, TIMER_REG_TCSR0);
    if ((status & (TIMER_CSR_CASCADE          |
                    TIMER_CSR_ENABLE_ALL       |
                    TIMER_CSR_ENABLE_PWM       |
                    TIMER_CSR_ENABLE_INTERRUPT |
                    TIMER_CSR_LOAD             |
                    TIMER_CSR_AUTO_RELOAD      |
                    TIMER_CSR_EXTERNAL_CAPTURE |
                    TIMER_CSR_EXTERNAL_GENERATE |
                    TIMER_CSR_CAPTURE_MODE)) != 0u) {
        timeout_timer_stop_and_clear();
        return EDGE_SCOPE_ERR_HW_STATE;
    }

    /*
     * 매우 짧은 합법적 Timeout은 위 MMIO Read 전에 이미 만료될 수 있다.
     * LOAD 단계에서 stale TINT=0을 확인했으므로 여기의 TINT=1은 정상 만료다.
     */
    if ((status & TIMER_CSR_INT_OCCURRED) != 0u) {
        return EDGE_SCOPE_OK;
    }

    if ((status & TIMER_CSR_TIMEOUT_RUN) != TIMER_CSR_TIMEOUT_RUN) {
        timeout_timer_stop_and_clear();
        return EDGE_SCOPE_ERR_HW_STATE;
    }

    count_before = reg_read(EDGE_SCOPE_TIMER_BASEADDR, TIMER_REG_TCR0);
    count_after = reg_read(EDGE_SCOPE_TIMER_BASEADDR, TIMER_REG_TCR0);

    if (count_after >= count_before) {
        /*
         * 두 Counter Read 사이 Terminal Count에 도달한 경우도 정상이다.
         * TINT가 없는데 Counter가 감소하지 않을 때만 Timer 고장으로 본다.
         */
        if (timeout_timer_expired() != 0u) {
            return EDGE_SCOPE_OK;
        }

        timeout_timer_stop_and_clear();
        return EDGE_SCOPE_ERR_HW_STATE;
    }

    return EDGE_SCOPE_OK;
}

/*
 * 함수 요약: Timer0 Terminal Count 발생 여부(TINT)를 Boolean으로 반환
 */
uint32_t timeout_timer_expired(void)
{
    return ((timeout_timer_status_read() & TIMER_CSR_INT_OCCURRED) != 0u)
           ? 1u
           : 0u;
}

/*
 * 함수 요약: Timer0 Control/Status Register 원본 반환
 */
uint32_t timeout_timer_status_read(void)
{
    return reg_read(EDGE_SCOPE_TIMER_BASEADDR, TIMER_REG_TCSR0);
}

/*
 * 함수 요약: Timer0의 32-bit Load Register 값 반환
 */
uint32_t timeout_timer_load_read(void)
{
    return reg_read(EDGE_SCOPE_TIMER_BASEADDR, TIMER_REG_TLR0);
}

/*
 * 함수 요약: Timer0의 현재 32-bit Counter 값 반환
 */
uint32_t timeout_timer_count_read(void)
{
    return reg_read(EDGE_SCOPE_TIMER_BASEADDR, TIMER_REG_TCR0);
}

/*
 * 함수 요약: xparameters.h에서 생성된 AXI Timer 입력 Clock(Hz) 반환
 */
uint32_t timeout_timer_clock_hz_read(void)
{
    return (uint32_t)EDGE_SCOPE_TIMER_CLOCK_HZ;
}

/*
 * 함수 요약: DONE 상태와 완료 IRQ를 해제하고 Trace Buffer를 IDLE로 복귀
 *
 * CLEAR_DONE은 정상 Capture 완료 후 사용한다.
 * Capture가 진행 중일 때 강제로 정지하려면 capture_abort()를 사용한다.
 */
void capture_clear(void)
{
    reg_write(EDGE_SCOPE_TRACE_BASEADDR,
              TRACE_REG_CONTROL,
              TRACE_CONTROL_CLEAR_DONE);
}

/*
 * 함수 요약: 진행 중인 Capture를 즉시 중단하고 상태 Latch/IRQ를 초기화
 *
 * BRAM 안의 기존 데이터는 지워지지 않지만, Trace Buffer 제어 상태는 IDLE이 된다.
 */
void capture_abort(void)
{
    reg_write(EDGE_SCOPE_TRACE_BASEADDR,
              TRACE_REG_CONTROL,
              TRACE_CONTROL_ABORT);
}

/*
 * 함수 요약: Trace Buffer를 PREFILL 상태로 진입시켜 Capture 시작
 *
 * ARM은 W1P이며 Busy 상태에서 추가 ARM 명령은 Hardware가 무시한다.
 */
void capture_arm(void)
{
    reg_write(EDGE_SCOPE_TRACE_BASEADDR,
              TRACE_REG_CONTROL,
              TRACE_CONTROL_ARM);
}

/*
 * 함수 요약: Trace Buffer의 BUSY/PRE_READY/TRIGGERED/DONE 상태 반환
 */
uint32_t capture_status_read(void)
{
    return reg_read(EDGE_SCOPE_TRACE_BASEADDR, TRACE_REG_STATUS);
}

/*
 * 함수 요약: CPU IRQ 출력은 막은 채 AXI INTC의 Hardware 입력 관측만 활성화
 *
 * MER.HIE=1이어야 외부 irq_o가 ISR에 반영된다. Polling 시험이므로 ME=0을
 * 유지하여 CPU Interrupt Handler 없이도 raw ISR만 안전하게 검사한다.
 */
edge_scope_result_t capture_irq_monitor_enable(void)
{
    uint32_t master_enable;

    reg_write(EDGE_SCOPE_INTC_BASEADDR,
              INTC_REG_MER,
              INTC_MER_HARDWARE_ENABLE);

    master_enable = reg_read(EDGE_SCOPE_INTC_BASEADDR, INTC_REG_MER);

    if (((master_enable & INTC_MER_HARDWARE_ENABLE) == 0u) ||
        ((master_enable & INTC_MER_MASTER_ENABLE) != 0u)) {
        return EDGE_SCOPE_ERR_HW_STATE;
    }

    return EDGE_SCOPE_OK;
}

/*
 * 함수 요약: AXI INTC에서 Circular Trace Buffer의 raw IRQ 상태 Latch 반환
 *
 * 현재 Hardware Design은 Trace irq_o를 AXI INTC input 0에 level-high로
 * 연결한다. IPR은 IER에 의해 Mask될 수 있으므로 HIE가 활성화된 raw ISR을
 * 직접 읽는다. Source 해제 후 IAR Acknowledge 전에는 1이 유지될 수 있다.
 */
uint32_t capture_irq_active_read(void)
{
    uint32_t interrupt_status =
        reg_read(EDGE_SCOPE_INTC_BASEADDR, INTC_REG_ISR);

    return ((interrupt_status & EDGE_SCOPE_TRACE_IRQ_MASK) != 0u) ? 1u : 0u;
}

/*
 * 함수 요약: Trace IRQ source를 내린 뒤 AXI INTC input 0을 Acknowledge
 *
 * Level IRQ의 근본 해제는 먼저 capture_clear()/capture_abort()로 irq_o를
 * Low로 만드는 것이다. 이 함수는 Source가 내려간 뒤 INTC의 IAR에 쓴다.
 */
void capture_irq_acknowledge(void)
{
    reg_write(EDGE_SCOPE_INTC_BASEADDR,
              INTC_REG_IAR,
              EDGE_SCOPE_TRACE_IRQ_MASK);
}

/*
 * 함수 요약: Pre-trigger 512 Sample 확보(PRE_READY=1)까지 Polling
 *
 * max_poll_count가 0이면 횟수 제한 없이 기다린다.
 * Capture가 예상과 달리 중지되면 HW_STATE 오류를 반환한다.
 */
edge_scope_result_t capture_wait_pre_ready(uint32_t max_poll_count)
{
    uint32_t poll_count = 0u;

    while (1) {
        uint32_t status = capture_status_read();

        if (((status & TRACE_STATUS_BUSY) == 0u) ||
            ((status & TRACE_STATUS_DONE) != 0u)) {
            return EDGE_SCOPE_ERR_HW_STATE;
        }

        if ((status & TRACE_STATUS_PRE_READY) != 0u) {
            return EDGE_SCOPE_OK;
        }

        if ((max_poll_count != 0u) && (++poll_count >= max_poll_count)) {
            return EDGE_SCOPE_ERR_TIMEOUT;
        }
    }
}

/*
 * 함수 요약: Trigger 이후 Post-trigger 저장이 끝나 DONE=1이 될 때까지 Polling
 *
 * max_poll_count가 0이면 횟수 제한 없이 기다린다.
 * 이 단계에서는 단순 Polling Count를 사용하고, 실제 시간 기반 Timeout은
 * 다음 단계에서 AXI Timer와 연결한다.
 */
edge_scope_result_t capture_wait_done(uint32_t max_poll_count)
{
    uint32_t poll_count = 0u;

    while (1) {
        uint32_t status = capture_status_read();

        if ((status & TRACE_STATUS_DONE) != 0u) {
            return EDGE_SCOPE_OK;
        }

        if ((status & TRACE_STATUS_BUSY) == 0u) {
            return EDGE_SCOPE_ERR_HW_STATE;
        }

        if ((max_poll_count != 0u) && (++poll_count >= max_poll_count)) {
            return EDGE_SCOPE_ERR_TIMEOUT;
        }
    }
}

/*
 * 함수 요약: CLEAR_DONE/ABORT 후 Trace IDLE 및 IRQ 해제를 순서대로 확인
 *
 * PRE_READY/TRIGGERED Bit의 DONE 이후 보존 정책은 Hardware 구현에 맡기고,
 * 재ARM의 필수 조건인 IDLE(BUSY=0, DONE=0)과 IRQ 해제만 검사한다.
 * Source가 내려간 IDLE을 먼저 확인하고 IAR를 Acknowledge한 뒤 raw ISR=0을
 * 별도로 Polling하여 level IRQ 처리 순서를 지킨다.
 */
edge_scope_result_t capture_wait_cleared(uint32_t max_poll_count)
{
    uint32_t poll_count = 0u;

    while (1) {
        uint32_t status = capture_status_read();

        if ((status & (TRACE_STATUS_BUSY | TRACE_STATUS_DONE)) == 0u) {
            break;
        }

        if ((max_poll_count != 0u) && (++poll_count >= max_poll_count)) {
            return EDGE_SCOPE_ERR_TIMEOUT;
        }
    }

    capture_irq_acknowledge();
    poll_count = 0u;

    while (capture_irq_active_read() != 0u) {
        if ((max_poll_count != 0u) && (++poll_count >= max_poll_count)) {
            return EDGE_SCOPE_ERR_TIMEOUT;
        }
    }

    return EDGE_SCOPE_OK;
}

/*
 * 함수 요약: Capture 결과 확인에 필요한 상태, 주소, 깊이 정보를 구조체에 저장
 */
void capture_read_meta(edge_scope_capture_meta_t *meta)
{
    uint32_t capture_info;

    if (meta == 0) {
        return;
    }

    capture_info = reg_read(EDGE_SCOPE_TRACE_BASEADDR,
                            TRACE_REG_CAPTURE_INFO);

    meta->status = capture_status_read();
    meta->start_addr =
        reg_read(EDGE_SCOPE_TRACE_BASEADDR,
                 TRACE_REG_START_ADDR) & TRACE_ADDR_MASK;
    meta->trigger_addr =
        reg_read(EDGE_SCOPE_TRACE_BASEADDR,
                 TRACE_REG_TRIGGER_ADDR) & TRACE_ADDR_MASK;
    meta->write_addr =
        reg_read(EDGE_SCOPE_TRACE_BASEADDR,
                 TRACE_REG_WRITE_ADDR) & TRACE_ADDR_MASK;
    meta->depth = capture_info & TRACE_CAPTURE_INFO_DEPTH_MASK;
    meta->trigger_index =
        (capture_info & TRACE_CAPTURE_INFO_TRIG_MASK)
        >> TRACE_CAPTURE_INFO_TRIG_SHIFT;
    meta->trigger_count =
        reg_read(EDGE_SCOPE_TRIGGER_BASEADDR,
                 TRIGGER_REG_TRIGGER_COUNT);
}

/*
 * 함수 요약: DONE Capture의 1,024개 Probe Sample을 기대 Step 파형과 비교
 *
 * START_ADDR를 기준으로 시간순 재정렬하여 Logical Index 0~511에는
 * before_sample, 512~1023에는 after_sample을 기대한다. BRAM의 공개 Probe
 * Payload인 Word[7:0]만 비교하고 511/512/513 실제값을 결과에 보관한다.
 */
edge_scope_result_t trace_validate_transition_capture(
    uint8_t before_sample,
    uint8_t after_sample,
    edge_scope_trace_check_t *check)
{
    edge_scope_capture_meta_t meta;
    uint32_t logical_index;
    uint32_t status;

    if (check == 0) {
        return EDGE_SCOPE_ERR_INVALID_ARG;
    }

    check->mismatch_count = 0u;
    check->first_mismatch_index = EDGE_SCOPE_CAPTURE_DEPTH;
    check->expected_word = 0u;
    check->actual_word = 0u;
    check->window_sample_511 = 0u;
    check->window_sample_512 = 0u;
    check->window_sample_513 = 0u;

    capture_read_meta(&meta);

    if ((meta.status & TRACE_STATUS_DONE) == 0u) {
        return EDGE_SCOPE_ERR_NOT_DONE;
    }

    if ((meta.status & TRACE_STATUS_BUSY) != 0u) {
        return EDGE_SCOPE_ERR_HW_STATE;
    }

    if ((meta.depth != EDGE_SCOPE_CAPTURE_DEPTH) ||
        (meta.trigger_index != EDGE_SCOPE_TRIGGER_INDEX)) {
        return EDGE_SCOPE_ERR_HW_STATE;
    }

    for (logical_index = 0u;
         logical_index < EDGE_SCOPE_CAPTURE_DEPTH;
         ++logical_index) {
        uint32_t physical_index =
            (meta.start_addr + logical_index) & TRACE_ADDR_MASK;
        uint32_t actual_word = trace_bram_word_read(physical_index);
        uint32_t actual_sample = actual_word & 0xFFu;
        uint32_t expected_sample =
            (logical_index < EDGE_SCOPE_TRIGGER_INDEX)
            ? (uint32_t)before_sample
            : (uint32_t)after_sample;

        if (logical_index == (EDGE_SCOPE_TRIGGER_INDEX - 1u)) {
            check->window_sample_511 = actual_sample;
        } else if (logical_index == EDGE_SCOPE_TRIGGER_INDEX) {
            check->window_sample_512 = actual_sample;
        } else if (logical_index == (EDGE_SCOPE_TRIGGER_INDEX + 1u)) {
            check->window_sample_513 = actual_sample;
        } else {
            /* No action required for the compact three-sample report. */
        }

        if (actual_sample != expected_sample) {
            if (check->mismatch_count == 0u) {
                check->first_mismatch_index = logical_index;
                check->expected_word = expected_sample;
                check->actual_word = actual_word;
            }

            ++check->mismatch_count;
        }
    }

    status = capture_status_read();
    if (((status & TRACE_STATUS_DONE) == 0u) ||
        ((status & TRACE_STATUS_BUSY) != 0u)) {
        return EDGE_SCOPE_ERR_HW_STATE;
    }

    if (check->mismatch_count != 0u) {
        return EDGE_SCOPE_ERR_DATA_MISMATCH;
    }

    return EDGE_SCOPE_OK;
}

/*
 * 함수 요약: DONE 상태의 BRAM 1,024개 Physical Word를 기준 배열에 저장
 *
 * Capture 전후 상태를 검사해 BUSY=0, DONE=1인 정지 상태에서만 Snapshot한다.
 * 8-bit Sample뿐 아니라 BRAM Word 전체 32-bit를 보존하여 비교 강도를 높인다.
 */
edge_scope_result_t trace_snapshot_read(uint32_t *snapshot,
                                        uint32_t snapshot_word_count)
{
    uint32_t physical_index;
    uint32_t status;

    if ((snapshot == 0) ||
        (snapshot_word_count != EDGE_SCOPE_CAPTURE_DEPTH)) {
        return EDGE_SCOPE_ERR_INVALID_ARG;
    }

    status = capture_status_read();
    if ((status & TRACE_STATUS_DONE) == 0u) {
        return EDGE_SCOPE_ERR_NOT_DONE;
    }

    if ((status & TRACE_STATUS_BUSY) != 0u) {
        return EDGE_SCOPE_ERR_HW_STATE;
    }

    for (physical_index = 0u;
         physical_index < EDGE_SCOPE_CAPTURE_DEPTH;
         ++physical_index) {
        snapshot[physical_index] =
            trace_bram_word_read(physical_index);
    }

    status = capture_status_read();
    if (((status & TRACE_STATUS_DONE) == 0u) ||
        ((status & TRACE_STATUS_BUSY) != 0u)) {
        return EDGE_SCOPE_ERR_HW_STATE;
    }

    return EDGE_SCOPE_OK;
}

/*
 * 함수 요약: 현재 BRAM과 기준 배열의 1,024개 Physical Word를 완전 비교
 *
 * 모든 Word를 끝까지 비교해 변경된 Word 수와 첫 변경 위치/값을 제공한다.
 */
edge_scope_result_t trace_snapshot_verify(
    const uint32_t *snapshot,
    uint32_t snapshot_word_count,
    edge_scope_trace_diff_t *difference)
{
    uint32_t physical_index;
    uint32_t status;

    if ((snapshot == 0) ||
        (snapshot_word_count != EDGE_SCOPE_CAPTURE_DEPTH) ||
        (difference == 0)) {
        return EDGE_SCOPE_ERR_INVALID_ARG;
    }

    difference->mismatch_count = 0u;
    difference->first_mismatch_index = EDGE_SCOPE_CAPTURE_DEPTH;
    difference->expected_word = 0u;
    difference->actual_word = 0u;

    status = capture_status_read();
    if ((status & TRACE_STATUS_DONE) == 0u) {
        return EDGE_SCOPE_ERR_NOT_DONE;
    }

    if ((status & TRACE_STATUS_BUSY) != 0u) {
        return EDGE_SCOPE_ERR_HW_STATE;
    }

    for (physical_index = 0u;
         physical_index < EDGE_SCOPE_CAPTURE_DEPTH;
         ++physical_index) {
        uint32_t actual_word = trace_bram_word_read(physical_index);

        if (actual_word != snapshot[physical_index]) {
            if (difference->mismatch_count == 0u) {
                difference->first_mismatch_index = physical_index;
                difference->expected_word = snapshot[physical_index];
                difference->actual_word = actual_word;
            }

            ++difference->mismatch_count;
        }
    }

    status = capture_status_read();
    if (((status & TRACE_STATUS_DONE) == 0u) ||
        ((status & TRACE_STATUS_BUSY) != 0u)) {
        return EDGE_SCOPE_ERR_HW_STATE;
    }

    if (difference->mismatch_count != 0u) {
        return EDGE_SCOPE_ERR_DATA_CHANGED;
    }

    return EDGE_SCOPE_OK;
}

/*
 * 함수 요약: 두 Capture Metadata가 같은 정지 Trace를 가리키는지 확인
 */
static uint32_t trace_meta_equal(const edge_scope_capture_meta_t *left,
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
 * 함수 요약: DONE Capture의 일부를 START_ADDR 기준 시간순으로 읽음
 */
edge_scope_result_t trace_logical_window_read(uint32_t first_index,
                                              uint32_t sample_count,
                                              uint8_t *samples)
{
    edge_scope_capture_meta_t meta_before;
    edge_scope_capture_meta_t meta_after;
    uint32_t sample_offset;

    if ((samples == 0) ||
        (sample_count == 0u) ||
        (first_index >= EDGE_SCOPE_CAPTURE_DEPTH) ||
        (sample_count > (EDGE_SCOPE_CAPTURE_DEPTH - first_index))) {
        return EDGE_SCOPE_ERR_INVALID_ARG;
    }

    capture_read_meta(&meta_before);

    if ((meta_before.status & TRACE_STATUS_DONE) == 0u) {
        return EDGE_SCOPE_ERR_NOT_DONE;
    }

    if (((meta_before.status & TRACE_STATUS_BUSY) != 0u) ||
        (meta_before.depth != EDGE_SCOPE_CAPTURE_DEPTH) ||
        (meta_before.trigger_index != EDGE_SCOPE_TRIGGER_INDEX)) {
        return EDGE_SCOPE_ERR_HW_STATE;
    }

    for (sample_offset = 0u;
         sample_offset < sample_count;
         ++sample_offset) {
        uint32_t logical_index = first_index + sample_offset;
        uint32_t physical_index =
            (meta_before.start_addr + logical_index) & TRACE_ADDR_MASK;

        samples[sample_offset] =
            (uint8_t)(trace_bram_word_read(physical_index) & 0xFFu);
    }

    capture_read_meta(&meta_after);

    if (((meta_after.status & TRACE_STATUS_DONE) == 0u) ||
        ((meta_after.status & TRACE_STATUS_BUSY) != 0u) ||
        (trace_meta_equal(&meta_before, &meta_after) == 0u)) {
        return EDGE_SCOPE_ERR_HW_STATE;
    }

    return EDGE_SCOPE_OK;
}

/*
 * 함수 요약: START_ADDR 기준 시간순 1,024 Word의 FNV-1a Checksum 계산
 *
 * 각 32-bit Word를 little-endian Byte 순서(0, 8, 16, 24 bit)로 Hash한다.
 * 계산 전후 Metadata가 같아야 Checksum을 유효한 결과로 반환한다.
 */
edge_scope_result_t trace_checksum_read(uint32_t *checksum)
{
    edge_scope_capture_meta_t meta_before;
    edge_scope_capture_meta_t meta_after;
    uint32_t hash = 2166136261u;
    uint32_t logical_index;

    if (checksum == 0) {
        return EDGE_SCOPE_ERR_INVALID_ARG;
    }

    capture_read_meta(&meta_before);

    if ((meta_before.status & TRACE_STATUS_DONE) == 0u) {
        return EDGE_SCOPE_ERR_NOT_DONE;
    }

    if (((meta_before.status & TRACE_STATUS_BUSY) != 0u) ||
        (meta_before.depth != EDGE_SCOPE_CAPTURE_DEPTH) ||
        (meta_before.trigger_index != EDGE_SCOPE_TRIGGER_INDEX)) {
        return EDGE_SCOPE_ERR_HW_STATE;
    }

    for (logical_index = 0u;
         logical_index < EDGE_SCOPE_CAPTURE_DEPTH;
         ++logical_index) {
        uint32_t physical_index =
            (meta_before.start_addr + logical_index) & TRACE_ADDR_MASK;
        uint32_t word = trace_bram_word_read(physical_index);
        uint32_t byte_shift;

        for (byte_shift = 0u;
             byte_shift < EDGE_SCOPE_BRAM_WORD_BITS;
             byte_shift += 8u) {
            hash ^= (word >> byte_shift) & 0xFFu;
            hash *= 16777619u;
        }
    }

    capture_read_meta(&meta_after);

    if (((meta_after.status & TRACE_STATUS_DONE) == 0u) ||
        ((meta_after.status & TRACE_STATUS_BUSY) != 0u) ||
        (trace_meta_equal(&meta_before, &meta_after) == 0u)) {
        return EDGE_SCOPE_ERR_HW_STATE;
    }

    *checksum = hash;

    return EDGE_SCOPE_OK;
}

/*
 * 함수 요약: 32-bit 값을 지정한 자리수만큼 16진수로 UART 출력
 *
 * xil_printf 구현별 Field Width 지원 차이를 피하기 위해 각 Digit를 직접 출력한다.
 */
static void uart_print_hex_fixed(uint32_t value, uint32_t digits)
{
    static const char hex_table[] = "0123456789ABCDEF";
    uint32_t index;

    for (index = digits; index > 0u; --index) {
        uint32_t shift = (index - 1u) * 4u;
        uint32_t nibble = (value >> shift) & 0xFu;

        xil_printf("%c", hex_table[nibble]);
    }
}

/*
 * 함수 요약: 0~9999 값을 네 자리 10진수로 UART 출력
 *
 * Sample Logical Index 0~1023을 0000~1023 형식으로 표시한다.
 */
static void uart_print_dec4(uint32_t value)
{
    xil_printf("%c", (char)('0' + ((value / 1000u) % 10u)));
    xil_printf("%c", (char)('0' + ((value / 100u) % 10u)));
    xil_printf("%c", (char)('0' + ((value / 10u) % 10u)));
    xil_printf("%c", (char)('0' + (value % 10u)));
}

/*
 * 함수 요약: Capture된 1,024 Sample을 시간순 Logical Index로 재정렬해 출력
 *
 * Circular BRAM의 실제 주소는
 *   physical = (START_ADDR + logical_index) & 0x3FF
 * 로 계산한다.
 *
 * BRAM Word[7:0]만 실제 Probe Sample이며 Logical Index 512에
 * <TRIGGER> 표시를 붙인다. Capture 중 BRAM Read는 보장되지 않으므로
 * DONE=1을 먼저 확인한다.
 */
edge_scope_result_t trace_dump_hex(void)
{
    edge_scope_capture_meta_t meta_before;
    edge_scope_capture_meta_t meta_after;
    uint32_t logical_index;

    capture_read_meta(&meta_before);

    if ((meta_before.status & TRACE_STATUS_DONE) == 0u) {
        return EDGE_SCOPE_ERR_NOT_DONE;
    }

    if (((meta_before.status & TRACE_STATUS_BUSY) != 0u) ||
        (meta_before.depth != EDGE_SCOPE_CAPTURE_DEPTH) ||
        (meta_before.trigger_index != EDGE_SCOPE_TRIGGER_INDEX)) {
        return EDGE_SCOPE_ERR_HW_STATE;
    }

    xil_printf("\r\nEDGE_SCOPE_LITE\r\n");

    xil_printf("START_ADDR=0x");
    uart_print_hex_fixed(meta_before.start_addr, 3u);
    xil_printf("\r\n");

    xil_printf("TRIGGER_ADDR=0x");
    uart_print_hex_fixed(meta_before.trigger_addr, 3u);
    xil_printf("\r\n");

    xil_printf("WRITE_ADDR=0x");
    uart_print_hex_fixed(meta_before.write_addr, 3u);
    xil_printf("\r\n");

    xil_printf("TRIGGER_INDEX=");
    uart_print_dec4(meta_before.trigger_index);
    xil_printf("\r\n\r\n");

    for (logical_index = 0u;
         logical_index < EDGE_SCOPE_CAPTURE_DEPTH;
         ++logical_index) {
        uint32_t physical_index =
            (meta_before.start_addr + logical_index) & TRACE_ADDR_MASK;
        uint32_t sample =
            trace_bram_word_read(physical_index) & 0xFFu;

        uart_print_dec4(logical_index);
        xil_printf(": ");
        uart_print_hex_fixed(sample, 2u);

        if (logical_index == meta_before.trigger_index) {
            xil_printf(" <TRIGGER>");
        }

        xil_printf("\r\n");
    }

    xil_printf("\r\nCAPTURE_END\r\n");

    capture_read_meta(&meta_after);

    if (((meta_after.status & TRACE_STATUS_DONE) == 0u) ||
        ((meta_after.status & TRACE_STATUS_BUSY) != 0u) ||
        (trace_meta_equal(&meta_before, &meta_after) == 0u)) {
        return EDGE_SCOPE_ERR_HW_STATE;
    }

    return EDGE_SCOPE_OK;
}
