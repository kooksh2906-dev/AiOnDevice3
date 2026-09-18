`timescale 1ns/1ps

module circular_trace_buffer_axi #(
  parameter int unsigned AXI_ADDR_WIDTH = 6,
  parameter int unsigned AXI_DATA_WIDTH = 32
) (
  input  logic                                           s_axi_aclk,
  input  logic                                           s_axi_aresetn,

  input  logic [AXI_ADDR_WIDTH-1:0]                      s_axi_awaddr,
  input  logic [2:0]                                     s_axi_awprot,
  input  logic                                           s_axi_awvalid,
  output logic                                           s_axi_awready,

  input  logic [AXI_DATA_WIDTH-1:0]                      s_axi_wdata,
  input  logic [(AXI_DATA_WIDTH/8)-1:0]                  s_axi_wstrb,
  input  logic                                           s_axi_wvalid,
  output logic                                           s_axi_wready,

  output logic [1:0]                                     s_axi_bresp,
  output logic                                           s_axi_bvalid,
  input  logic                                           s_axi_bready,

  input  logic [AXI_ADDR_WIDTH-1:0]                      s_axi_araddr,
  input  logic [2:0]                                     s_axi_arprot,
  input  logic                                           s_axi_arvalid,
  output logic                                           s_axi_arready,

  output logic [AXI_DATA_WIDTH-1:0]                      s_axi_rdata,
  output logic [1:0]                                     s_axi_rresp,
  output logic                                           s_axi_rvalid,
  input  logic                                           s_axi_rready,

  input  logic [logic_analyzer_pkg::PROBE_WIDTH-1:0]     sample_data_i,
  input  logic                                           sample_valid_i,
  input  logic                                           trigger_pulse_i,

  output logic                                           irq_o,
  output logic                                           bram_en_o,
  output logic [3:0]                                     bram_we_o,
  output logic [logic_analyzer_pkg::BRAM_ADDR_WIDTH-1:0] bram_addr_o,
  output logic [logic_analyzer_pkg::BRAM_DATA_WIDTH-1:0] bram_wdata_o
);
  import logic_analyzer_pkg::*;

  localparam logic [1:0] AXI_RESP_OKAY = 2'b00;

  logic                      aw_hold_valid_q;
  logic [AXI_ADDR_WIDTH-1:0] awaddr_q;
  logic                      w_hold_valid_q;
  logic [AXI_DATA_WIDTH-1:0] wdata_q;
  logic [(AXI_DATA_WIDTH/8)-1:0] wstrb_q;
  logic                      bvalid_q;

  logic [AXI_DATA_WIDTH-1:0] rdata_q;
  logic                      rvalid_q;
  logic [AXI_DATA_WIDTH-1:0] read_mux_data;

  logic write_commit;
  logic control_write;
  logic arm_pulse;
  logic clear_done_pulse;
  logic abort_pulse;

  logic                       core_busy;
  logic                       core_pre_ready;
  logic                       core_triggered;
  logic                       core_capture_done;
  logic [BRAM_ADDR_WIDTH-1:0] core_start_addr;
  logic [BRAM_ADDR_WIDTH-1:0] core_trigger_addr;
  logic [BRAM_ADDR_WIDTH-1:0] core_write_addr;

  // AW and W are buffered independently. This supports legal AXI4-Lite
  // transactions where address and data arrive in different cycles.
  assign s_axi_awready = !aw_hold_valid_q && !bvalid_q;
  assign s_axi_wready  = !w_hold_valid_q  && !bvalid_q;
  assign write_commit  = aw_hold_valid_q && w_hold_valid_q && !bvalid_q;

  assign control_write =
      write_commit &&
      (awaddr_q == TRACE_REG_CONTROL) &&
      wstrb_q[0];

  assign arm_pulse        = control_write && wdata_q[0];
  assign clear_done_pulse = control_write && wdata_q[1];
  assign abort_pulse      = control_write && wdata_q[2];

  assign s_axi_bresp  = AXI_RESP_OKAY;
  assign s_axi_bvalid = bvalid_q;

  always_ff @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn) begin
      aw_hold_valid_q <= 1'b0;
      awaddr_q        <= '0;
      w_hold_valid_q  <= 1'b0;
      wdata_q         <= '0;
      wstrb_q         <= '0;
      bvalid_q        <= 1'b0;
    end else begin
      if (s_axi_awready && s_axi_awvalid) begin
        aw_hold_valid_q <= 1'b1;
        awaddr_q        <= s_axi_awaddr;
      end

      if (s_axi_wready && s_axi_wvalid) begin
        w_hold_valid_q <= 1'b1;
        wdata_q        <= s_axi_wdata;
        wstrb_q        <= s_axi_wstrb;
      end

      if (write_commit) begin
        aw_hold_valid_q <= 1'b0;
        w_hold_valid_q  <= 1'b0;
        bvalid_q        <= 1'b1;
      end else if (bvalid_q && s_axi_bready) begin
        bvalid_q <= 1'b0;
      end
    end
  end

  always_comb begin
    read_mux_data = '0;

    case (s_axi_araddr)
      TRACE_REG_CONTROL: begin
        // W1P register: reads always return zero.
        read_mux_data = '0;
      end

      TRACE_REG_STATUS: begin
        read_mux_data[0] = core_busy;
        read_mux_data[1] = core_pre_ready;
        read_mux_data[2] = core_triggered;
        read_mux_data[3] = core_capture_done;
      end

      TRACE_REG_START_ADDR: begin
        read_mux_data[BRAM_ADDR_WIDTH-1:0] = core_start_addr;
      end

      TRACE_REG_TRIGGER_ADDR: begin
        read_mux_data[BRAM_ADDR_WIDTH-1:0] = core_trigger_addr;
      end

      TRACE_REG_WRITE_ADDR: begin
        read_mux_data[BRAM_ADDR_WIDTH-1:0] = core_write_addr;
      end

      TRACE_REG_CAPTURE_INFO: begin
        read_mux_data[10:0]  = CAPTURE_DEPTH;
        read_mux_data[25:16] = TRIGGER_LOGICAL_INDEX;
      end

      default: begin
        read_mux_data = '0;
      end
    endcase
  end

  assign s_axi_arready = !rvalid_q;
  assign s_axi_rdata   = rdata_q;
  assign s_axi_rresp   = AXI_RESP_OKAY;
  assign s_axi_rvalid  = rvalid_q;

  always_ff @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn) begin
      rdata_q  <= '0;
      rvalid_q <= 1'b0;
    end else begin
      if (s_axi_arready && s_axi_arvalid) begin
        rdata_q  <= read_mux_data;
        rvalid_q <= 1'b1;
      end else if (rvalid_q && s_axi_rready) begin
        rvalid_q <= 1'b0;
      end
    end
  end

  // Protection attributes are accepted but are not used by this peripheral.
  logic unused_prot;
  assign unused_prot = ^{s_axi_awprot, s_axi_arprot};

  circular_trace_buffer_core u_core (
    .clk_i            (s_axi_aclk),
    .rst_ni           (s_axi_aresetn),
    .sample_data_i    (sample_data_i),
    .sample_valid_i   (sample_valid_i),
    .trigger_pulse_i  (trigger_pulse_i),
    .arm_i            (arm_pulse),
    .clear_done_i     (clear_done_pulse),
    .abort_i          (abort_pulse),
    .busy_o           (core_busy),
    .pre_ready_o      (core_pre_ready),
    .triggered_o      (core_triggered),
    .capture_done_o   (core_capture_done),
    .irq_o            (irq_o),
    .start_addr_o     (core_start_addr),
    .trigger_addr_o   (core_trigger_addr),
    .write_addr_o     (core_write_addr),
    .bram_en_o        (bram_en_o),
    .bram_we_o        (bram_we_o),
    .bram_addr_o      (bram_addr_o),
    .bram_wdata_o     (bram_wdata_o)
  );

endmodule
