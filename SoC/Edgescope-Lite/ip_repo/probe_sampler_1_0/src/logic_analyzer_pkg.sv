`timescale 1ns/1ps

package logic_analyzer_pkg;
  // Day 1 Frozen v2.1 constants. Package parameters cannot be overridden, so
  // localparam makes the fixed nature of the shared specification explicit.
  localparam int unsigned SPEC_VERSION_MAJOR      = 2;
  localparam int unsigned SPEC_VERSION_MINOR      = 1;
  localparam int unsigned PROBE_WIDTH             = 8;
  localparam int unsigned BRAM_DATA_WIDTH         = 32;
  localparam int unsigned BRAM_ADDR_WIDTH         = 10;
  localparam int unsigned CAPTURE_DEPTH           = 1024;
  localparam int unsigned CAPTURE_MEMORY_BYTES    = 4096;
  localparam int unsigned PRE_TRIGGER_SAMPLES     = 512;
  localparam int unsigned POST_TRIGGER_SAMPLES    = 512;
  localparam int unsigned TRIGGER_LOGICAL_INDEX   = 512;
  localparam int unsigned CSR_DATA_WIDTH          = 32;

  typedef enum logic [1:0] {
    DIVIDE_BY_1 = 2'b00,
    DIVIDE_BY_2 = 2'b01,
    DIVIDE_BY_4 = 2'b10,
    DIVIDE_BY_8 = 2'b11
  } divider_sel_e;

  typedef enum logic [1:0] {
    TRIGGER_DISABLED = 2'b00,
    TRIGGER_RISING   = 2'b01,
    TRIGGER_FALLING  = 2'b10,
    TRIGGER_PATTERN  = 2'b11
  } trigger_mode_e;

  localparam logic [5:0] SAMPLER_REG_CONTROL      = 6'h00;
  localparam logic [5:0] SAMPLER_REG_CONFIG       = 6'h04;
  localparam logic [5:0] SAMPLER_REG_LAST_SAMPLE  = 6'h08;
  localparam logic [5:0] SAMPLER_REG_SAMPLE_COUNT = 6'h0C;

  localparam logic [5:0] TRIGGER_REG_CONTROL       = 6'h00;
  localparam logic [5:0] TRIGGER_REG_CONFIG        = 6'h04;
  localparam logic [5:0] TRIGGER_REG_PATTERN       = 6'h08;
  localparam logic [5:0] TRIGGER_REG_STATUS        = 6'h0C;
  localparam logic [5:0] TRIGGER_REG_TRIGGER_COUNT = 6'h10;

  localparam logic [5:0] TRACE_REG_CONTROL      = 6'h00;
  localparam logic [5:0] TRACE_REG_STATUS       = 6'h04;
  localparam logic [5:0] TRACE_REG_START_ADDR   = 6'h08;
  localparam logic [5:0] TRACE_REG_TRIGGER_ADDR = 6'h0C;
  localparam logic [5:0] TRACE_REG_WRITE_ADDR   = 6'h10;
  localparam logic [5:0] TRACE_REG_CAPTURE_INFO = 6'h14;
endpackage
