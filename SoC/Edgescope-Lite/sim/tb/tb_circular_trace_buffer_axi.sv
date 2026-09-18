`timescale 1ns/1ps

module tb_circular_trace_buffer_axi;
  import logic_analyzer_pkg::*;

  localparam time CLK_PERIOD = 10ns;
  localparam int unsigned AXI_ADDR_WIDTH = 6;
  localparam int unsigned AXI_DATA_WIDTH = 32;

  logic                      s_axi_aclk;
  logic                      s_axi_aresetn;
  logic [AXI_ADDR_WIDTH-1:0] s_axi_awaddr;
  logic [2:0]                s_axi_awprot;
  logic                      s_axi_awvalid;
  logic                      s_axi_awready;
  logic [AXI_DATA_WIDTH-1:0] s_axi_wdata;
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
  logic [AXI_DATA_WIDTH-1:0] s_axi_rdata;
  logic [1:0]                s_axi_rresp;
  logic                      s_axi_rvalid;
  logic                      s_axi_rready;

  logic [PROBE_WIDTH-1:0]     sample_data_i;
  logic                       sample_valid_i;
  logic                       trigger_pulse_i;
  logic                       irq_o;
  logic                       bram_en_o;
  logic [3:0]                 bram_we_o;
  logic [BRAM_ADDR_WIDTH-1:0] bram_addr_o;
  logic [BRAM_DATA_WIDTH-1:0] bram_wdata_o;

  int unsigned bram_write_count;

  circular_trace_buffer_axi dut (
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
    .bram_addr_o,
    .bram_wdata_o
  );

  initial s_axi_aclk = 1'b0;
  always #(CLK_PERIOD/2) s_axi_aclk = ~s_axi_aclk;

  always @(posedge s_axi_aclk) begin
    if (bram_en_o) begin
      if (bram_we_o !== 4'b1111)
        $fatal(1, "BRAM write enable mismatch");
      if (bram_addr_o !== bram_write_count[BRAM_ADDR_WIDTH-1:0])
        $fatal(1, "BRAM write %0d used address %0d",
               bram_write_count, bram_addr_o);
      if (bram_wdata_o[31:8] != 0 ||
          bram_wdata_o[7:0] != sample_data_i)
        $fatal(1, "BRAM write data packing mismatch");

      bram_write_count <= bram_write_count + 1;
    end
  end

  task automatic send_aw(input logic [AXI_ADDR_WIDTH-1:0] addr);
    begin
      @(negedge s_axi_aclk);
      s_axi_awaddr  = addr;
      s_axi_awvalid = 1'b1;

      do @(posedge s_axi_aclk); while (!s_axi_awready);

      @(negedge s_axi_aclk);
      s_axi_awvalid = 1'b0;
    end
  endtask

  task automatic send_w(
    input logic [AXI_DATA_WIDTH-1:0] data,
    input logic [3:0]                strb
  );
    begin
      @(negedge s_axi_aclk);
      s_axi_wdata  = data;
      s_axi_wstrb  = strb;
      s_axi_wvalid = 1'b1;

      do @(posedge s_axi_aclk); while (!s_axi_wready);

      @(negedge s_axi_aclk);
      s_axi_wvalid = 1'b0;
    end
  endtask

  // order=0: AW/W together, order=1: AW first, order=2: W first.
  task automatic axi_write(
    input logic [AXI_ADDR_WIDTH-1:0] addr,
    input logic [AXI_DATA_WIDTH-1:0] data,
    input logic [3:0]                strb,
    input int unsigned               order
  );
    begin
      case (order)
        0: fork
          send_aw(addr);
          send_w(data, strb);
        join

        1: begin
          send_aw(addr);
          repeat (2) @(posedge s_axi_aclk);
          send_w(data, strb);
        end

        2: begin
          send_w(data, strb);
          repeat (2) @(posedge s_axi_aclk);
          send_aw(addr);
        end

        default: $fatal(1, "Unsupported AXI write order");
      endcase

      while (!s_axi_bvalid)
        @(posedge s_axi_aclk);

      if (s_axi_bresp !== 2'b00)
        $fatal(1, "AXI write returned BRESP=%b", s_axi_bresp);

      @(posedge s_axi_aclk);
      #1;
    end
  endtask

  task automatic axi_read(
    input  logic [AXI_ADDR_WIDTH-1:0] addr,
    output logic [AXI_DATA_WIDTH-1:0] data
  );
    begin
      @(negedge s_axi_aclk);
      s_axi_araddr  = addr;
      s_axi_arvalid = 1'b1;

      do @(posedge s_axi_aclk); while (!s_axi_arready);
      #1;

      if (!s_axi_rvalid)
        $fatal(1, "AXI read did not assert RVALID");
      if (s_axi_rresp !== 2'b00)
        $fatal(1, "AXI read returned RRESP=%b", s_axi_rresp);

      data = s_axi_rdata;

      @(negedge s_axi_aclk);
      s_axi_arvalid = 1'b0;
      s_axi_rready  = 1'b1;
      @(posedge s_axi_aclk);
      #1;
      @(negedge s_axi_aclk);
      s_axi_rready = 1'b0;
    end
  endtask

  task automatic test_partial_channel_reset;
    begin
      // An address accepted without its W channel must be discarded by reset.
      send_aw(TRACE_REG_CONTROL);
      @(negedge s_axi_aclk);
      s_axi_aresetn = 1'b0;
      @(posedge s_axi_aclk);
      #1;
      if (s_axi_bvalid)
        $fatal(1, "Partial AW transaction survived reset");
      @(negedge s_axi_aclk);
      s_axi_aresetn = 1'b1;

      // The same rule applies to an independently accepted W channel.
      send_w(32'h0000_0001, 4'b0001);
      @(negedge s_axi_aclk);
      s_axi_aresetn = 1'b0;
      @(posedge s_axi_aclk);
      #1;
      if (s_axi_bvalid)
        $fatal(1, "Partial W transaction survived reset");
      @(negedge s_axi_aclk);
      s_axi_aresetn = 1'b1;
    end
  endtask

  task automatic test_write_response_backpressure;
    logic [1:0] held_bresp;
    begin
      s_axi_bready = 1'b0;

      fork
        send_aw(6'h18);
        send_w(32'hA5A5_5A5A, 4'b1111);
      join

      while (!s_axi_bvalid)
        @(posedge s_axi_aclk);
      #1;
      held_bresp = s_axi_bresp;

      repeat (3) begin
        @(posedge s_axi_aclk);
        #1;
        if (!s_axi_bvalid || s_axi_bresp !== held_bresp)
          $fatal(1, "BVALID/BRESP changed while BREADY=0");
        if (s_axi_awready || s_axi_wready)
          $fatal(1, "New write accepted while response was stalled");
      end

      @(negedge s_axi_aclk);
      s_axi_bready = 1'b1;
      @(posedge s_axi_aclk);
      #1;
      if (s_axi_bvalid)
        $fatal(1, "BVALID did not clear after BREADY handshake");
    end
  endtask

  task automatic test_read_response_backpressure;
    logic [AXI_DATA_WIDTH-1:0] held_rdata;
    logic [1:0]                held_rresp;
    begin
      s_axi_rready = 1'b0;

      @(negedge s_axi_aclk);
      s_axi_araddr  = TRACE_REG_CAPTURE_INFO;
      s_axi_arvalid = 1'b1;

      do @(posedge s_axi_aclk); while (!s_axi_arready);
      #1;
      if (!s_axi_rvalid)
        $fatal(1, "RVALID missing after AR handshake");

      held_rdata = s_axi_rdata;
      held_rresp = s_axi_rresp;

      @(negedge s_axi_aclk);
      s_axi_arvalid = 1'b0;
      // Change ARADDR to prove the registered response remains stable.
      s_axi_araddr = TRACE_REG_STATUS;

      repeat (3) begin
        @(posedge s_axi_aclk);
        #1;
        if (!s_axi_rvalid || s_axi_rdata !== held_rdata ||
            s_axi_rresp !== held_rresp)
          $fatal(1, "RVALID/RDATA/RRESP changed while RREADY=0");
        if (s_axi_arready)
          $fatal(1, "New read accepted while response was stalled");
      end

      if (held_rdata != 32'h0200_0400)
        $fatal(1, "Stalled CAPTURE_INFO response was incorrect");

      @(negedge s_axi_aclk);
      s_axi_rready = 1'b1;
      @(posedge s_axi_aclk);
      #1;
      if (s_axi_rvalid)
        $fatal(1, "RVALID did not clear after RREADY handshake");
      @(negedge s_axi_aclk);
      s_axi_rready = 1'b0;
    end
  endtask

  task automatic drive_sample(
    input logic [PROBE_WIDTH-1:0] data,
    input logic                   trigger
  );
    begin
      @(negedge s_axi_aclk);
      sample_data_i   = data;
      sample_valid_i  = 1'b1;
      trigger_pulse_i = trigger;

      @(posedge s_axi_aclk);
      #1;

      @(negedge s_axi_aclk);
      sample_valid_i  = 1'b0;
      trigger_pulse_i = 1'b0;
    end
  endtask

  initial begin
    logic [31:0] read_data;
    int unsigned sample_number;

    s_axi_aresetn   = 1'b0;
    s_axi_awaddr    = '0;
    s_axi_awprot    = '0;
    s_axi_awvalid   = 1'b0;
    s_axi_wdata     = '0;
    s_axi_wstrb     = '0;
    s_axi_wvalid    = 1'b0;
    s_axi_bready    = 1'b1;
    s_axi_araddr    = '0;
    s_axi_arprot    = '0;
    s_axi_arvalid   = 1'b0;
    s_axi_rready    = 1'b0;
    sample_data_i   = '0;
    sample_valid_i  = 1'b0;
    trigger_pulse_i = 1'b0;
    bram_write_count = 0;

    if ($test$plusargs("VCD")) begin
      $dumpfile("tb_circular_trace_buffer_axi.vcd");
      $dumpvars(0, tb_circular_trace_buffer_axi);
    end

    repeat (4) @(posedge s_axi_aclk);
    @(negedge s_axi_aclk);
    s_axi_aresetn = 1'b1;

    test_partial_channel_reset();
    test_write_response_backpressure();
    test_read_response_backpressure();

    axi_read(TRACE_REG_CONTROL, read_data);
    if (read_data != 0)
      $fatal(1, "W1P CONTROL read was nonzero");

    axi_read(TRACE_REG_STATUS, read_data);
    if (read_data != 0)
      $fatal(1, "Reset STATUS was nonzero");

    axi_read(TRACE_REG_CAPTURE_INFO, read_data);
    if (read_data != 32'h0200_0400)
      $fatal(1, "CAPTURE_INFO=%08h, expected=02000400", read_data);

    axi_read(6'h18, read_data);
    if (read_data != 0)
      $fatal(1, "Reserved register did not read as zero");

    // A zero byte strobe must suppress the ARM W1P command.
    axi_write(TRACE_REG_CONTROL, 32'h0000_0001, 4'b0000, 0);
    axi_read(TRACE_REG_STATUS, read_data);
    if (read_data != 0)
      $fatal(1, "WSTRB=0 unexpectedly armed the core");

    // AW arrives before W.
    axi_write(TRACE_REG_CONTROL, 32'h0000_0001, 4'b0001, 1);
    axi_read(TRACE_REG_STATUS, read_data);
    if (read_data != 32'h0000_0001)
      $fatal(1, "ARM status=%08h, expected busy=1", read_data);

    // W arrives before AW. Abort must return the core to IDLE.
    axi_write(TRACE_REG_CONTROL, 32'h0000_0004, 4'b0001, 2);
    axi_read(TRACE_REG_STATUS, read_data);
    if (read_data != 0)
      $fatal(1, "ABORT did not clear STATUS");

    bram_write_count = 0;
    axi_write(TRACE_REG_CONTROL, 32'h0000_0001, 4'b0001, 0);

    sample_number = 0;
    for (int unsigned i = 0; i < PRE_TRIGGER_SAMPLES; i++) begin
      drive_sample(sample_number[PROBE_WIDTH-1:0], 1'b0);
      sample_number++;
    end

    axi_read(TRACE_REG_STATUS, read_data);
    if (read_data != 32'h0000_0003)
      $fatal(1, "ARMED STATUS=%08h, expected=00000003", read_data);

    drive_sample(sample_number[PROBE_WIDTH-1:0], 1'b1);
    sample_number++;

    axi_read(TRACE_REG_STATUS, read_data);
    if (read_data != 32'h0000_0007)
      $fatal(1, "POST STATUS=%08h, expected=00000007", read_data);

    for (int unsigned i = 1; i < POST_TRIGGER_SAMPLES; i++) begin
      drive_sample(sample_number[PROBE_WIDTH-1:0], 1'b0);
      sample_number++;
    end

    if (!irq_o)
      $fatal(1, "IRQ did not assert at capture completion");

    axi_read(TRACE_REG_STATUS, read_data);
    if (read_data != 32'h0000_000E)
      $fatal(1, "DONE STATUS=%08h, expected=0000000E", read_data);

    axi_read(TRACE_REG_START_ADDR, read_data);
    if (read_data != 0)
      $fatal(1, "START_ADDR=%0d, expected=0", read_data);

    axi_read(TRACE_REG_TRIGGER_ADDR, read_data);
    if (read_data != 512)
      $fatal(1, "TRIGGER_ADDR=%0d, expected=512", read_data);

    axi_read(TRACE_REG_WRITE_ADDR, read_data);
    if (read_data != 1023)
      $fatal(1, "WRITE_ADDR=%0d, expected=1023", read_data);

    // Writes to RO registers receive OKAY but have no effect.
    axi_write(TRACE_REG_STATUS, 32'hFFFF_FFFF, 4'b1111, 0);
    axi_read(TRACE_REG_STATUS, read_data);
    if (read_data != 32'h0000_000E)
      $fatal(1, "Write to RO STATUS changed its value");

    axi_write(TRACE_REG_CONTROL, 32'h0000_0002, 4'b0001, 0);
    axi_read(TRACE_REG_STATUS, read_data);
    if (read_data != 0 || irq_o)
      $fatal(1, "CLEAR_DONE did not clear STATUS/IRQ");

    $display("PASS: AXI read mux and CAPTURE_INFO");
    $display("PASS: W1P CONTROL and WSTRB behavior");
    $display("PASS: independent AW-first and W-first transactions");
    $display("PASS: AXI B/R response backpressure stability");
    $display("PASS: reset discarded partial AW/W transactions");
    $display("PASS: ARM, ABORT and CLEAR_DONE through AXI");
    $display("PASS: STATUS transitions 0x1 -> 0x3 -> 0x7 -> 0xE");
    $display("PASS: START/TRIGGER/WRITE address registers");
    $display("PASS: writes to RO registers had no effect");
    $display("tb_circular_trace_buffer_axi: PASS");
    $finish;
  end

  // Prevent a protocol regression from turning into an unbounded simulation.
  initial begin
    #1ms;
    $fatal(1, "AXI testbench watchdog expired");
  end

endmodule
