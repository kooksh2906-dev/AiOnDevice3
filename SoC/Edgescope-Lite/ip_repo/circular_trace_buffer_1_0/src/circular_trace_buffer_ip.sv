`timescale 1ns/1ps

// Vivado IP Packager top level.
// S_AXI controls capture; BRAM_PORTA is the write-side native BRAM master.
// AXI widths are intentionally fixed by the Day 1 common specification so
// the packaged-IP GUI cannot be set to an unsupported register geometry.
module circular_trace_buffer_ip (
  input  logic                      s_axi_aclk,
  input  logic                      s_axi_aresetn,

  input  logic [5:0]                s_axi_awaddr,
  input  logic [2:0]                s_axi_awprot,
  input  logic                      s_axi_awvalid,
  output logic                      s_axi_awready,
  input  logic [31:0]               s_axi_wdata,
  input  logic [3:0]                s_axi_wstrb,
  input  logic                      s_axi_wvalid,
  output logic                      s_axi_wready,
  output logic [1:0]                s_axi_bresp,
  output logic                      s_axi_bvalid,
  input  logic                      s_axi_bready,
  input  logic [5:0]                s_axi_araddr,
  input  logic [2:0]                s_axi_arprot,
  input  logic                      s_axi_arvalid,
  output logic                      s_axi_arready,
  output logic [31:0]               s_axi_rdata,
  output logic [1:0]                s_axi_rresp,
  output logic                      s_axi_rvalid,
  input  logic                      s_axi_rready,

  input  logic [7:0]                sample_data_i,
  input  logic                      sample_valid_i,
  input  logic                      trigger_pulse_i,
  output logic                      irq_o,

  output logic                      bram_clk_o,
  output logic                      bram_rst_o,
  output logic                      bram_en_o,
  output logic [3:0]                bram_we_o,
  output logic [31:0]               bram_addr_o,
  output logic [31:0]               bram_wrdata_o,
  input  logic [31:0]               bram_rddata_i
);
  import logic_analyzer_pkg::*;

  logic [BRAM_ADDR_WIDTH-1:0] bram_word_addr;
  logic [BRAM_DATA_WIDTH-1:0] bram_write_data;
  logic                       unused_bram_read;

  assign bram_clk_o    = s_axi_aclk;
  assign bram_rst_o    = !s_axi_aresetn;
  assign bram_wrdata_o = bram_write_data;

  // Port A is write-only for this IP. The read data pin remains present so
  // Vivado can group all signals into a standard BRAM master interface.
  assign unused_bram_read = ^bram_rddata_i;

  circular_trace_buffer_axi #(
    .AXI_ADDR_WIDTH (6),
    .AXI_DATA_WIDTH (32)
  ) u_axi (
    .s_axi_aclk,
    .s_axi_aresetn,
    .s_axi_awaddr,
    .s_axi_awprot,
    .s_axi_awvalid,
    .s_axi_awready,
    .s_axi_wdata,
    .s_axi_wstrb,
    .s_axi_wvalid,
    .s_axi_wready,
    .s_axi_bresp,
    .s_axi_bvalid,
    .s_axi_bready,
    .s_axi_araddr,
    .s_axi_arprot,
    .s_axi_arvalid,
    .s_axi_arready,
    .s_axi_rdata,
    .s_axi_rresp,
    .s_axi_rvalid,
    .s_axi_rready,
    .sample_data_i,
    .sample_valid_i,
    .trigger_pulse_i,
    .irq_o,
    .bram_en_o,
    .bram_we_o,
    .bram_addr_o  (bram_word_addr),
    .bram_wdata_o (bram_write_data)
  );

  capture_bram_addr_adapter u_addr_adapter (
    .word_addr_i (bram_word_addr),
    .byte_addr_o (bram_addr_o)
  );

endmodule
