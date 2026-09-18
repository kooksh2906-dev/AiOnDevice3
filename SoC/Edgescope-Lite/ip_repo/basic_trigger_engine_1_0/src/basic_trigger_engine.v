`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// Basic Trigger Engine
// -----------------------------------------------------------------------------
// Frozen v2.0 core specification:
//   - 8-bit sampled input
//   - Rising, falling, and masked-pattern-entry trigger modes
//   - Synchronous active-low reset
//   - trigger_pulse_o is combinational and aligned with the current valid sample
//
// Expected state storage in this core:
//   previous_sample_q  :  8 FF
//   history_valid_q    :  1 FF
//   previous_match_q   :  1 FF
//   armed_o            :  1 FF
//   triggered_o        :  1 FF
//   trigger_count_o    : 32 FF
//                         -----
//                         44 FF total
// -----------------------------------------------------------------------------

module basic_trigger_engine (
    input  wire        clk_i,
    input  wire        rst_ni,

    input  wire [7:0]  sample_data_i,
    input  wire        sample_valid_i,

    input  wire        arm_i,
    input  wire        clear_i,

    input  wire [1:0]  mode_i,
    input  wire [2:0]  edge_channel_i,
    input  wire [7:0]  pattern_value_i,
    input  wire [7:0]  pattern_mask_i,

    output wire        trigger_pulse_o,
    output reg         armed_o,
    output reg         triggered_o,
    output reg  [31:0] trigger_count_o
);

    // Trigger mode encoding from the common specification.
    localparam [1:0] TRIGGER_DISABLED = 2'b00;
    localparam [1:0] TRIGGER_RISING   = 2'b01;
    localparam [1:0] TRIGGER_FALLING  = 2'b10;
    localparam [1:0] TRIGGER_PATTERN  = 2'b11;

    // State registers.
    reg  [7:0] previous_sample_q;
    reg        history_valid_q;
    reg        previous_match_q;

    // Combinational trigger conditions for the current sample.
    wire current_match_w;
    wire rising_condition_w;
    wire falling_condition_w;
    wire pattern_condition_w;
    reg  selected_condition_r;

    assign current_match_w =
        ((sample_data_i   & pattern_mask_i) ==
         (pattern_value_i & pattern_mask_i));

    // history_valid_q prevents an edge trigger on the first valid sample
    // received after an ARM command.
    assign rising_condition_w =
        history_valid_q &&
        !previous_sample_q[edge_channel_i] &&
         sample_data_i[edge_channel_i];

    assign falling_condition_w =
        history_valid_q &&
         previous_sample_q[edge_channel_i] &&
        !sample_data_i[edge_channel_i];

    // A zero mask is explicitly defined as "pattern trigger disabled".
    // previous_match_q makes this an entry detector instead of a level detector.
    assign pattern_condition_w =
        (pattern_mask_i != 8'b0) &&
         current_match_w &&
        !previous_match_q;

    always @(*) begin
        case (mode_i)
            TRIGGER_RISING:
                selected_condition_r = rising_condition_w;

            TRIGGER_FALLING:
                selected_condition_r = falling_condition_w;

            TRIGGER_PATTERN:
                selected_condition_r = pattern_condition_w;

            TRIGGER_DISABLED:
                selected_condition_r = 1'b0;

            default:
                selected_condition_r = 1'b0;
        endcase
    end

    // The pulse is intentionally not registered. It is visible during the
    // same cycle as the sample that satisfies the selected trigger condition.
    // ARM and CLEAR are command cycles and therefore suppress trigger output.
    assign trigger_pulse_o =
        armed_o              &&
       !triggered_o          &&
       !arm_i                &&
       !clear_i              &&
        sample_valid_i       &&
        selected_condition_r;

    // State update priority:
    //   synchronous reset > clear > arm > normal sample processing
    always @(posedge clk_i) begin
        if (!rst_ni) begin
            previous_sample_q <= 8'b0;
            history_valid_q   <= 1'b0;
            previous_match_q  <= 1'b0;
            armed_o           <= 1'b0;
            triggered_o       <= 1'b0;
            trigger_count_o   <= 32'b0;
        end
        else if (clear_i) begin
            previous_sample_q <= 8'b0;
            history_valid_q   <= 1'b0;
            previous_match_q  <= 1'b0;
            armed_o           <= 1'b0;
            triggered_o       <= 1'b0;

            // The trigger count is cumulative and is cleared only by reset.
            trigger_count_o   <= trigger_count_o;
        end
        else if (arm_i) begin
            previous_sample_q <= 8'b0;
            history_valid_q   <= 1'b0;
            previous_match_q  <= 1'b0;
            armed_o           <= 1'b1;
            triggered_o       <= 1'b0;
            trigger_count_o   <= trigger_count_o;
        end
        else begin
            if (trigger_pulse_o) begin
                triggered_o     <= 1'b1;
                trigger_count_o <= trigger_count_o + 32'd1;
            end

            // No history is collected while disarmed. After a trigger, history
            // is frozen until CLEAR or a new ARM command.
            if (armed_o && !triggered_o && sample_valid_i) begin
                previous_sample_q <= sample_data_i;
                history_valid_q   <= 1'b1;
                previous_match_q  <= current_match_w;
            end
        end
    end

endmodule
