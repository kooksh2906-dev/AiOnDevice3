#ifndef CPU_POLLING_CONFIG_H
#define CPU_POLLING_CONFIG_H

#include <stdint.h>

#include "xparameters.h"

/* Frozen addresses from team_a_cpu_polling_comparison_conditions.md. */
#define CPU_POLL_TEST_CTRL_BASEADDR 0x40000000u
#define CPU_POLL_PROBE_BASEADDR     0x40010000u

/*
 * The common Base SoC has not fixed the AXI Timer instance name yet. Add its
 * generated xparameters.h symbol here if it differs from the common names.
 */
#if defined(XPAR_AXI_TIMER_0_BASEADDR)
#define CPU_POLL_TIMER_BASEADDR XPAR_AXI_TIMER_0_BASEADDR
#elif defined(XPAR_XTMRCTR_0_BASEADDR)
#define CPU_POLL_TIMER_BASEADDR XPAR_XTMRCTR_0_BASEADDR
#else
#error "Set CPU_POLL_TIMER_BASEADDR to the frozen common AXI Timer base address"
#endif

#define CPU_POLL_TIMER_HZ             100000000u
#define CPU_POLL_UART_BAUD            9600u
#define CPU_POLL_BENCH_ITERATIONS     10000u
#define CPU_POLL_TIMEOUT_TICKS        10000000u
#define CPU_POLL_TIMEOUT_OBSERVATIONS 100000u
#define CPU_POLL_INTER_TRIAL_TICKS    1000000u

/* Frozen test_pattern_generator.sv test_id mapping. */
#define CPU_POLL_TEST_ID_NOT_SET UINT32_MAX
#define CPU_POLL_TEST_ID_RISING 1u
#define CPU_POLL_TEST_ID_FALLING 2u
#define CPU_POLL_TEST_ID_PATTERN 3u
#define CPU_POLL_TEST_ID_PATTERN_HOLD 4u
#define CPU_POLL_TEST_ID_NO_TRIGGER 5u
#define CPU_POLL_TEST_ID_PULSE 6u

#endif
