#ifndef LOGIC_ANALYZER_REGS_H
#define LOGIC_ANALYZER_REGS_H

#define EDGE_SCOPE_SPEC_VERSION_MAJOR  2u
#define EDGE_SCOPE_SPEC_VERSION_MINOR  1u

/* Probe Sampler: offsets from the Sampler AXI base address. */
#define SAMPLER_REG_CONTROL       0x00u
#define SAMPLER_REG_CONFIG        0x04u
#define SAMPLER_REG_LAST_SAMPLE   0x08u
#define SAMPLER_REG_SAMPLE_COUNT  0x0Cu

#define SAMPLER_CONTROL_ENABLE      (1u << 0)
#define SAMPLER_CONTROL_SOFT_CLEAR  (1u << 1)

#define SAMPLER_CONFIG_DIVIDER_MASK   (0x3u << 0)
#define SAMPLER_CONFIG_CHANNEL_SHIFT  8u
#define SAMPLER_CONFIG_CHANNEL_MASK   (0xFFu << SAMPLER_CONFIG_CHANNEL_SHIFT)

#define SAMPLER_DIVIDE_BY_1  0u
#define SAMPLER_DIVIDE_BY_2  1u
#define SAMPLER_DIVIDE_BY_4  2u
#define SAMPLER_DIVIDE_BY_8  3u

/* Basic Trigger Engine: offsets from the Trigger AXI base address. */
#define TRIGGER_REG_CONTROL        0x00u
#define TRIGGER_REG_CONFIG         0x04u
#define TRIGGER_REG_PATTERN        0x08u
#define TRIGGER_REG_STATUS         0x0Cu
#define TRIGGER_REG_TRIGGER_COUNT  0x10u

#define TRIGGER_CONTROL_ARM    (1u << 0)
#define TRIGGER_CONTROL_CLEAR  (1u << 1)

#define TRIGGER_CONFIG_MODE_MASK     (0x3u << 0)
#define TRIGGER_CONFIG_CHANNEL_SHIFT 8u
#define TRIGGER_CONFIG_CHANNEL_MASK  (0x7u << TRIGGER_CONFIG_CHANNEL_SHIFT)

#define TRIGGER_MODE_DISABLED  0u
#define TRIGGER_MODE_RISING    1u
#define TRIGGER_MODE_FALLING   2u
#define TRIGGER_MODE_PATTERN   3u

#define TRIGGER_PATTERN_VALUE_MASK  (0xFFu << 0)
#define TRIGGER_PATTERN_MASK_SHIFT  8u
#define TRIGGER_PATTERN_MASK_MASK   (0xFFu << TRIGGER_PATTERN_MASK_SHIFT)

#define TRIGGER_STATUS_ARMED     (1u << 0)
#define TRIGGER_STATUS_TRIGGERED (1u << 1)

/* Circular Trace Buffer: offsets from the Trace Buffer AXI base address. */
#define TRACE_REG_CONTROL       0x00u
#define TRACE_REG_STATUS        0x04u
#define TRACE_REG_START_ADDR    0x08u
#define TRACE_REG_TRIGGER_ADDR  0x0Cu
#define TRACE_REG_WRITE_ADDR    0x10u
#define TRACE_REG_CAPTURE_INFO  0x14u

#define TRACE_CONTROL_ARM        (1u << 0)
#define TRACE_CONTROL_CLEAR_DONE (1u << 1)
#define TRACE_CONTROL_ABORT      (1u << 2)

#define TRACE_STATUS_BUSY       (1u << 0)
#define TRACE_STATUS_PRE_READY  (1u << 1)
#define TRACE_STATUS_TRIGGERED  (1u << 2)
#define TRACE_STATUS_DONE       (1u << 3)
#define TRACE_STATUS_ALL        (TRACE_STATUS_BUSY      | \
                                 TRACE_STATUS_PRE_READY | \
                                 TRACE_STATUS_TRIGGERED | \
                                 TRACE_STATUS_DONE)

