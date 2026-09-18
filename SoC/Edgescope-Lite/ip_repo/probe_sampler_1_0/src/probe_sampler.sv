`timescale 1ns/1ps

module probe_sampler (
    input  logic        clk_i,
    input  logic        rst_ni,
    input  logic [7:0]  probe_i,
    input  logic        enable_i,
    input  logic        soft_clear_i,
    input  logic [1:0]  divider_sel_i,
    input  logic [7:0]  channel_mask_i,
    output logic [7:0]  sample_data_o,
    output logic        sample_valid_o,
    output logic [31:0] sample_count_o
);

    logic [2:0] divider_count_q;
    logic [1:0] divider_sel_q;

    function automatic logic [2:0] divider_terminal (
        input logic [1:0] divider_sel
    );
        case (divider_sel)
            2'b00: divider_terminal = 3'd0; // Divide by 1
            2'b01: divider_terminal = 3'd1; // Divide by 2
            2'b10: divider_terminal = 3'd3; // Divide by 4
            default: divider_terminal = 3'd7; // Divide by 8
        endcase
    endfunction

    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            divider_count_q <= 3'd0;
            divider_sel_q   <= divider_sel_i;
            sample_data_o   <= 8'h00;
            sample_valid_o  <= 1'b0;
            sample_count_o  <= 32'd0;
        end else if (soft_clear_i) begin
            divider_count_q <= 3'd0;
            divider_sel_q   <= divider_sel_i;
            sample_data_o   <= 8'h00;
            sample_valid_o  <= 1'b0;
            sample_count_o  <= 32'd0;
        end else begin
            sample_valid_o <= 1'b0;

            // Restart the divider phase when software changes the divider.
            // This prevents a stale counter value from creating a long or
            // shortened first period after a run-time configuration change.
            if (divider_sel_i != divider_sel_q) begin
                divider_count_q <= 3'd0;
                divider_sel_q   <= divider_sel_i;
            end else if (!enable_i) begin
                divider_count_q <= 3'd0;
            end else if (divider_count_q == divider_terminal(divider_sel_i)) begin
                divider_count_q <= 3'd0;
                sample_data_o   <= probe_i & channel_mask_i;
                sample_valid_o  <= 1'b1;
                sample_count_o  <= sample_count_o + 32'd1;
            end else begin
                divider_count_q <= divider_count_q + 3'd1;
            end
        end
    end

endmodule
