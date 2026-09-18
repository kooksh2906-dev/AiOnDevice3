`timescale 1ns/1ps

module tb_circular_trace_buffer_control;
  import logic_analyzer_pkg::*;

  localparam time CLK_PERIOD = 10ns;

  logic                       clk_i;
  logic                       rst_ni;
  logic [PROBE_WIDTH-1:0]     sample_data_i;
  logic                       sample_valid_i;
  logic                       trigger_pulse_i;
  logic                       arm_i;
  logic                       clear_done_i;
  logic                       abort_i;

  logic                       busy_o;
  logic                       pre_ready_o;
  logic                       triggered_o;
  logic                       capture_done_o;
  logic                       irq_o;
  logic [BRAM_ADDR_WIDTH-1:0] start_addr_o;
  logic [BRAM_ADDR_WIDTH-1:0] trigger_addr_o;
  logic [BRAM_ADDR_WIDTH-1:0] write_addr_o;
  logic                       bram_en_o;
  logic [3:0]                 bram_we_o;
  logic [BRAM_ADDR_WIDTH-1:0] bram_addr_o;
  logic [BRAM_DATA_WIDTH-1:0] bram_wdata_o;

  int unsigned observed_write_count;

  circular_trace_buffer_core dut (
    .clk_i,
    .rst_ni,
    .sample_data_i,
    .sample_valid_i,
    .trigger_pulse_i,
    .arm_i,
    .clear_done_i,
    .abort_i,
    .busy_o,
    .pre_ready_o,
    .triggered_o,
    .capture_done_o,
    .irq_o,
    .start_addr_o,
    .trigger_addr_o,
    .write_addr_o,
    .bram_en_o,
    .bram_we_o,
    .bram_addr_o,
    .bram_wdata_o
  );

  initial clk_i = 1'b0;
  always #(CLK_PERIOD/2) clk_i = ~clk_i;

  always @(posedge clk_i) begin
    if (bram_en_o) begin
      if (bram_we_o !== 4'b1111)
        $fatal(1, "BRAM write enable mismatch");
      observed_write_count <= observed_write_count + 1;
    end
  end

  task automatic pulse_arm;
    begin
      @(negedge clk_i);
      arm_i = 1'b1;
      @(posedge clk_i);
      #1;
      @(negedge clk_i);
      arm_i = 1'b0;
    end
  endtask

  task automatic drive_sample(
    input logic [PROBE_WIDTH-1:0] data,
    input logic                   trigger
  );
    begin
      @(negedge clk_i);
      sample_data_i   = data;
      sample_valid_i  = 1'b1;
      trigger_pulse_i = trigger;

      @(posedge clk_i);
      #1;

      @(negedge clk_i);
      sample_valid_i  = 1'b0;
      trigger_pulse_i = 1'b0;
    end
  endtask

  task automatic complete_capture;
    int unsigned sample_number;
    begin
      pulse_arm();

      if (!busy_o || pre_ready_o || capture_done_o || irq_o)
        $fatal(1, "New capture did not start cleanly");

      sample_number = 0;

      for (int unsigned i = 0; i < PRE_TRIGGER_SAMPLES; i++) begin
        drive_sample(sample_number[PROBE_WIDTH-1:0], 1'b0);
        sample_number++;
      end

      if (!pre_ready_o || triggered_o)
        $fatal(1, "PREFILL completion failure");

      drive_sample(sample_number[PROBE_WIDTH-1:0], 1'b1);
      sample_number++;

      if (!triggered_o || capture_done_o)
        $fatal(1, "Trigger did not start POST_CAPTURE");

      for (int unsigned i = 1; i < POST_TRIGGER_SAMPLES; i++) begin
        drive_sample(sample_number[PROBE_WIDTH-1:0], 1'b0);
        sample_number++;
      end

      if (busy_o || !pre_ready_o || !triggered_o ||
          !capture_done_o || !irq_o)
        $fatal(1, "Capture did not reach DONE");
      if (start_addr_o != 0 || trigger_addr_o != 512 ||
          write_addr_o != 1023)
        $fatal(1, "Unexpected address result at DONE");
    end
  endtask

  initial begin
    int unsigned writes_before_control;
    logic [BRAM_ADDR_WIDTH-1:0] held_start;
    logic [BRAM_ADDR_WIDTH-1:0] held_trigger;
    logic [BRAM_ADDR_WIDTH-1:0] held_write;

    rst_ni              = 1'b0;
    sample_data_i       = '0;
    sample_valid_i      = 1'b0;
    trigger_pulse_i     = 1'b0;
    arm_i               = 1'b0;
    clear_done_i        = 1'b0;
    abort_i             = 1'b0;
    observed_write_count = 0;

    if ($test$plusargs("VCD")) begin
      $dumpfile("tb_circular_trace_buffer_control.vcd");
      $dumpvars(0, tb_circular_trace_buffer_control);
    end

    repeat (3) @(posedge clk_i);
    @(negedge clk_i);
    rst_ni = 1'b1;

    // Abort has priority over arm, clear and a pending sample write.
    pulse_arm();
    for (int unsigned i = 0; i < 10; i++)
      drive_sample(i[PROBE_WIDTH-1:0], 1'b0);

    writes_before_control = observed_write_count;

    @(negedge clk_i);
    sample_data_i   = 8'hAA;
    sample_valid_i  = 1'b1;
    trigger_pulse_i = 1'b1;
    arm_i           = 1'b1;
    clear_done_i    = 1'b1;
    abort_i         = 1'b1;
    @(posedge clk_i);
    #1;

    if (bram_en_o || observed_write_count != writes_before_control)
      $fatal(1, "Abort allowed an additional BRAM write");
    if (busy_o || pre_ready_o || triggered_o || capture_done_o || irq_o)
      $fatal(1, "Abort did not return all status outputs to idle");
    if (start_addr_o != 0 || trigger_addr_o != 0 || write_addr_o != 0)
      $fatal(1, "Abort did not reset capture addresses");

    @(negedge clk_i);
    sample_valid_i  = 1'b0;
    trigger_pulse_i = 1'b0;
    arm_i           = 1'b0;
    clear_done_i    = 1'b0;
    abort_i         = 1'b0;

    // Re-arm after abort must restart from physical address zero.
    pulse_arm();
    for (int unsigned i = 0; i < 5; i++)
      drive_sample((8'h20+i), 1'b0);

    if (write_addr_o != 4)
      $fatal(1, "Re-arm after abort did not restart at address zero");

    // While busy, clear_done and arm are ignored. The valid sample must still
    // be written, proving that ignored controls do not stall capture.
    writes_before_control = observed_write_count;

    @(negedge clk_i);
    sample_data_i  = 8'h55;
    sample_valid_i = 1'b1;
    arm_i          = 1'b1;
    clear_done_i   = 1'b1;
    @(posedge clk_i);
    #1;
    @(negedge clk_i);
    sample_valid_i = 1'b0;
    arm_i          = 1'b0;
    clear_done_i   = 1'b0;

    if (!busy_o || write_addr_o != 5 ||
        observed_write_count != writes_before_control+1)
      $fatal(1, "Busy-state arm/clear handling is incorrect");

    // Return to IDLE before the full-capture control tests.
    @(negedge clk_i);
    abort_i = 1'b1;
    @(posedge clk_i);
    #1;
    @(negedge clk_i);
    abort_i = 1'b0;

    // First full capture: verify DONE/IRQ remain latched while inputs toggle.
    complete_capture();
    held_start   = start_addr_o;
    held_trigger = trigger_addr_o;
    held_write   = write_addr_o;
    writes_before_control = observed_write_count;

    repeat (3)
      drive_sample(8'hEE, 1'b1);

    if (!capture_done_o || !irq_o || !triggered_o || !pre_ready_o)
      $fatal(1, "DONE/IRQ/status did not remain latched");
    if (observed_write_count != writes_before_control)
      $fatal(1, "DONE state allowed a BRAM write");
    if (start_addr_o != held_start || trigger_addr_o != held_trigger ||
        write_addr_o != held_write)
      $fatal(1, "DONE state did not preserve capture addresses");

    // clear_done has priority over a simultaneous arm in DONE.
    @(negedge clk_i);
    clear_done_i = 1'b1;
    arm_i        = 1'b1;
    @(posedge clk_i);
    #1;
    @(negedge clk_i);
    clear_done_i = 1'b0;
    arm_i        = 1'b0;

    if (busy_o || pre_ready_o || triggered_o || capture_done_o || irq_o)
      $fatal(1, "clear_done did not return DONE to IDLE");

    // Second full capture: arm directly from DONE must start a clean PREFILL.
    complete_capture();
    pulse_arm();

    if (!busy_o || pre_ready_o || triggered_o || capture_done_o || irq_o)
      $fatal(1, "Direct re-arm from DONE did not start a clean capture");
    if (start_addr_o != 0 || trigger_addr_o != 0 || write_addr_o != 0)
      $fatal(1, "Direct re-arm did not reset capture addresses");

    drive_sample(8'h5A, 1'b0);
    if (write_addr_o != 0)
      $fatal(1, "First write after direct re-arm was not address zero");

    @(negedge clk_i);
    abort_i = 1'b1;
    @(posedge clk_i);
    #1;
    @(negedge clk_i);
    abort_i = 1'b0;

    if (busy_o || pre_ready_o || triggered_o || capture_done_o || irq_o)
      $fatal(1, "Final abort did not return to IDLE");

    $display("PASS: abort blocked write and overrode arm/clear/trigger");
    $display("PASS: re-arm after abort restarted at address zero");
    $display("PASS: arm/clear were ignored while busy without losing sample");
    $display("PASS: DONE, IRQ and addresses remained latched");
    $display("PASS: clear_done had priority over simultaneous arm");
    $display("PASS: direct re-arm from DONE started a clean PREFILL");
    $display("tb_circular_trace_buffer_control: PASS");
    $finish;
  end

endmodule