#define TRACE_ADDR_MASK                0x3FFu
#define TRACE_CAPTURE_INFO_DEPTH_MASK  0x7FFu
#define TRACE_CAPTURE_INFO_TRIG_SHIFT  16u
#define TRACE_CAPTURE_INFO_TRIG_MASK   \
    (0x3FFu << TRACE_CAPTURE_INFO_TRIG_SHIFT)

/*
 * AXI Interrupt Controller
 *
 * Circular Trace Buffer irq_o is connected to AXI INTC input 2.
 * The final demo polls raw ISR with HIE enabled and CPU interrupts disabled.
 */
#define INTC_REG_ISR                  0x00u
#define INTC_REG_IAR                  0x0Cu
#define INTC_REG_MER                  0x1Cu
#define INTC_MER_MASTER_ENABLE        (1u << 0)
#define INTC_MER_HARDWARE_ENABLE      (1u << 1)
#define EDGE_SCOPE_TRACE_IRQ_MASK     (1u << 2)

/*
 * AXI Timer 0
 *
 * Timer0 is used as a polling-only one-shot down counter. ENIT remains
 * disabled so the Timer input does not interfere with the Trace IRQ check.
 */
#define TIMER_REG_TCSR0  0x00u
#define TIMER_REG_TLR0   0x04u
#define TIMER_REG_TCR0   0x08u

#define TIMER_CSR_CASCADE           (1u << 11)
#define TIMER_CSR_ENABLE_ALL        (1u << 10)
#define TIMER_CSR_ENABLE_PWM        (1u << 9)
#define TIMER_CSR_INT_OCCURRED      (1u << 8)
#define TIMER_CSR_ENABLE_TIMER      (1u << 7)
#define TIMER_CSR_ENABLE_INTERRUPT  (1u << 6)
#define TIMER_CSR_LOAD              (1u << 5)
#define TIMER_CSR_AUTO_RELOAD       (1u << 4)
#define TIMER_CSR_EXTERNAL_CAPTURE  (1u << 3)
#define TIMER_CSR_EXTERNAL_GENERATE (1u << 2)
#define TIMER_CSR_DOWN_COUNT        (1u << 1)
#define TIMER_CSR_CAPTURE_MODE      (1u << 0)

#define TIMER_CSR_TIMEOUT_LOAD  (TIMER_CSR_INT_OCCURRED | \
                                 TIMER_CSR_LOAD         | \
                                 TIMER_CSR_DOWN_COUNT)
#define TIMER_CSR_TIMEOUT_RUN   (TIMER_CSR_ENABLE_TIMER | \
                                 TIMER_CSR_DOWN_COUNT)

#define EDGE_SCOPE_PROBE_WIDTH           8u
#define EDGE_SCOPE_BRAM_WORD_BITS       32u
#define EDGE_SCOPE_CAPTURE_DEPTH      1024u
#define EDGE_SCOPE_CAPTURE_BYTES      4096u
#define EDGE_SCOPE_PRE_SAMPLES         512u
#define EDGE_SCOPE_POST_SAMPLES        512u
#define EDGE_SCOPE_TRIGGER_INDEX       512u
#define EDGE_SCOPE_TWO_WRAP_SAMPLES   (2u * EDGE_SCOPE_CAPTURE_DEPTH)
#define EDGE_SCOPE_DEMO_WINDOW_FIRST  \
    (EDGE_SCOPE_TRIGGER_INDEX - 4u)
#define EDGE_SCOPE_DEMO_WINDOW_LAST   \
    (EDGE_SCOPE_TRIGGER_INDEX + 4u)
#define EDGE_SCOPE_DEMO_WINDOW_COUNT  \
    (EDGE_SCOPE_DEMO_WINDOW_LAST - EDGE_SCOPE_DEMO_WINDOW_FIRST + 1u)
#define EDGE_SCOPE_FREEZE_GUARD_SAMPLES \
    (EDGE_SCOPE_CAPTURE_DEPTH + 37u)

#endif
