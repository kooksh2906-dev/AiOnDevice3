`timescale 1ns/1ps
`default_nettype none

module tb_test_pattern_generator_frozen;

  localparam integer PRE_CYCLES = 1_000_000;
  localparam integer POST_CYCLES = 1_000_000;
  localparam integer NO_TRIGGER_CYCLES = 10_000_000;

  reg         clk;
  reg         reset_n;
  reg [25:0]  control;
  wire [1:0]  status;
  wire [7:0]  probe;

  integer cycle_number;
  integer failures;
  integer accepted_cycle;
  integer event_cycle;
  integer fall_cycle;
  integer done_cycle;

  test_pattern_generator_gpio_adapter dut (
    .clk_i(clk),
    .reset_n_i(reset_n),
    .control_i(control),
    .status_o(status),
    .probe_test_o(probe)
  );

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

  task automatic clear_generator;
    begin
      @(negedge clk);
      control[0] = 1'b0;
      control[25] = 1'b1;
      @(posedge clk);
      #1;
      check_condition(status === 2'b00, "CLEAR status mismatch");
      check_condition(probe === 8'h00, "CLEAR probe mismatch");
      @(negedge clk);
      control[25] = 1'b0;
      @(posedge clk);
      #1;
    end
  endtask

  task automatic launch_test;
    input [3:0] test_id;
    input [19:0] pulse_width;
    begin
      @(negedge clk);
      control[24:5] = pulse_width;
      control[4:1] = test_id;
      control[0] = 1'b1;
      @(posedge clk);
      #1;
      accepted_cycle = cycle_number;
      check_condition(status === 2'b01, "frozen START was not accepted");
      @(negedge clk);
      control[0] = 1'b0;
    end
  endtask

  task automatic run_frozen_pulse;
    input integer pulse_width;
    begin
      clear_generator();
      launch_test(4'h6, pulse_width);

      repeat (PRE_CYCLES - 1) @(posedge clk);
      #1;
      check_condition(probe === 8'h00, "frozen pulse event was early");
      @(posedge clk);
      #1;
      event_cycle = cycle_number;
      check_condition(
        event_cycle - accepted_cycle == PRE_CYCLES,
        "frozen pulse pre-delay mismatch"
      );
      check_condition(probe === 8'h01, "frozen pulse did not rise");

      repeat (pulse_width - 1) @(posedge clk);
      #1;
      check_condition(probe === 8'h01, "frozen pulse ended early");
      @(posedge clk);
      #1;
      fall_cycle = cycle_number;
      check_condition(
        fall_cycle - event_cycle == pulse_width,
        "frozen pulse width mismatch"
      );
      check_condition(probe === 8'h00, "frozen pulse did not fall");

      repeat (POST_CYCLES - 1) @(posedge clk);
      #1;
      check_condition(status === 2'b01, "frozen pulse DONE was early");
      @(posedge clk);
      #1;
      done_cycle = cycle_number;
      check_condition(
        done_cycle - fall_cycle == POST_CYCLES,
        "frozen pulse post-event duration mismatch"
      );
      check_condition(status === 2'b10, "frozen pulse DONE missing");
    end
  endtask

  initial begin
    clk = 1'b0;
    reset_n = 1'b0;
    control = 26'd0;
    cycle_number = 0;
    failures = 0;

    repeat (3) @(posedge clk);
    @(negedge clk);
    reset_n = 1'b1;
    @(posedge clk);
    #1;

    // Frozen 10 ms pre-delay and 10 ms post-event hold.
    clear_generator();
    launch_test(4'h1, 20'd0);
    repeat (PRE_CYCLES - 1) @(posedge clk);
    #1;
    check_condition(probe === 8'h00, "frozen rising event was early");
    @(posedge clk);
    #1;
    event_cycle = cycle_number;
    check_condition(
      event_cycle - accepted_cycle == PRE_CYCLES,
      "frozen pre-delay is not exactly 1,000,000 clocks"
    );
    check_condition(probe === 8'h01, "frozen rising event missing");

    repeat (POST_CYCLES - 1) @(posedge clk);
    #1;
    check_condition(status === 2'b01, "frozen DONE was early");
    @(posedge clk);
    #1;
    done_cycle = cycle_number;
    check_condition(
      done_cycle - event_cycle == POST_CYCLES,
      "frozen post-event duration is not 1,000,000 clocks"
    );
    check_condition(status === 2'b10, "frozen rising DONE missing");

    // All six official Pulse Stress widths at the frozen 100 MHz timing.
    run_frozen_pulse(1);
    run_frozen_pulse(10);
    run_frozen_pulse(100);
    run_frozen_pulse(1_000);
    run_frozen_pulse(10_000);
    run_frozen_pulse(100_000);

    // Frozen P-05 duration is exactly 100 ms from accepted START.
    clear_generator();
    launch_test(4'h5, 20'd0);
    repeat (NO_TRIGGER_CYCLES - 1) @(posedge clk);
    #1;
    check_condition(status === 2'b01, "P-05 DONE was early");
    check_condition(probe === 8'h00, "P-05 generated an event");
    @(posedge clk);
    #1;
    done_cycle = cycle_number;
    check_condition(
      done_cycle - accepted_cycle == NO_TRIGGER_CYCLES,
      "P-05 is not exactly 10,000,000 clocks"
    );
    check_condition(status === 2'b10, "P-05 DONE missing");
    check_condition(probe === 8'h00, "P-05 output changed");

    if (failures == 0) begin
      $display("TEST_PATTERN_GENERATOR_FROZEN: PASS");
      $finish;
    end else begin
      $fatal(
        1,
        "TEST_PATTERN_GENERATOR_FROZEN: %0d failure(s)",
        failures
      );
    end
  end

endmodule

`default_nettype wire
