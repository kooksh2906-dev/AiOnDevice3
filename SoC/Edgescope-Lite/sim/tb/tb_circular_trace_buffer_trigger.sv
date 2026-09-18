`timescale 1ns/1ps

module tb_circular_trace_buffer_trigger;
  import logic_analyzer_pkg::*;

  localparam time         CLK_PERIOD           = 10ns;
  localparam int unsigned ARMED_WAIT_SAMPLES   = 7;
  localparam int unsigned EXPECTED_TRIGGER_ADDR =
      PRE_TRIGGER_SAMPLES + ARMED_WAIT_SAMPLES;
  localparam int unsigned EXPECTED_START_ADDR  = ARMED_WAIT_SAMPLES;
  localparam int unsigned EXPECTED_LAST_ADDR   = ARMED_WAIT_SAMPLES - 1;
  localparam int unsigned TOTAL_WRITES         =
      PRE_TRIGGER_SAMPLES + ARMED_WAIT_SAMPLES + POST_TRIGGER_SAMPLES;

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

  // Models BMG Port A and checks the circular physical write sequence.
  always @(posedge clk_i) begin
    if (bram_en_o) begin
      if (bram_we_o !== 4'b1111)
        $fatal(1, "Write %0d: invalid write enable %b",
               observed_write_count, bram_we_o);

      if (bram_addr_o !==
          observed_write_count[BRAM_ADDR_WIDTH-1:0])
        $fatal(1, "Write %0d: address=%0d, expected=%0d",
               observed_write_count, bram_addr_o,
               observed_write_count[BRAM_ADDR_WIDTH-1:0]);

      if (bram_wdata_o !==
          {{(BRAM_DATA_WIDTH-PROBE_WIDTH){1'b0}}, sample_data_i})
        $fatal(1, "Write %0d: BRAM data mismatch", observed_write_count);

      bram_model[bram_addr_o] <= bram_wdata_o;
      observed_write_count    <= observed_write_count + 1;
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

  initial begin
    int unsigned sample_number;
    int unsigned physical;
    int unsigned expected_sequence;
    int unsigned write_count_at_done;
    logic [BRAM_DATA_WIDTH-1:0] expected_word;

    rst_ni              = 1'b0;
    sample_data_i       = '0;
    sample_valid_i      = 1'b0;
    trigger_pulse_i     = 1'b0;
    arm_i               = 1'b0;
    clear_done_i        = 1'b0;
    abort_i             = 1'b0;
    observed_write_count = 0;

    if ($test$plusargs("VCD")) begin
      $dumpfile("tb_circular_trace_buffer_trigger.vcd");
      $dumpvars(0, tb_circular_trace_buffer_trigger);
    end

    repeat (3) @(posedge clk_i);
    @(negedge clk_i);
    rst_ni = 1'b1;

    pulse_arm();

    // Store the fixed 512-sample prefill.
    sample_number = 0;
    for (int unsigned i = 0; i < PRE_TRIGGER_SAMPLES; i++) begin
      drive_sample(sample_number[PROBE_WIDTH-1:0], 1'b0);
      sample_number++;
    end

    if (!pre_ready_o || triggered_o)
      $fatal(1, "Core did not enter untriggered ARMED state");

    // Move the circular pointer away from the 50% boundary.
    for (int unsigned i = 0; i < ARMED_WAIT_SAMPLES; i++) begin
      drive_sample(sample_number[PROBE_WIDTH-1:0], 1'b0);
      sample_number++;
    end

    if (write_addr_o !== EXPECTED_TRIGGER_ADDR-1)
      $fatal(1, "Pre-trigger last address=%0d, expected=%0d",
             write_addr_o, EXPECTED_TRIGGER_ADDR-1);

    // A trigger without sample_valid must not be accepted.
    @(negedge clk_i);
    trigger_pulse_i = 1'b1;
    @(posedge clk_i);
    #1;
    @(negedge clk_i);
    trigger_pulse_i = 1'b0;

    if (triggered_o || capture_done_o)
      $fatal(1, "Trigger was accepted without sample_valid_i");

    // This sample is both written and designated as post-trigger sample #1.
    drive_sample(sample_number[PROBE_WIDTH-1:0], 1'b1);
    sample_number++;

    if (!triggered_o || capture_done_o)
      $fatal(1, "Trigger sample did not enter POST_CAPTURE");
    if (trigger_addr_o !== EXPECTED_TRIGGER_ADDR)
      $fatal(1, "trigger_addr=%0d, expected=%0d",
             trigger_addr_o, EXPECTED_TRIGGER_ADDR);
    if (write_addr_o !== EXPECTED_TRIGGER_ADDR)
      $fatal(1, "Trigger sample and BRAM write address are not aligned");

    // Store 510 of the 511 remaining post-trigger samples.
    for (int unsigned i = 0; i < POST_TRIGGER_SAMPLES-2; i++) begin
      drive_sample(sample_number[PROBE_WIDTH-1:0], 1'b0);
      sample_number++;

      if (capture_done_o)
        $fatal(1, "capture_done_o asserted early at post sample %0d", i+2);
    end

    if (capture_done_o)
      $fatal(1, "Capture completed with only 511 total post samples");

    // This is the 511th sample after the trigger and post sample #512.
    drive_sample(sample_number[PROBE_WIDTH-1:0], 1'b0);
    sample_number++;

    if (busy_o)
      $fatal(1, "busy_o remained high after final post sample");
    if (!pre_ready_o || !triggered_o || !capture_done_o || !irq_o)
      $fatal(1, "DONE status outputs are incorrect");
    if (trigger_addr_o !== EXPECTED_TRIGGER_ADDR)
      $fatal(1, "trigger_addr changed during post capture");
    if (start_addr_o !== EXPECTED_START_ADDR)
      $fatal(1, "start_addr=%0d, expected=%0d",
             start_addr_o, EXPECTED_START_ADDR);
    if (write_addr_o !== EXPECTED_LAST_ADDR)
      $fatal(1, "last write address=%0d, expected=%0d",
             write_addr_o, EXPECTED_LAST_ADDR);
    if (observed_write_count != TOTAL_WRITES)
      $fatal(1, "Total writes=%0d, expected=%0d",
             observed_write_count, TOTAL_WRITES);

    physical = (start_addr_o + TRIGGER_LOGICAL_INDEX) &
               (CAPTURE_DEPTH-1);
    if (physical != trigger_addr_o)
      $fatal(1, "Logical trigger index maps to %0d, trigger_addr=%0d",
             physical, trigger_addr_o);

    // Read the modeled BRAM from START_ADDR and check all 1,024 retained
    // samples are consecutive in time.
    for (int unsigned i = 0; i < CAPTURE_DEPTH; i++) begin
      physical = (start_addr_o + i) & (CAPTURE_DEPTH-1);
      expected_sequence = EXPECTED_START_ADDR + i;
      expected_word = {
        {(BRAM_DATA_WIDTH-PROBE_WIDTH){1'b0}},
        expected_sequence[PROBE_WIDTH-1:0]
      };

      if (bram_model[physical] !== expected_word)
        $fatal(1,
          "Logical %0d/physical %0d: data=%08h, expected=%08h",
          i, physical, bram_model[physical], expected_word);
    end

    // DONE must stop all further writes even if the sample stream continues.
    write_count_at_done = observed_write_count;
    repeat (3)
      drive_sample(8'hEE, 1'b0);

    if (observed_write_count != write_count_at_done)
      $fatal(1, "BRAM changed after capture completed");

    $display("PASS: trigger accepted only with sample_valid");
    $display("PASS: trigger sample stored at physical address %0d",
             trigger_addr_o);
    $display("PASS: trigger sample counted as post sample #1");
    $display("PASS: exactly 511 samples stored after trigger");
    $display("PASS: start_addr=%0d, last_write_addr=%0d",
             start_addr_o, write_addr_o);
    $display("PASS: logical index 512 maps to trigger address");
    $display("PASS: all 1,024 retained samples are time ordered");
    $display("PASS: DONE stopped further BRAM writes");
    $display("tb_circular_trace_buffer_trigger: PASS");
    $finish;
  end

endmodule
