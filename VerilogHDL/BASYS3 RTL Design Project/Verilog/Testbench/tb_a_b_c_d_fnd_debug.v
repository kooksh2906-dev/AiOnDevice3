`timescale 1ns / 1ps

module tb_a_b_c_d_fnd_debug;
    reg clk;
    reg arst;
    reg btn_enter;
    reg btn_100;
    reg btn_500;
    reg btn_1000;
    reg btn_refund;
    reg [14:0] sw;

    wire [15:0] led;
    wire [6:0] seg;
    wire [3:0] an;
    wire servo_out;
    wire [7:0] ja_dbg;

    integer fail_count;

    top_a_b_c_d_fnd_debug uut (
        .clk       (clk),
        .arst      (arst),
        .btn_enter (btn_enter),
        .btn_100   (btn_100),
        .btn_500   (btn_500),
        .btn_1000  (btn_1000),
        .btn_refund(btn_refund),
        .sw        (sw),
        .led       (led),
        .seg       (seg),
        .an        (an),
        .servo_out (servo_out),
        .ja_dbg    (ja_dbg)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task check_ja;
        input [7:0] expected;
        input [8*24-1:0] label;
        begin
            #1;
            if (ja_dbg !== expected) begin
                $display("[FAIL] %s | ja_dbg=0x%02h exp=0x%02h",
                         label, ja_dbg, expected);
                fail_count = fail_count + 1;
            end
            else
                $display("[PASS] %s | ja_dbg=0x%02h", label, ja_dbg);
        end
    endtask

    initial begin
        fail_count = 0;
        arst       = 1'b1;
        btn_enter  = 1'b0;
        btn_100    = 1'b0;
        btn_500    = 1'b0;
        btn_1000   = 1'b0;
        btn_refund = 1'b0;
        sw         = 15'd0;

        repeat (10) @(posedge clk);
        arst = 1'b0;
        repeat (20) @(posedge clk);

        check_ja(8'h3f, "state 0 INSERT");

        // Conditioned Enter pulse advances INSERT -> DRINK_SEL.
        @(posedge clk);
        btn_enter <= 1'b1;
        repeat (20) @(posedge clk);
        btn_enter <= 1'b0;
        repeat (20) @(posedge clk);

        check_ja(8'h06, "state 1 DRINK_SEL");

        if (fail_count == 0)
            $display("[PASS] FND debug top elaboration/state display");
        else
            $display("[FAIL] FND debug top checks=%0d", fail_count);

        $finish;
    end

    initial begin
        #10000;
        $display("[FAIL] FND debug TB timeout");
        $finish;
    end
endmodule
