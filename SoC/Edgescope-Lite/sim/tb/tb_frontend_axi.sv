`timescale 1ns/1ps

module tb_frontend_axi;
  import logic_analyzer_pkg::*;

  logic clk = 1'b0;
  logic resetn = 1'b0;
  logic [7:0] probe = 8'h00;
  logic [7:0] sample_data;
  logic sample_valid;
  logic trigger_pulse;

  logic [5:0] sawaddr;
  logic [2:0] sawprot = '0;
  logic sawvalid;
  logic sawready;
  logic [31:0] swdata;
  logic [3:0] swstrb;
  logic swvalid;
  logic swready;
  logic [1:0] sbresp;
  logic sbvalid;
  logic sbready;
  logic [5:0] saraddr;
  logic [2:0] sarprot = '0;
  logic sarvalid;
  logic sarready;
  logic [31:0] srdata;
  logic [1:0] srresp;
  logic srvalid;
  logic srready;

  logic [5:0] tawaddr;
  logic [2:0] tawprot = '0;
  logic tawvalid;
  logic tawready;
  logic [31:0] twdata;
  logic [3:0] twstrb;
  logic twvalid;
  logic twready;
  logic [1:0] tbresp;
  logic tbvalid;
  logic tbready;
  logic [5:0] taraddr;
  logic [2:0] tarprot = '0;
  logic tarvalid;
  logic tarready;
  logic [31:0] trdata;
  logic [1:0] trresp;
  logic trvalid;
  logic trready;

  int pulse_count = 0;

  always #5 clk = ~clk;
  always @(posedge clk)
    if (trigger_pulse)
      pulse_count <= pulse_count + 1;

  probe_sampler_axi sampler (
    .s_axi_aclk(clk), .s_axi_aresetn(resetn),
    .s_axi_awaddr(sawaddr), .s_axi_awprot(sawprot),
    .s_axi_awvalid(sawvalid), .s_axi_awready(sawready),
    .s_axi_wdata(swdata), .s_axi_wstrb(swstrb),
    .s_axi_wvalid(swvalid), .s_axi_wready(swready),
    .s_axi_bresp(sbresp), .s_axi_bvalid(sbvalid), .s_axi_bready(sbready),
    .s_axi_araddr(saraddr), .s_axi_arprot(sarprot),
    .s_axi_arvalid(sarvalid), .s_axi_arready(sarready),
    .s_axi_rdata(srdata), .s_axi_rresp(srresp),
    .s_axi_rvalid(srvalid), .s_axi_rready(srready),
    .probe_i(probe), .sample_data_o(sample_data),
    .sample_valid_o(sample_valid)
  );

  basic_trigger_engine_axi trigger (
    .s_axi_aclk(clk), .s_axi_aresetn(resetn),
    .s_axi_awaddr(tawaddr), .s_axi_awprot(tawprot),
    .s_axi_awvalid(tawvalid), .s_axi_awready(tawready),
    .s_axi_wdata(twdata), .s_axi_wstrb(twstrb),
    .s_axi_wvalid(twvalid), .s_axi_wready(twready),
    .s_axi_bresp(tbresp), .s_axi_bvalid(tbvalid), .s_axi_bready(tbready),
    .s_axi_araddr(taraddr), .s_axi_arprot(tarprot),
    .s_axi_arvalid(tarvalid), .s_axi_arready(tarready),
    .s_axi_rdata(trdata), .s_axi_rresp(trresp),
    .s_axi_rvalid(trvalid), .s_axi_rready(trready),
    .sample_data_i(sample_data), .sample_valid_i(sample_valid),
    .trigger_pulse_o(trigger_pulse)
  );

  task automatic sampler_write(input logic [5:0] address,
                               input logic [31:0] data);
    begin
      @(posedge clk);
      sawaddr <= address;
      swdata <= data;
      swstrb <= 4'hf;
      sawvalid <= 1'b1;
      swvalid <= 1'b1;
      do @(posedge clk); while (!(sawready && swready));
      sawvalid <= 1'b0;
      swvalid <= 1'b0;
      do @(posedge clk); while (!sbvalid);
    end
  endtask

  task automatic sampler_read(input logic [5:0] address,
                              output logic [31:0] data);
    begin
      @(posedge clk);
      saraddr <= address;
      sarvalid <= 1'b1;
      do @(posedge clk); while (!sarready);
      sarvalid <= 1'b0;
      do @(posedge clk); while (!srvalid);
      data = srdata;
    end
  endtask

  task automatic trigger_write(input logic [5:0] address,
                               input logic [31:0] data);
    begin
      @(posedge clk);
      tawaddr <= address;
      twdata <= data;
      twstrb <= 4'hf;
      tawvalid <= 1'b1;
      twvalid <= 1'b1;
      do @(posedge clk); while (!(tawready && twready));
      tawvalid <= 1'b0;
      twvalid <= 1'b0;
      do @(posedge clk); while (!tbvalid);
    end
  endtask

  task automatic trigger_read(input logic [5:0] address,
                              output logic [31:0] data);
    begin
      @(posedge clk);
      taraddr <= address;
      tarvalid <= 1'b1;
      do @(posedge clk); while (!tarready);
      tarvalid <= 1'b0;
      do @(posedge clk); while (!trvalid);
      data = trdata;
    end
  endtask

  initial begin
    logic [31:0] value;

    sawaddr = '0; sawvalid = 0; swdata = '0; swstrb = '0;
    swvalid = 0; sbready = 1; saraddr = '0; sarvalid = 0; srready = 1;
    tawaddr = '0; tawvalid = 0; twdata = '0; twstrb = '0;
    twvalid = 0; tbready = 1; taraddr = '0; tarvalid = 0; trready = 1;

    repeat (5) @(posedge clk);
    resetn <= 1'b1;
    repeat (3) @(posedge clk);

    // Rising edge through the complete Sampler -> Trigger AXI data path.
    sampler_write(SAMPLER_REG_CONFIG, 32'h0000_ff00);
    sampler_write(SAMPLER_REG_CONTROL, 32'h0000_0002);
    trigger_write(TRIGGER_REG_CONFIG, TRIGGER_RISING);
    trigger_write(TRIGGER_REG_CONTROL, 32'h0000_0002);
    trigger_write(TRIGGER_REG_CONTROL, 32'h0000_0001);
    sampler_write(SAMPLER_REG_CONTROL, 32'h0000_0001);
    repeat (5) @(posedge clk);
    probe <= 8'h01;
    repeat (6) @(posedge clk);

    trigger_read(TRIGGER_REG_STATUS, value);
    if ((value & 32'h3) != 32'h3)
      $fatal(1, "Rising trigger status mismatch: %08x", value);
    trigger_read(TRIGGER_REG_TRIGGER_COUNT, value);
    if (value != 1 || pulse_count != 1)
      $fatal(1, "Rising trigger count mismatch: reg=%0d pulse=%0d",
             value, pulse_count);

    sampler_read(SAMPLER_REG_LAST_SAMPLE, value);
    if ((value & 8'hff) != 8'h01)
      $fatal(1, "Sampler last sample mismatch: %08x", value);
    sampler_read(SAMPLER_REG_SAMPLE_COUNT, value);
    if (value == 0)
      $fatal(1, "Sampler count did not advance");

    // Pattern entry must produce exactly one additional pulse.
    sampler_write(SAMPLER_REG_CONTROL, 32'h0000_0002);
    probe <= 8'h95;
    trigger_write(TRIGGER_REG_CONTROL, 32'h0000_0002);
    trigger_write(TRIGGER_REG_CONFIG, TRIGGER_PATTERN);
    trigger_write(TRIGGER_REG_PATTERN, 32'h0000_f0a0);
    trigger_write(TRIGGER_REG_CONTROL, 32'h0000_0001);
    sampler_write(SAMPLER_REG_CONTROL, 32'h0000_0001);
    repeat (5) @(posedge clk);
    probe <= 8'ha5;
    repeat (6) @(posedge clk);
    repeat (5) @(posedge clk); // Holding the pattern must not retrigger.

    trigger_read(TRIGGER_REG_TRIGGER_COUNT, value);
    if (value != 2 || pulse_count != 2)
      $fatal(1, "Pattern one-shot mismatch: reg=%0d pulse=%0d",
             value, pulse_count);

    $display("tb_frontend_axi: PASS");
    $finish;
  end
endmodule
