`timescale 1ns / 1ps

module top_a_b_c_d_wrapper (
    input  wire        clk,
    input  wire        arst,
    input  wire        btn_enter,
    input  wire        btn_100,
    input  wire        btn_500,
    input  wire        btn_1000,
    input  wire        btn_refund,
    input  wire [14:0] sw,

    output wire [15:0] led,
    output wire [6:0]  seg,
    output wire [3:0]  an,
    output wire        servo_out
);

    wire reset_n;
    wire btn_enter_pulse;
    wire btn_refund_pulse;
    wire fsm_enter_pulse;

    wire [14:0] fsm_led;
    wire [15:0] bcd_led;
    wire [31:0] order_info;
    wire [31:0] status_out;
    wire [31:0] inventory_out;
    wire [31:0] fsm_status_out;

    wire o_insert_en;
    wire o_soldout_en;
    wire o_nomoney_en;
    wire o_re_insert_en;
    wire o_done_en;
    wire o_servo_en;
    wire o_change_en;
    wire o_close_en;

    wire o_account_en;

    reg  account_en_d;
    reg  done_en_d;
    reg  servo_en_d;
    reg  change_en_d;

    reg  req_write;
    reg  req_read;
    reg  update_en;
    wire done_write;
    wire done_read;

    reg  flag_DONE;
    reg  flag_SERVO;
    reg  flag_CHANGE;
    wire flag_cplt_DONE;
    wire flag_cplt_SERVO;
    wire flag_cplt_CHANGE;

    reg done_cplt_latched;
    reg servo_cplt_latched;
    reg change_cplt_latched;

    reg [3:0] fsm_state;

    wire dispense_cplt_to_fsm;
    wire servo_cplt_to_fsm;
    wire change_cplt_to_fsm;

    assign reset_n = ~arst;

    btn_conditioner u_btn_enter (
        .clk    (clk),
        .arst   (arst),
        .btn_in (btn_enter),
        .btn_out(btn_enter_pulse)
    );

    btn_conditioner u_btn_refund (
        .clk    (clk),
        .arst   (arst),
        .btn_in (btn_refund),
        .btn_out(btn_refund_pulse)
    );

    top_master_fsm u_master_fsm (
        .clk             (clk),
        .arst            (arst),
        .change          (btn_refund_pulse),
        .ent             (fsm_enter_pulse),
        .i_drink_sel     (sw[14:10]),
        .i_sugar_sel     (sw[4:0]),
        .i_ice_sel       (sw[9:5]),
        .i_inventory_out (inventory_out),
        .i_statue_out    (fsm_status_out),
        .i_dispense_cplt (dispense_cplt_to_fsm),
        .i_servo_cplt    (servo_cplt_to_fsm),
        .i_change_cplt   (change_cplt_to_fsm),
        .led             (fsm_led),
        .o_order_info    (order_info),
        .o_insert_en     (o_insert_en),
        .o_account_en    (o_account_en),
        .o_soldout_en    (o_soldout_en),
        .o_nomoney_en    (o_nomoney_en),
        .o_re_insert_en  (o_re_insert_en),
        .o_done_en       (o_done_en),
        .o_servo_en      (o_servo_en),
        .o_change_en     (o_change_en),
        .o_close_en      (o_close_en)
    );

    // The A-team transition table qualifies ACCOUNT results with Enter.
    // Treat completion of the automatic read as the ACCOUNT confirmation so
    // the user does not need to press Enter a fifth time after payment.
    assign fsm_enter_pulse = btn_enter_pulse | done_read;

    // status_out retains the previous transaction result.  Present it to
    // Team A only when the current AXI read sequence has completed so a stale
    // result cannot make a later ACCOUNT state exit early.
    assign fsm_status_out = done_read ? status_out : 32'd0;

    // ACCOUNT -> AXI write -> AXI read -> money update adapter.
    // Each command is exactly one clock wide.
    always @(posedge clk or posedge arst) begin
        if (arst) begin
            account_en_d <= 1'b0;
            done_en_d    <= 1'b0;
            servo_en_d   <= 1'b0;
            change_en_d  <= 1'b0;
            req_write    <= 1'b0;
            req_read     <= 1'b0;
            update_en    <= 1'b0;
            flag_DONE    <= 1'b0;
            flag_SERVO   <= 1'b0;
            flag_CHANGE  <= 1'b0;
        end
        else begin
            account_en_d <= o_account_en;
            done_en_d    <= o_done_en;
            servo_en_d   <= o_servo_en;
            change_en_d  <= o_change_en;

            req_write   <= o_account_en & ~account_en_d;
            req_read    <= done_write;
            update_en   <= done_read && (status_out == 32'd1);

            flag_DONE   <= o_done_en   & ~done_en_d;
            flag_SERVO  <= o_servo_en  & ~servo_en_d;
            flag_CHANGE <= o_change_en & ~change_en_d;
        end
    end

    // Convert Team A state enables to the display/money state coding used by
    // the verified B+C+D wrapper.
    always @(*) begin
        if (o_nomoney_en)
            fsm_state = 4'd4;
        else if (o_done_en || o_servo_en)
            fsm_state = 4'd5;
        else if (o_soldout_en)
            fsm_state = 4'd6;
        else if (o_change_en)
            fsm_state = 4'd10;
        else
            fsm_state = 4'd0;
    end

    // D-team completion outputs are pulses.  Hold each one until Team A has
    // consumed it in the matching state.
    always @(posedge clk or posedge arst) begin
        if (arst) begin
            done_cplt_latched   <= 1'b0;
            servo_cplt_latched  <= 1'b0;
            change_cplt_latched <= 1'b0;
        end
        else begin
            if (!o_done_en)
                done_cplt_latched <= 1'b0;
            else if (flag_cplt_DONE)
                done_cplt_latched <= 1'b1;

            if (!o_servo_en)
                servo_cplt_latched <= 1'b0;
            else if (flag_cplt_SERVO)
                servo_cplt_latched <= 1'b1;

            if (!o_change_en)
                change_cplt_latched <= 1'b0;
            else if (flag_cplt_CHANGE)
                change_cplt_latched <= 1'b1;
        end
    end

    assign dispense_cplt_to_fsm = done_cplt_latched && (sw == 15'd0);
    assign servo_cplt_to_fsm    = servo_cplt_latched;
    assign change_cplt_to_fsm   = change_cplt_latched;

    top_b_c_d_wrapper u_bcd (
        .clk              (clk),
        .reset_n          (reset_n),
        .btn_100_in       (btn_100),
        .btn_500_in       (btn_500),
        .btn_1000_in      (btn_1000),
        .seg              (seg),
        .an               (an),
        .o_led            (bcd_led),
        .o_servo_pwm      (servo_out),
        .fsm_state        (fsm_state),
        .update_en        (update_en),
        .req_write        (req_write),
        .req_read         (req_read),
        .order_info       (order_info),
        .done_write       (done_write),
        .done_read        (done_read),
        .status_out       (status_out),
        .inventory_out    (inventory_out),
        .flag_SERVO       (flag_SERVO),
        .flag_CHANGE      (flag_CHANGE),
        .flag_DONE        (flag_DONE),
        .flag_cplt_SERVO  (flag_cplt_SERVO),
        .flag_cplt_CHANGE (flag_cplt_CHANGE),
        .flag_cplt_DONE   (flag_cplt_DONE)
    );

    // Team A drives selection/inventory LEDs; Team D drives the dispense
    // animation.  Their active states do not overlap.
    assign led = {1'b0, fsm_led} | bcd_led;

endmodule
