#ifndef VIVADO_ILA_CONFIG_H
#define VIVADO_ILA_CONFIG_H

#include <stdint.h>

#include "xparameters.h"

/*
 * The BSP-generated peripheral name is authoritative.  The fallback is the
 * frozen address assigned by comparison/common/base_soc.tcl and is kept only
 * so the source remains understandable before a BSP has been generated.
 */
#if defined(XPAR_AXI_GPIO_TEST_CTRL_BASEADDR)
#define VIVADO_ILA_TEST_CTRL_BASEADDR XPAR_AXI_GPIO_TEST_CTRL_BASEADDR
#elif defined(XPAR_AXI_GPIO_TEST_CTRL_0_BASEADDR)
#define VIVADO_ILA_TEST_CTRL_BASEADDR XPAR_AXI_GPIO_TEST_CTRL_0_BASEADDR
#elif defined(XPAR_XGPIO_0_BASEADDR)
#define VIVADO_ILA_TEST_CTRL_BASEADDR XPAR_XGPIO_0_BASEADDR
#else
#define VIVADO_ILA_TEST_CTRL_BASEADDR 0x40000000u
#endif

#if defined(XPAR_AXI_TIMER_0_BASEADDR)
#define VIVADO_ILA_TIMER_BASEADDR XPAR_AXI_TIMER_0_BASEADDR
#elif defined(XPAR_XTMRCTR_0_BASEADDR)
#define VIVADO_ILA_TIMER_BASEADDR XPAR_XTMRCTR_0_BASEADDR
#else
#error "The C design BSP did not generate an AXI Timer base address"
#endif

#if defined(XPAR_AXI_TIMER_0_CLOCK_FREQUENCY)
#define VIVADO_ILA_CLOCK_HZ XPAR_AXI_TIMER_0_CLOCK_FREQUENCY
#else
#define VIVADO_ILA_CLOCK_HZ 100000000u
#endif

#define VIVADO_ILA_UART_BAUD         9600u
#define VIVADO_ILA_CAPTURE_DEPTH     1024u
#define VIVADO_ILA_TRIGGER_INDEX     512u
#define VIVADO_ILA_TIMEOUT_TICKS     20000000u
#define VIVADO_ILA_CLEAR_WAIT_TICKS  32u
#define VIVADO_ILA_PULSE_MIN_CYCLES  1u
#define VIVADO_ILA_PULSE_MAX_CYCLES  0x000fffffu

/* Frozen test_pattern_generator.sv test-id mapping. */
#define VIVADO_ILA_TEST_RISING       1u
#define VIVADO_ILA_TEST_FALLING      2u
#define VIVADO_ILA_TEST_PATTERN      3u
#define VIVADO_ILA_TEST_PATTERN_HOLD 4u
#define VIVADO_ILA_TEST_NO_TRIGGER   5u
#define VIVADO_ILA_TEST_PULSE        6u

#endif
