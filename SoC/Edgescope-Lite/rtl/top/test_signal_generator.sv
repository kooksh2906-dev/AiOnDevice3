`timescale 1ns/1ps

module test_signal_generator (
    input  logic       clk_i,
    input  logic       rst_ni,
    input  logic       manual_i,
    output logic [7:0] probe_o
);

    localparam logic [7:0] SERIAL_PATTERN = 8'h55;

    logic [31:0] counter_q;

    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            counter_q <= 32'd0;
        end else begin
            counter_q <= counter_q + 32'd1;
        end
    end

    always_comb begin
        // CH0: slow square wave
        probe_o[0] = counter_q[24];

        // CH1: faster square wave
        probe_o[1] = counter_q[20];

        // CH2: 25% duty-cycle PWM
        probe_o[2] = (counter_q[9:0] < 10'd256);

        // CH3: serialized 8'h55 pattern, one bit per 1024 clocks
        probe_o[3] = SERIAL_PATTERN[counter_q[12:10]];

        // CH4: one-clock pulse every 2^20 clocks
        probe_o[4] = (counter_q[19:0] == 20'hFFFFF);

        // CH5: deterministic multi-edge/bounce-like signal
        probe_o[5] = counter_q[18] ^ counter_q[17] ^ counter_q[16];

        // CH6: repeatable pattern component for masked triggering
        probe_o[6] = counter_q[15] & counter_q[14];

        // CH7: Basys3 switch/button or another manual source
        probe_o[7] = manual_i;
    end

endmodule
