`timescale 1ns/1ps

module tb_circular_trace_buffer_wrap;
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
  int unsigned                capture_write_count;

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
        $fatal(1, "Write %0d: bram_we_o=%b",
               capture_write_count, bram_we_o);

      if (bram_addr_o !==
          capture_write_count[BRAM_ADDR_WIDTH-1:0])
        $fatal(1, "Write %0d: address=%0d, expected=%0d",
               capture_write_count, bram_addr_o,
               capture_write_count[BRAM_ADDR_WIDTH-1:0]);

      if (bram_wdata_o !==
          {{(BRAM_DATA_WIDTH-PROBE_WIDTH){1'b0}}, sample_data_i})
        $fatal(1, "Write %0d: data mismatch", capture_write_count);

      bram_model[bram_addr_o] <= bram_wdata_o;
      capture_write_count     <= capture_write_count + 1;
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

  task automatic run_wrap_case(input int unsigned target_trigger_addr);
    int unsigned wait_samples;
    int unsigned sample_number;
    int unsigned expected_start;
    int unsigned expected_last;
    int unsigned expected_total_writes;
    int unsigned physical;
    int unsigned expected_sample_number;
    logic [BRAM_DATA_WIDTH-1:0] expected_word;
    begin
      // After PREFILL the next pointer is 512. wait_samples advances that
      // pointer to the requested trigger address.
      wait_samples = (target_trigger_addr + CAPTURE_DEPTH -
                      PRE_TRIGGER_SAMPLES) % CAPTURE_DEPTH;
      expected_start = (target_trigger_addr + CAPTURE_DEPTH -
                        PRE_TRIGGER_SAMPLES) % CAPTURE_DEPTH;
      expected_last = (target_trigger_addr + POST_TRIGGER_SAMPLES - 1) %
                      CAPTURE_DEPTH;
      expected_total_writes = CAPTURE_DEPTH + wait_samples;

      @(negedge clk_i);
      capture_write_count = 0;
      pulse_arm();

      if (!busy_o || pre_ready_o || triggered_o || capture_done_o)
        $fatal(1, "Target %0d: invalid state after arm",
               target_trigger_addr);

      sample_number = 0;

      for (int unsigned i = 0; i < PRE_TRIGGER_SAMPLES; i++) begin
        drive_sample(sample_number[PROBE_WIDTH-1:0], 1'b0);
        sample_number++;
      end

      if (!pre_ready_o || triggered_o)
        $fatal(1, "Target %0d: PREFILL completion failure",
               target_trigger_addr);

      for (int unsigned i = 0; i < wait_samples; i++) begin
        drive_sample(sample_number[PROBE_WIDTH-1:0], 1'b0);
        sample_number++;
      end

      if (bram_addr_o !== target_trigger_addr[BRAM_ADDR_WIDTH-1:0])
        $fatal(1, "Target %0d: next BRAM address=%0d",
               target_trigger_addr, bram_addr_o);

      drive_sample(sample_number[PROBE_WIDTH-1:0], 1'b1);
      sample_number++;

      if (!triggered_o || capture_done_o)
        $fatal(1, "Target %0d: trigger was not captured",
               target_trigger_addr);
      if (trigger_addr_o !== target_trigger_addr[BRAM_ADDR_WIDTH-1:0])
        $fatal(1, "Target %0d: trigger_addr_o=%0d",
               target_trigger_addr, trigger_addr_o);

      // Trigger is post sample #1, so exactly 511 more are required.
      for (int unsigned i = 1; i < POST_TRIGGER_SAMPLES; i++) begin
        drive_sample(sample_number[PROBE_WIDTH-1:0], 1'b0);
        sample_number++;

        if ((i < POST_TRIGGER_SAMPLES-1) && capture_done_o)
          $fatal(1, "Target %0d: done asserted early after %0d post samples",
                 target_trigger_addr, i+1);
      end

      if (busy_o || !capture_done_o || !irq_o || !triggered_o)
        $fatal(1, "Target %0d: invalid DONE state",
               target_trigger_addr);
      if (start_addr_o !== expected_start[BRAM_ADDR_WIDTH-1:0])
        $fatal(1, "Target %0d: start=%0d, expected=%0d",
               target_trigger_addr, start_addr_o, expected_start);
      if (write_addr_o !== expected_last[BRAM_ADDR_WIDTH-1:0])
        $fatal(1, "Target %0d: last=%0d, expected=%0d",
               target_trigger_addr, write_addr_o, expected_last);
      if (capture_write_count != expected_total_writes)
        $fatal(1, "Target %0d: writes=%0d, expected=%0d",
               target_trigger_addr, capture_write_count,
               expected_total_writes);

      physical = (start_addr_o + TRIGGER_LOGICAL_INDEX) %
                 CAPTURE_DEPTH;
      if (physical != target_trigger_addr)
        $fatal(1, "Target %0d: logical trigger maps to %0d",
               target_trigger_addr, physical);

      // The final buffer must contain the last 1,024 generated samples.
      // wait_samples is the sequence number of logical sample zero.
      for (int unsigned i = 0; i < CAPTURE_DEPTH; i++) begin
        physical = (start_addr_o + i) % CAPTURE_DEPTH;
        expected_sample_number = wait_samples + i;
        expected_word = {
          {(BRAM_DATA_WIDTH-PROBE_WIDTH){1'b0}},
          expected_sample_number[PROBE_WIDTH-1:0]
        };

        if (bram_model[physical] !== expected_word)
          $fatal(1,
            "Target %0d, logical %0d, physical %0d: got=%08h expected=%08h",
            target_trigger_addr, i, physical,
            bram_model[physical], expected_word);
      end

      $display(
        "PASS: trigger_addr=%0d start_addr=%0d last_addr=%0d writes=%0d",
        target_trigger_addr, start_addr_o, write_addr_o,
        capture_write_count);
    end
  endtask

  initial begin
    rst_ni              = 1'b0;
    sample_data_i       = '0;
    sample_valid_i      = 1'b0;
    trigger_pulse_i     = 1'b0;
    arm_i               = 1'b0;
    clear_done_i        = 1'b0;
    abort_i             = 1'b0;
    capture_write_count = 0;

    if ($test$plusargs("VCD")) begin
      $dumpfile("tb_circular_trace_buffer_wrap.vcd");
      $dumpvars(0, tb_circular_trace_buffer_wrap);
    end

    repeat (3) @(posedge clk_i);
    @(negedge clk_i);
    rst_ni = 1'b1;

    run_wrap_case(0);
    run_wrap_case(1);
    run_wrap_case(CAPTURE_DEPTH-2);
    run_wrap_case(CAPTURE_DEPTH-1);

    $display("PASS: trigger addresses 0, 1, 1022 and 1023");
    $display("PASS: all wrap-around buffers retained 1,024 ordered samples");
    $display("tb_circular_trace_buffer_wrap: PASS");
    $finish;
  end

endmodule
