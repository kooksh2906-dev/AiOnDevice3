`timescale 1ns/1ps
`default_nettype none

// Common deterministic stimulus for the EdgeScope-Lite comparison builds.
//
// AXI GPIO channel 1 drives control_i:
//   [0]    START_LEVEL
//   [4:1]  TEST_ID
//   [24:5] PULSE_WIDTH_CYCLES
//   [25]   CLEAR
//
// AXI GPIO channel 2 reads status_o:
//   [0] BUSY
//   [1] DONE (sticky until CLEAR)
module test_pattern_generator #(
  parameter integer PRE_EVENT_CYCLES = 1_000_000,
  parameter integer POST_EVENT_CYCLES = 1_000_000,
  parameter integer NO_TRIGGER_CYCLES = 10_000_000
) (
  input  wire         clk_i,
  input  wire         reset_n_i,
  input  wire [25:0]  control_i,
  output wire [1:0]   status_o,
  output reg  [7:0]   probe_test_o
);

  localparam [3:0] TEST_SAFE         = 4'h0;
  localparam [3:0] TEST_RISING       = 4'h1;
  localparam [3:0] TEST_FALLING      = 4'h2;
  localparam [3:0] TEST_PATTERN      = 4'h3;
  localparam [3:0] TEST_PATTERN_HOLD = 4'h4;
  localparam [3:0] TEST_NO_TRIGGER   = 4'h5;
  localparam [3:0] TEST_PULSE_STRESS = 4'h6;

  localparam [2:0] STATE_IDLE       = 3'd0;
  localparam [2:0] STATE_PRE_EVENT  = 3'd1;
  localparam [2:0] STATE_POST_EVENT = 3'd2;
  localparam [2:0] STATE_PULSE_HIGH = 3'd3;
  localparam [2:0] STATE_NO_TRIGGER = 3'd4;

  wire        start_level;
  wire [3:0]  selected_test_id;
  wire [19:0] selected_pulse_width;
  wire        clear;
  wire        start_event;
  wire        selected_test_valid;

  reg         start_level_q;
  reg         busy_q;
  reg         done_q;
  reg [2:0]   state_q;
  reg [3:0]   test_id_q;
  reg [19:0]  pulse_width_q;
  reg [31:0]  cycle_count_q;

  assign start_level = control_i[0];
  assign selected_test_id = control_i[4:1];
  assign selected_pulse_width = control_i[24:5];
  assign clear = control_i[25];

  // The AXI write may keep START_LEVEL high for many clocks.  Only its
  // rising edge is accepted as the one-clock internal start event.
  assign start_event = start_level & ~start_level_q;
  assign selected_test_valid =
    (selected_test_id >= TEST_RISING) &&
    (selected_test_id <= TEST_PULSE_STRESS);

  assign status_o = {done_q, busy_q};

  always @(posedge clk_i) begin
    if (!reset_n_i) begin
      start_level_q <= 1'b0;
      busy_q         <= 1'b0;
      done_q         <= 1'b0;
      state_q        <= STATE_IDLE;
      test_id_q      <= TEST_SAFE;
      pulse_width_q  <= 20'd1;
      cycle_count_q  <= 32'd0;
      probe_test_o   <= 8'h00;
    end else begin
      start_level_q <= start_level;

      // CLEAR has priority over START and over every active state.
      if (clear) begin
        start_level_q <= start_level;
        busy_q         <= 1'b0;
        done_q         <= 1'b0;
        state_q        <= STATE_IDLE;
        test_id_q      <= TEST_SAFE;
        pulse_width_q  <= 20'd1;
        cycle_count_q  <= 32'd0;
        probe_test_o   <= 8'h00;
      end else begin
        case (state_q)
          STATE_IDLE: begin
            cycle_count_q <= 32'd0;

            // DONE is sticky.  Software must clear it before the next run.
            // TEST_SAFE and reserved IDs deliberately reject START.
            if (start_event && !done_q && selected_test_valid) begin
              busy_q        <= 1'b1;
              done_q        <= 1'b0;
              test_id_q     <= selected_test_id;
              pulse_width_q <=
                (selected_pulse_width == 20'd0)
                  ? 20'd1 : selected_pulse_width;

              case (selected_test_id)
                TEST_FALLING:
                  probe_test_o <= 8'h01;

                TEST_PATTERN,
                TEST_PATTERN_HOLD:
                  probe_test_o <= 8'h95;

                default:
                  probe_test_o <= 8'h00;
              endcase

              if (selected_test_id == TEST_NO_TRIGGER) begin
                state_q <= STATE_NO_TRIGGER;
              end else begin
                state_q <= STATE_PRE_EVENT;
              end
            end
          end

          STATE_PRE_EVENT: begin
            if (cycle_count_q == PRE_EVENT_CYCLES - 1) begin
              cycle_count_q <= 32'd0;

              case (test_id_q)
                TEST_RISING:
                  probe_test_o <= 8'h01;

                TEST_FALLING:
                  probe_test_o <= 8'h00;

                TEST_PATTERN,
                TEST_PATTERN_HOLD:
                  probe_test_o <= 8'hA5;

                TEST_PULSE_STRESS:
                  probe_test_o <= 8'h01;

                default:
                  probe_test_o <= 8'h00;
              endcase

              if (test_id_q == TEST_PULSE_STRESS) begin
                state_q <= STATE_PULSE_HIGH;
              end else begin
                state_q <= STATE_POST_EVENT;
              end
            end else begin
              cycle_count_q <= cycle_count_q + 1'b1;
            end
          end

          STATE_PULSE_HIGH: begin
            // probe_test_o became high on the event edge.  Lower it at
            // event + pulse_width_q, giving exactly W full clock periods.
            if (cycle_count_q >= pulse_width_q - 1'b1) begin
              probe_test_o  <= 8'h00;
              cycle_count_q <= 32'd0;
              state_q       <= STATE_POST_EVENT;
            end else begin
              cycle_count_q <= cycle_count_q + 1'b1;
            end
          end

          STATE_POST_EVENT: begin
            if (cycle_count_q == POST_EVENT_CYCLES - 1) begin
              cycle_count_q <= 32'd0;
              busy_q        <= 1'b0;
              done_q        <= 1'b1;
              state_q       <= STATE_IDLE;
            end else begin
              cycle_count_q <= cycle_count_q + 1'b1;
            end
          end

          STATE_NO_TRIGGER: begin
            // P-05 observes a constant non-event input for 100 ms total
            // from the accepted START edge.
            if (cycle_count_q == NO_TRIGGER_CYCLES - 1) begin
              cycle_count_q <= 32'd0;
              busy_q        <= 1'b0;
              done_q        <= 1'b1;
              state_q       <= STATE_IDLE;
            end else begin
              cycle_count_q <= cycle_count_q + 1'b1;
            end
          end

          default: begin
            busy_q        <= 1'b0;
            done_q        <= 1'b0;
            state_q       <= STATE_IDLE;
            test_id_q     <= TEST_SAFE;
            pulse_width_q <= 20'd1;
            cycle_count_q <= 32'd0;
            probe_test_o  <= 8'h00;
          end
        endcase
      end
    end
  end

endmodule

`default_nettype wire
