`timescale 1ns/1ps

module tb_circular_trace_buffer_basic;
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

  logic [BRAM_DATA_WIDTH-1:0] bram_model [0:CAPTURE_DEPTH-1];
  int unsigned                observed_write_count;

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

  // BRAM model and write-address scoreboard. Values are sampled on the same
  // rising edge on which a real Block Memory Generator would perform a write.
  always @(posedge clk_i) begin
    if (bram_en_o) begin
      if (bram_we_o !== 4'b1111)
        $fatal(1, "Write %0d: bram_we_o=%b, expected 1111",
               observed_write_count, bram_we_o);

      if (bram_addr_o !== observed_write_count[BRAM_ADDR_WIDTH-1:0])
        $fatal(1, "Write %0d: address=%0d, expected=%0d",
               observed_write_count, bram_addr_o,
               observed_write_count[BRAM_ADDR_WIDTH-1:0]);

      if (bram_wdata_o !== {{(BRAM_DATA_WIDTH-PROBE_WIDTH){1'b0}},
                             sample_data_i})
        $fatal(1, "Write %0d: data=%08h, sample=%02h",
               observed_write_count, bram_wdata_o, sample_data_i);

      bram_model[bram_addr_o] <= bram_wdata_o;
      observed_write_count    <= observed_write_count + 1;
    end
  end

  task automatic drive_one_sample(
    input logic [PROBE_WIDTH-1:0] data,
    input logic                   trigger
  );
    begin
      @(negedge clk_i);
      sample_data_i    = data;
      sample_valid_i   = 1'b1;
      trigger_pulse_i  = trigger;

      @(posedge clk_i);
      #1;

      @(negedge clk_i);
      sample_valid_i   = 1'b0;
      trigger_pulse_i  = 1'b0;
    end
  endtask

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

  initial begin
    rst_ni           = 1'b0;
    sample_data_i    = '0;
    sample_valid_i   = 1'b0;
    trigger_pulse_i  = 1'b0;
    arm_i            = 1'b0;
    clear_done_i     = 1'b0;
    abort_i          = 1'b0;
    observed_write_count = 0;

    if ($test$plusargs("VCD")) begin
      $dumpfile("tb_circular_trace_buffer_basic.vcd");
      $dumpvars(0, tb_circular_trace_buffer_basic);
    end

    repeat (3) @(posedge clk_i);
    @(negedge clk_i);
    rst_ni = 1'b1;
    @(posedge clk_i);
    #1;

    if (busy_o || pre_ready_o || triggered_o || capture_done_o || irq_o)
      $fatal(1, "Reset state outputs are not idle");
    if (bram_en_o || (bram_we_o != 4'b0000))
      $fatal(1, "BRAM write active while idle");

    pulse_arm();

    if (!busy_o)
      $fatal(1, "busy_o did not assert after arm");
    if (pre_ready_o)
      $fatal(1, "pre_ready_o asserted before prefill");

    // sample_valid=0 must not move the pointer or write the BRAM.
    repeat (3) begin
      @(posedge clk_i);
      #1;
      if (bram_en_o || (write_addr_o != 0) || (observed_write_count != 0))
        $fatal(1, "State changed while sample_valid_i=0");
    end

    // First 511 samples must remain in PREFILL.
    for (int unsigned i = 0; i < PRE_TRIGGER_SAMPLES-1; i++) begin
      // Exercise the frozen contract: an early trigger is ignored.
      drive_one_sample(i[PROBE_WIDTH-1:0], (i == 100));
      if (pre_ready_o)
        $fatal(1, "pre_ready_o asserted early after %0d samples", i+1);
      if (triggered_o)
        $fatal(1, "PREFILL trigger was accepted after %0d samples", i+1);
      if (write_addr_o !== i[BRAM_ADDR_WIDTH-1:0])
        $fatal(1, "Last write address mismatch after sample %0d", i+1);
    end

    // A trigger concurrent with the 512th sample is also still PREFILL and
    // must be ignored. The edge only completes PREFILL and enters ARMED.
    drive_one_sample(8'hA5, 1'b1);

    if (!busy_o || !pre_ready_o)
      $fatal(1, "Core did not enter ARMED after 512 samples");
    if (triggered_o || capture_done_o || irq_o)
      $fatal(1, "Trigger/done asserted without a trigger");
    if (write_addr_o !== 10'd511)
      $fatal(1, "512th sample was not written to address 511");
    if (observed_write_count != PRE_TRIGGER_SAMPLES)
      $fatal(1, "Observed %0d writes, expected %0d",
             observed_write_count, PRE_TRIGGER_SAMPLES);

    // Confirm that ARMED continues circular writes while waiting for trigger.
    drive_one_sample(8'hC1, 1'b0);
    drive_one_sample(8'hC2, 1'b0);
    drive_one_sample(8'hC3, 1'b0);

    if (!pre_ready_o || triggered_o || capture_done_o)
      $fatal(1, "ARMED status changed without trigger");
    if (write_addr_o !== 10'd514)
      $fatal(1, "ARMED write address=%0d, expected=514", write_addr_o);
    if (observed_write_count != PRE_TRIGGER_SAMPLES+3)
      $fatal(1, "ARMED write count mismatch");

    $display("PASS: reset and ARM");
    $display("PASS: sample_valid gating");
    $display("PASS: PREFILL and 512th-sample triggers were ignored");
    $display("PASS: PREFILL wrote 512 samples to addresses 0..511");
    $display("PASS: pre_ready asserted after exactly 512 samples");
    $display("PASS: ARMED continued writes through address 514");
    $display("tb_circular_trace_buffer_basic: PASS");
    $finish;
  end

endmodule
