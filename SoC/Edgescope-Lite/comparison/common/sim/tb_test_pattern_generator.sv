`timescale 1ns/1ps
`default_nettype none

module tb_test_pattern_generator;

  localparam integer PRE_CYCLES = 4;
  localparam integer POST_CYCLES = 5;
  localparam integer NO_TRIGGER_CYCLES = 9;

  reg         clk;
  reg         reset_n;
  reg [25:0]  control;
  wire [1:0]  status;
  wire [7:0]  probe;

  integer cycle_number;
  integer failures;

  test_pattern_generator_gpio_adapter dut (
    .clk_i(clk),
    .reset_n_i(reset_n),
    .control_i(control),
    .status_o(status),
    .probe_test_o(probe)
  );

  defparam dut.generator_i.PRE_EVENT_CYCLES = PRE_CYCLES;
  defparam dut.generator_i.POST_EVENT_CYCLES = POST_CYCLES;
  defparam dut.generator_i.NO_TRIGGER_CYCLES = NO_TRIGGER_CYCLES;

  always #5 clk = ~clk;

  always @(posedge clk) begin
    if (!reset_n) begin
      cycle_number <= 0;
    end else begin
      cycle_number <= cycle_number + 1;
    end
  end

  task automatic check_condition;
    input condition;
    input [8*96-1:0] message;
    begin
      if (!condition) begin
        failures = failures + 1;
        $display("FAIL cycle=%0d: %0s", cycle_number, message);
      end
    end
  endtask

  task automatic wait_and_check;
    input integer count;
    input [7:0] expected_probe;
    input expected_busy;
    input expected_done;
    integer i;
    begin
      for (i = 0; i < count; i = i + 1) begin
        @(posedge clk);
        #1;
        check_condition(
          probe === expected_probe,
          "unexpected probe value"
        );
        check_condition(
          status[0] === expected_busy,
          "unexpected BUSY value"
        );
        check_condition(
          status[1] === expected_done,
          "unexpected DONE value"
        );
        check_condition(
          ((^probe !== 1'bx) && (^status !== 1'bx)),
          "X/Z detected on outputs"
        );
      end
    end
  endtask

  task automatic clear_generator;
    begin
      @(negedge clk);
      control[0] = 1'b0;
      control[25] = 1'b1;
      @(posedge clk);
      #1;
      check_condition(
        probe === 8'h00 && status === 2'b00,
        "CLEAR did not restore the safe state"
      );
      @(negedge clk);
      control[25] = 1'b0;
      @(posedge clk);
      #1;
    end
  endtask

  task automatic launch_test;
    input [3:0] test_id;
    input [19:0] pulse_width;
    input expected_accept;
    output integer accepted_cycle;
    begin
      @(negedge clk);
      control[25] = 1'b0;
      control[24:5] = pulse_width;
      control[4:1] = test_id;
      control[0] = 1'b1;
      @(posedge clk);
      #1;
      accepted_cycle = cycle_number;
      if (expected_accept) begin
        check_condition(status === 2'b01, "START was not accepted");
      end else begin
        check_condition(status === 2'b00, "invalid START was accepted");
      end
    end
  endtask

  task automatic finish_start_level;
    begin
      @(negedge clk);
      control[0] = 1'b0;
    end
  endtask

  task automatic run_normal_test;
    input [3:0] test_id;
    input [7:0] pre_value;
    input [7:0] event_value;
    integer accepted_cycle;
    integer event_cycle;
    integer done_cycle;
    begin
      clear_generator();
      launch_test(test_id, 20'd0, 1'b1, accepted_cycle);

      check_condition(probe === pre_value, "wrong pre-event value");
      wait_and_check(PRE_CYCLES - 1, pre_value, 1'b1, 1'b0);

      @(posedge clk);
      #1;
      event_cycle = cycle_number;
      check_condition(
        event_cycle - accepted_cycle == PRE_CYCLES,
        "event did not occur at accepted START + PRE_EVENT_CYCLES"
      );
      check_condition(probe === event_value, "wrong event value");
      check_condition(status === 2'b01, "BUSY dropped on event");

      wait_and_check(POST_CYCLES - 1, event_value, 1'b1, 1'b0);
      @(posedge clk);
      #1;
      done_cycle = cycle_number;
      check_condition(
        done_cycle - event_cycle == POST_CYCLES,
        "DONE did not occur at event + POST_EVENT_CYCLES"
      );
      check_condition(probe === event_value, "post-event value changed");
      check_condition(status === 2'b10, "DONE was not sticky-high");

      // START remained high for the whole run.  It must not retrigger.
      wait_and_check(3, event_value, 1'b0, 1'b1);
      finish_start_level();
    end
  endtask

  task automatic run_pulse_test;
    input [19:0] requested_width;
    input integer expected_width;
    integer accepted_cycle;
    integer event_cycle;
    integer fall_cycle;
    integer i;
    begin
      clear_generator();
      launch_test(4'h6, requested_width, 1'b1, accepted_cycle);
      check_condition(probe === 8'h00, "pulse pre-value was not zero");

      wait_and_check(PRE_CYCLES - 1, 8'h00, 1'b1, 1'b0);
      @(posedge clk);
      #1;
      event_cycle = cycle_number;
      check_condition(
        event_cycle - accepted_cycle == PRE_CYCLES,
        "pulse event timing mismatch"
      );
      check_condition(probe === 8'h01, "pulse did not rise");

      for (i = 1; i < expected_width; i = i + 1) begin
        @(posedge clk);
        #1;
        check_condition(probe === 8'h01, "pulse ended too early");
        check_condition(status === 2'b01, "BUSY dropped during pulse");
      end

      @(posedge clk);
      #1;
      fall_cycle = cycle_number;
      check_condition(
        fall_cycle - event_cycle == expected_width,
        "pulse width has an off-by-one error"
      );
      check_condition(probe === 8'h00, "pulse did not fall");
      check_condition(status === 2'b01, "BUSY dropped at pulse fall");

      wait_and_check(POST_CYCLES - 1, 8'h00, 1'b1, 1'b0);
      @(posedge clk);
      #1;
      check_condition(status === 2'b10, "pulse DONE timing mismatch");
      check_condition(probe === 8'h00, "pulse output was not safe at DONE");
      finish_start_level();
    end
  endtask

  integer accepted_cycle;
  integer no_trigger_done_cycle;

  initial begin
    clk = 1'b0;
    reset_n = 1'b0;
    control = 26'd0;
    cycle_number = 0;
    failures = 0;

    $dumpfile("test_pattern_generator_fast.vcd");
    $dumpvars(0, tb_test_pattern_generator);

    repeat (3) @(posedge clk);
    #1;
    check_condition(
      probe === 8'h00 && status === 2'b00,
      "reset values are incorrect"
    );

    @(negedge clk);
    reset_n = 1'b1;
    @(posedge clk);
    #1;

    // Reserved and SAFE IDs must reject START without changing outputs.
    launch_test(4'h0, 20'd0, 1'b0, accepted_cycle);
    check_condition(
      status === 2'b00 && probe === 8'h00,
      "SAFE ID must reject START"
    );
    finish_start_level();
    wait_and_check(2, 8'h00, 1'b0, 1'b0);

    launch_test(4'hF, 20'd0, 1'b0, accepted_cycle);
    check_condition(
      status === 2'b00 && probe === 8'h00,
      "reserved ID must reject START"
    );
    finish_start_level();
    wait_and_check(2, 8'h00, 1'b0, 1'b0);

    run_normal_test(4'h1, 8'h00, 8'h01);
    run_normal_test(4'h2, 8'h01, 8'h00);
    run_normal_test(4'h3, 8'h95, 8'hA5);
    run_normal_test(4'h4, 8'h95, 8'hA5);

    // Width zero is clamped to one full clock.
    run_pulse_test(20'd0, 1);
    run_pulse_test(20'd1, 1);
    run_pulse_test(20'd3, 3);

    // P-05 is constant zero for exactly NO_TRIGGER_CYCLES from START.
    clear_generator();
    launch_test(4'h5, 20'd0, 1'b1, accepted_cycle);
    check_condition(probe === 8'h00, "P-05 pre-value was not zero");
    wait_and_check(
      NO_TRIGGER_CYCLES - 1,
      8'h00,
      1'b1,
      1'b0
    );
    @(posedge clk);
    #1;
    no_trigger_done_cycle = cycle_number;
    check_condition(
      no_trigger_done_cycle - accepted_cycle == NO_TRIGGER_CYCLES,
      "P-05 duration mismatch"
    );
    check_condition(status === 2'b10, "P-05 did not finish");
    finish_start_level();

    // START while DONE is set must be ignored.
    @(negedge clk);
    control[4:1] = 4'h1;
    control[0] = 1'b1;
    @(posedge clk);
    #1;
    check_condition(status === 2'b10, "START was accepted while DONE");
    finish_start_level();

    // CLEAR aborts an active sequence and has priority over START.
    clear_generator();
    launch_test(4'h1, 20'd0, 1'b1, accepted_cycle);
    wait_and_check(2, 8'h00, 1'b1, 1'b0);
    @(negedge clk);
    control[25] = 1'b1;
    control[0] = 1'b1;
    @(posedge clk);
    #1;
    check_condition(
      status === 2'b00 && probe === 8'h00,
      "CLEAR did not abort or did not override START"
    );
    @(negedge clk);
    control[25] = 1'b0;
    // START is still high, so no new edge may be fabricated after CLEAR.
    wait_and_check(3, 8'h00, 1'b0, 1'b0);
    @(negedge clk);
    control[0] = 1'b0;

    // Controls are latched at START; changes during BUSY must not alter run.
    clear_generator();
    launch_test(4'h1, 20'd1, 1'b1, accepted_cycle);
    @(negedge clk);
    control[4:1] = 4'h2;
    control[24:5] = 20'd9;
    control[0] = 1'b0;
    wait_and_check(PRE_CYCLES - 1, 8'h00, 1'b1, 1'b0);
    @(posedge clk);
    #1;
    check_condition(
      probe === 8'h01,
      "latched TEST_ID changed while BUSY"
    );

    // Reset must abort from an active state.
    @(negedge clk);
    reset_n = 1'b0;
    @(posedge clk);
    #1;
    check_condition(
      status === 2'b00 && probe === 8'h00,
      "reset did not abort active sequence"
    );

    if (failures == 0) begin
      $display("TEST_PATTERN_GENERATOR_FAST: PASS");
      $finish;
    end else begin
      $fatal(1, "TEST_PATTERN_GENERATOR_FAST: %0d failure(s)", failures);
    end
  end

endmodule

`default_nettype wire
