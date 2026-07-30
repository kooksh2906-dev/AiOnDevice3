`timescale 1ns/1ps

module tb_circular_trace_buffer_bram;
  import logic_analyzer_pkg::*;

  localparam time CLK_PERIOD = 10ns;
  localparam int unsigned AXI_ADDR_WIDTH = 6;
  localparam int unsigned ARMED_WAIT_SAMPLES = 7;

  logic                      clk;
  logic                      rst_n;
  logic [AXI_ADDR_WIDTH-1:0] s_axi_awaddr;
  logic [2:0]                s_axi_awprot;
  logic                      s_axi_awvalid;
  logic                      s_axi_awready;
  logic [31:0]               s_axi_wdata;
  logic [3:0]                s_axi_wstrb;
  logic                      s_axi_wvalid;
  logic                      s_axi_wready;
  logic [1:0]                s_axi_bresp;
  logic                      s_axi_bvalid;
  logic                      s_axi_bready;
  logic [AXI_ADDR_WIDTH-1:0] s_axi_araddr;
  logic [2:0]                s_axi_arprot;
  logic                      s_axi_arvalid;
  logic                      s_axi_arready;
  logic [31:0]               s_axi_rdata;
  logic [1:0]                s_axi_rresp;
  logic                      s_axi_rvalid;
  logic                      s_axi_rready;

  logic [PROBE_WIDTH-1:0]     sample_data_i;
  logic                       sample_valid_i;
  logic                       trigger_pulse_i;
  logic                       irq_o;
  logic                       bram_clk;
  logic                       bram_rst;
  logic                       bram_en;
  logic [3:0]                 bram_we;
  logic [31:0]                bram_wdata;
  logic [31:0]                bram_byte_addr_a;
  logic [31:0]                bram_douta;

  logic                       cpu_bram_en;
  logic [3:0]                 cpu_bram_we;
  logic [31:0]                cpu_bram_addr;
  logic [31:0]                cpu_bram_wdata;
  logic [31:0]                cpu_bram_rdata;

  int unsigned port_a_write_count;

  // Instantiate the actual IP Packager top so clock/reset, AXI, BRAM port
  // naming and the word-to-byte address adapter are verified together.
  circular_trace_buffer_ip u_trace (
    .s_axi_aclk         (clk),
    .s_axi_aresetn      (rst_n),
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
    .bram_clk_o         (bram_clk),
    .bram_rst_o         (bram_rst),
    .bram_en_o          (bram_en),
    .bram_we_o          (bram_we),
    .bram_addr_o        (bram_byte_addr_a),
    .bram_wrdata_o      (bram_wdata),
    .bram_rddata_i      (bram_douta)
  );

  capture_bram_tdp_model u_capture_bram (
    .clka  (bram_clk),
    .ena   (bram_en),
    .wea   (bram_we),
    .addra (bram_byte_addr_a),
    .dina  (bram_wdata),
    .douta (bram_douta),
    .clkb  (clk),
    .enb   (cpu_bram_en),
    .web   (cpu_bram_we),
    .addrb (cpu_bram_addr),
    .dinb  (cpu_bram_wdata),
    .doutb (cpu_bram_rdata)
  );

  initial clk = 1'b0;
  always #(CLK_PERIOD/2) clk = ~clk;

  always @(posedge clk) begin
    if (bram_en) begin
      if (bram_byte_addr_a[1:0] != 2'b00)
        $fatal(1, "Port A byte address is not word aligned");
      if (bram_byte_addr_a !==
          {20'b0, port_a_write_count[BRAM_ADDR_WIDTH-1:0], 2'b00})
        $fatal(1, "Port A write %0d used byte address %08h",
               port_a_write_count, bram_byte_addr_a);

      port_a_write_count <= port_a_write_count + 1;
    end
  end

  task automatic axi_write_control(input logic [2:0] command);
    begin
      @(negedge clk);
      s_axi_awaddr  = TRACE_REG_CONTROL;
      s_axi_awvalid = 1'b1;
      s_axi_wdata   = {29'b0, command};
      s_axi_wstrb   = 4'b0001;
      s_axi_wvalid  = 1'b1;

      do @(posedge clk); while (!(s_axi_awready && s_axi_wready));

      @(negedge clk);
      s_axi_awvalid = 1'b0;
      s_axi_wvalid  = 1'b0;

      while (!s_axi_bvalid)
        @(posedge clk);

      if (s_axi_bresp != 2'b00)
        $fatal(1, "AXI control write failed");

      @(posedge clk);
      #1;
    end
  endtask

  task automatic axi_read(
    input  logic [AXI_ADDR_WIDTH-1:0] addr,
    output logic [31:0]               data
  );
    begin
      @(negedge clk);
      s_axi_araddr  = addr;
      s_axi_arvalid = 1'b1;

      do @(posedge clk); while (!s_axi_arready);
      #1;

      if (!s_axi_rvalid || s_axi_rresp != 2'b00)
        $fatal(1, "AXI register read failed");
      data = s_axi_rdata;

      @(negedge clk);
      s_axi_arvalid = 1'b0;
      s_axi_rready  = 1'b1;
      @(posedge clk);
      #1;
      @(negedge clk);
      s_axi_rready = 1'b0;
    end
  endtask

  task automatic drive_sample(
    input logic [PROBE_WIDTH-1:0] data,
    input logic                   trigger
  );
    begin
      @(negedge clk);
      sample_data_i   = data;
      sample_valid_i  = 1'b1;
      trigger_pulse_i = trigger;

      @(posedge clk);
      #1;

      @(negedge clk);
      sample_valid_i  = 1'b0;
      trigger_pulse_i = 1'b0;
    end
  endtask

  task automatic cpu_bram_read(
    input  logic [31:0] byte_addr,
    output logic [31:0] data
  );
    begin
      if (byte_addr[1:0] != 2'b00)
        $fatal(1, "CPU BRAM address %08h is not word aligned", byte_addr);

      @(negedge clk);
      cpu_bram_addr = byte_addr;
      cpu_bram_en   = 1'b1;
      cpu_bram_we   = 4'b0000;

      @(posedge clk);
      #1;
      data = cpu_bram_rdata;

      @(negedge clk);
      cpu_bram_en = 1'b0;
    end
  endtask

  initial begin
    logic [31:0] register_data;
    logic [31:0] memory_data;
    int unsigned sample_number;
    int unsigned start_word;
    int unsigned trigger_word;
    int unsigned physical_word;
    int unsigned expected_sample;
    int unsigned byte_address;

    rst_n              = 1'b0;
    s_axi_awaddr       = '0;
    s_axi_awprot       = '0;
    s_axi_awvalid      = 1'b0;
    s_axi_wdata        = '0;
    s_axi_wstrb        = '0;
    s_axi_wvalid       = 1'b0;
    s_axi_bready       = 1'b1;
    s_axi_araddr       = '0;
    s_axi_arprot       = '0;
    s_axi_arvalid      = 1'b0;
    s_axi_rready       = 1'b0;
    sample_data_i      = '0;
    sample_valid_i     = 1'b0;
    trigger_pulse_i    = 1'b0;
    cpu_bram_en        = 1'b0;
    cpu_bram_we        = 4'b0000;
    cpu_bram_addr      = '0;
    cpu_bram_wdata     = '0;
    port_a_write_count = 0;

    if ($test$plusargs("VCD")) begin
      $dumpfile("tb_circular_trace_buffer_bram.vcd");
      $dumpvars(0, tb_circular_trace_buffer_bram);
    end

    repeat (4) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
    #1ps; // Allow continuous BRAM clock/reset assignments to settle in XSim.

    if (bram_clk !== clk || bram_rst !== !rst_n)
      $fatal(1, "Packaged BRAM clock/reset wiring mismatch");

    axi_write_control(3'b001);

    sample_number = 0;
    for (int unsigned i = 0; i < PRE_TRIGGER_SAMPLES; i++) begin
      drive_sample(sample_number[PROBE_WIDTH-1:0], 1'b0);
      sample_number++;
    end

    for (int unsigned i = 0; i < ARMED_WAIT_SAMPLES; i++) begin
      drive_sample(sample_number[PROBE_WIDTH-1:0], 1'b0);
      sample_number++;
    end

    drive_sample(sample_number[PROBE_WIDTH-1:0], 1'b1);
    sample_number++;

    for (int unsigned i = 1; i < POST_TRIGGER_SAMPLES; i++) begin
      drive_sample(sample_number[PROBE_WIDTH-1:0], 1'b0);
      sample_number++;
    end

    if (!irq_o)
      $fatal(1, "Capture did not complete");

    axi_read(TRACE_REG_STATUS, register_data);
    if (register_data != 32'h0000_000E)
      $fatal(1, "DONE status mismatch: %08h", register_data);

    axi_read(TRACE_REG_START_ADDR, register_data);
    start_word = register_data & (CAPTURE_DEPTH-1);

    axi_read(TRACE_REG_TRIGGER_ADDR, register_data);
    trigger_word = register_data & (CAPTURE_DEPTH-1);

    if (start_word != ARMED_WAIT_SAMPLES)
      $fatal(1, "START_ADDR=%0d, expected=%0d",
             start_word, ARMED_WAIT_SAMPLES);
    if (trigger_word != PRE_TRIGGER_SAMPLES+ARMED_WAIT_SAMPLES)
      $fatal(1, "TRIGGER_ADDR=%0d, expected=%0d",
             trigger_word, PRE_TRIGGER_SAMPLES+ARMED_WAIT_SAMPLES);

    // Model the AXI BRAM Controller's CPU byte addressing and read all final
    // samples from BMG Port B in logical time order.
    for (int unsigned logical_index = 0;
         logical_index < CAPTURE_DEPTH;
         logical_index++) begin
      physical_word = (start_word + logical_index) &
                      (CAPTURE_DEPTH-1);
      byte_address = physical_word << 2;

      cpu_bram_read(byte_address, memory_data);

      expected_sample = ARMED_WAIT_SAMPLES + logical_index;
      if (memory_data[31:8] != 0 ||
          memory_data[7:0] !=
            expected_sample[PROBE_WIDTH-1:0])
        $fatal(1,
          "Logical %0d, physical %0d, byte %0d: got=%08h expected=%02h",
          logical_index, physical_word, byte_address,
          memory_data, expected_sample[PROBE_WIDTH-1:0]);
    end

    physical_word = (start_word + TRIGGER_LOGICAL_INDEX) &
                    (CAPTURE_DEPTH-1);
    if (physical_word != trigger_word)
      $fatal(1, "Logical trigger index did not map to TRIGGER_ADDR");

    $display("PASS: packaged top clock/reset and BRAM interface wiring");
    $display("PASS: Port A word-to-byte address conversion");
    $display("PASS: 1,024 x 32-bit true dual-port BRAM behavior");
    $display("PASS: synchronous Port B reads");
    $display("PASS: CPU byte address = physical word index * 4");
    $display("PASS: 1,024 samples read in logical time order");
    $display("PASS: logical trigger index 512 mapped to physical %0d",
             trigger_word);
    $display("tb_circular_trace_buffer_bram: PASS");
    $finish;
  end

endmodule
