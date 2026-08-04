`timescale 1ns / 1ps

// External one-digit display decoder (board-observed active-low polarity).
// Segment ON = 0, segment OFF = 1.
// o_ja[7:0] = {dp, g, f, e, d, c, b, a}; dp is OFF at logic 1.
module test_fnd_decoder (
    input  wire [3:0] i_state,
    output reg  [7:0] o_ja
);
    localparam SEG_0 = 8'b1100_0000;
    localparam SEG_1 = 8'b1111_1001;
    localparam SEG_2 = 8'b1010_0100;
    localparam SEG_3 = 8'b1011_0000;
    localparam SEG_4 = 8'b1001_1001;
    localparam SEG_5 = 8'b1001_0010;
    localparam SEG_6 = 8'b1000_0010;
    localparam SEG_7 = 8'b1111_1000;
    localparam SEG_8 = 8'b1000_0000;
    localparam SEG_9 = 8'b1001_0000;
    localparam SEG_A = 8'b1000_1000;
    localparam SEG_B = 8'b1000_0011;
    localparam SEG_C = 8'b1100_0110;
    localparam SEG_D = 8'b1010_0001;
    localparam SEG_E = 8'b1000_0110;
    localparam SEG_F = 8'b1000_1110;

    always @(*) begin
        case (i_state)
            4'h0: o_ja = SEG_0;
            4'h1: o_ja = SEG_1;
            4'h2: o_ja = SEG_2;
            4'h3: o_ja = SEG_3;
            4'h4: o_ja = SEG_4;
            4'h5: o_ja = SEG_5;
            4'h6: o_ja = SEG_6;
            4'h7: o_ja = SEG_7;
            4'h8: o_ja = SEG_8;
            4'h9: o_ja = SEG_9;
            4'hA: o_ja = SEG_A;
            4'hB: o_ja = SEG_B;
            4'hC: o_ja = SEG_C;
            4'hD: o_ja = SEG_D;
            4'hE: o_ja = SEG_E;
            default: o_ja = SEG_F;
        endcase
    end
endmodule

// --------------------------------------------------------------------------
// Debug-only selector/helper modules. These intentionally use unique module
// names so Vivado cannot bind the debug hierarchy to helpers in master_fsm.v.
// --------------------------------------------------------------------------
module drink_selector_dbg (
    input  wire       clk,
    input  wire       arst,
    input  wire [4:0] drink_sel,
    input  wire       flag_state,
    input  wire       flag_rst,
    output reg        flag_cplt,
    output reg  [4:0] drink_out
);
    localparam IDLE      = 5'b00000;
    localparam APPLE     = 5'b10000;
    localparam ORANGE    = 5'b01000;
    localparam MANGO     = 5'b00100;
    localparam GRAPE     = 5'b00010;
    localparam PINEAPPLE = 5'b00001;

    always @(posedge clk or posedge arst) begin
        if (arst)
            {flag_cplt, drink_out} <= 6'b0;
        else if (flag_state) begin
            case (drink_sel)
                5'b00001: {flag_cplt, drink_out} <= {1'b1, PINEAPPLE};
                5'b00010: {flag_cplt, drink_out} <= {1'b1, GRAPE};
                5'b00100: {flag_cplt, drink_out} <= {1'b1, MANGO};
                5'b01000: {flag_cplt, drink_out} <= {1'b1, ORANGE};
                5'b10000: {flag_cplt, drink_out} <= {1'b1, APPLE};
                default:  {flag_cplt, drink_out} <= {1'b0, IDLE};
            endcase
        end
        else
            {flag_cplt, drink_out} <= flag_rst ? 6'b0 : {1'b0, drink_out};
    end
endmodule

module sugar_selector_dbg (
    input  wire       clk,
    input  wire       arst,
    input  wire [4:0] sugar_sel,
    input  wire       flag_state,
    input  wire       flag_rst,
    output reg        flag_cplt,
    output reg  [4:0] led_sugar
);
    localparam IDLE      = 5'b00000;
    localparam SUGAR_20  = 5'b00001;
    localparam SUGAR_40  = 5'b00011;
    localparam SUGAR_60  = 5'b00111;
    localparam SUGAR_80  = 5'b01111;
    localparam SUGAR_100 = 5'b11111;

    always @(posedge clk or posedge arst) begin
        if (arst)
            {flag_cplt, led_sugar} <= 6'b0;
        else if (flag_state) begin
            case (sugar_sel)
                5'b00001: {flag_cplt, led_sugar} <= {1'b1, SUGAR_20};
                5'b00010: {flag_cplt, led_sugar} <= {1'b1, SUGAR_40};
                5'b00100: {flag_cplt, led_sugar} <= {1'b1, SUGAR_60};
                5'b01000: {flag_cplt, led_sugar} <= {1'b1, SUGAR_80};
                5'b10000: {flag_cplt, led_sugar} <= {1'b1, SUGAR_100};
                default:  {flag_cplt, led_sugar} <= {1'b0, IDLE};
            endcase
        end
        else
            {flag_cplt, led_sugar} <= flag_rst ? 6'b0 : {1'b0, led_sugar};
    end
endmodule

module ice_selector_dbg (
    input  wire       clk,
    input  wire       arst,
    input  wire [4:0] ice_sel,
    input  wire       flag_state,
    input  wire       flag_rst,
    output reg        flag_cplt,
    output reg  [4:0] led_ice
);
    localparam IDLE  = 5'b00000;
    localparam ICE_1 = 5'b00001;
    localparam ICE_2 = 5'b00011;
    localparam ICE_3 = 5'b00111;
    localparam ICE_4 = 5'b01111;
    localparam ICE_5 = 5'b11111;

    always @(posedge clk or posedge arst) begin
        if (arst)
            {flag_cplt, led_ice} <= 6'b0;
        else if (flag_state) begin
            case (ice_sel)
                5'b00001: {flag_cplt, led_ice} <= {1'b1, ICE_1};
                5'b00010: {flag_cplt, led_ice} <= {1'b1, ICE_2};
                5'b00100: {flag_cplt, led_ice} <= {1'b1, ICE_3};
                5'b01000: {flag_cplt, led_ice} <= {1'b1, ICE_4};
                5'b10000: {flag_cplt, led_ice} <= {1'b1, ICE_5};
                default:  {flag_cplt, led_ice} <= {1'b0, IDLE};
            endcase
        end
        else
            {flag_cplt, led_ice} <= flag_rst ? 6'b0 : {1'b0, led_ice};
    end
endmodule

module led_out_gate_dbg (
    input  wire       i_state_en,
    input  wire       apple_inv,
    input  wire       orange_inv,
    input  wire       mango_inv,
    input  wire       grape_inv,
    input  wire       pine_inv,
    input  wire [4:0] led_sugar,
    input  wire [4:0] led_ice,
    output wire [14:0] led
);
    // Fixed debug layout: [14:10]=inventory, [9:5]=sugar, [4:0]=ice.
    assign led = i_state_en ?
                 {apple_inv, orange_inv, mango_inv, grape_inv, pine_inv,
                  led_sugar, led_ice} : 15'b0;
endmodule

module sw_ctrl_gate_dbg (
    input  wire [4:0] sw_drink,
    input  wire [4:0] sw_sugar,
    input  wire [4:0] sw_ice,
    input  wire       i_cplt_drink_sel,
    input  wire       i_cplt_sugar_sel,
    input  wire       i_cplt_ice_sel,
    input  wire       i_cplt_servo,
    output reg        o_cplt_drink_sel,
    output reg        o_cplt_sugar_sel,
    output reg        o_cplt_ice_sel,
    output reg        o_cplt_servo
);
    localparam IDLE = 2'd0;
    localparam OFF  = 2'd1;
    localparam ON   = 2'd2;

    wire [1:0] drink;
    wire [1:0] sugar;
    wire [1:0] ice;

    assign drink = (sw_drink == 5'b00000) ? OFF :
                   ((sw_drink == 5'b00001) || (sw_drink == 5'b00010) ||
                    (sw_drink == 5'b00100) || (sw_drink == 5'b01000) ||
                    (sw_drink == 5'b10000)) ? ON : IDLE;

    assign sugar = (sw_sugar == 5'b00000) ? OFF :
                   ((sw_sugar == 5'b00001) || (sw_sugar == 5'b00010) ||
                    (sw_sugar == 5'b00100) || (sw_sugar == 5'b01000) ||
                    (sw_sugar == 5'b10000)) ? ON : IDLE;

    assign ice = (sw_ice == 5'b00000) ? OFF :
                 ((sw_ice == 5'b00001) || (sw_ice == 5'b00010) ||
                  (sw_ice == 5'b00100) || (sw_ice == 5'b01000) ||
                  (sw_ice == 5'b10000)) ? ON : IDLE;

    always @(*) begin
        case ({i_cplt_drink_sel, i_cplt_sugar_sel, i_cplt_ice_sel,
               i_cplt_servo, drink, sugar, ice})
            {4'b1000, ON,  OFF, OFF}: {o_cplt_drink_sel, o_cplt_sugar_sel,
                                      o_cplt_ice_sel, o_cplt_servo} = 4'b1000;
            {4'b0100, ON,  ON,  OFF}: {o_cplt_drink_sel, o_cplt_sugar_sel,
                                      o_cplt_ice_sel, o_cplt_servo} = 4'b0100;
            {4'b0010, ON,  ON,  ON }: {o_cplt_drink_sel, o_cplt_sugar_sel,
                                      o_cplt_ice_sel, o_cplt_servo} = 4'b0010;
            {4'b0001, OFF, OFF, OFF}: {o_cplt_drink_sel, o_cplt_sugar_sel,
                                      o_cplt_ice_sel, o_cplt_servo} = 4'b0001;
            default: {o_cplt_drink_sel, o_cplt_sugar_sel,
                      o_cplt_ice_sel, o_cplt_servo} = 4'b0000;
        endcase
    end
endmodule

module drink_selector_mux_dbg (
    input  wire [4:0]  i_drink_out,
    output reg  [31:0] o_order_info
);
    always @(*) begin
        case (i_drink_out)
            5'b10000: o_order_info = 32'h0000_4000;
            5'b01000: o_order_info = 32'h0000_2000;
            5'b00100: o_order_info = 32'h0000_1000;
            5'b00010: o_order_info = 32'h0000_0800;
            5'b00001: o_order_info = 32'h0000_0400;
            default:  o_order_info = 32'h0000_0000;
        endcase
    end
endmodule

module account_flag_mux_dbg (
    input  wire        i_state_en,
    input  wire [31:0] i_statue_out,
    output reg         o_pay_success,
    output reg         o_pay_nomoney,
    output reg         o_pay_soldout
);
    always @(*) begin
        if (i_state_en) begin
            case (i_statue_out)
                32'h0000_0001: {o_pay_success, o_pay_nomoney, o_pay_soldout} = 3'b100;
                32'h0000_0002: {o_pay_success, o_pay_nomoney, o_pay_soldout} = 3'b010;
                32'h0000_0003: {o_pay_success, o_pay_nomoney, o_pay_soldout} = 3'b001;
                default:       {o_pay_success, o_pay_nomoney, o_pay_soldout} = 3'b000;
            endcase
        end
        else
            {o_pay_success, o_pay_nomoney, o_pay_soldout} = 3'b000;
    end
endmodule

module masterinf2fsm_inventory_dbg (
    input  wire        i_state_en,
    input  wire [31:0] i_inventory_out,
    output wire        o_inv_apple,
    output wire        o_inv_orange,
    output wire        o_inv_mango,
    output wire        o_inv_grape,
    output wire        o_inv_pine,
    output wire        o_all_soldout
);
    assign {o_inv_apple, o_inv_orange, o_inv_mango,
            o_inv_grape, o_inv_pine} = i_inventory_out[14:10];
    assign o_all_soldout = i_state_en ? i_inventory_out[31] : 1'b0;
endmodule

// Debug wrapper around the verified master_fsm. All state enables remain
// identical; o_ja is the only added output.
module master_fsm_fnd (
    input  wire i_clk,
    input  wire i_arst,
    input  wire i_btn_change,
    input  wire i_btn_ent,
    input  wire i_drink_sel_cplt,
    input  wire i_sugar_sel_cplt,
    input  wire i_ice_sel_cplt,
    input  wire i_pay_success,
    input  wire i_pay_nomoney,
    input  wire i_pay_soldout,
    input  wire i_dispense_cplt,
    input  wire i_servo_cplt,
    input  wire i_change_cplt,
    input  wire i_all_soldout,

    output wire o_insert_en,
    output wire o_drink_sel_en,
    output wire o_sugar_sel_en,
    output wire o_ice_sel_en,
    output wire o_account_en,
    output wire o_soldout_en,
    output wire o_nomoney_en,
    output wire o_re_insert_en,
    output wire o_done_en,
    output wire o_servo_en,
    output wire o_change_en,
    output wire o_close_en,
    output wire [7:0] o_ja
);
    localparam ST_INSERT    = 4'd0;
    localparam ST_DRINK_SEL = 4'd1;
    localparam ST_SUGAR_SEL = 4'd2;
    localparam ST_ICE_SEL   = 4'd3;
    localparam ST_ACCOUNT   = 4'd4;
    localparam ST_SOLD_OUT  = 4'd5;
    localparam ST_NO_MONEY  = 4'd6;
    localparam ST_RE_INSERT = 4'd7;
    localparam ST_DONE      = 4'd8;
    localparam ST_SERVO     = 4'd9;
    localparam ST_CHANGE    = 4'd10;
    localparam ST_CLOSE     = 4'd11;

    reg [3:0] debug_state;

    master_fsm u_core (
        .i_clk            (i_clk),
        .i_arst           (i_arst),
        .i_btn_change     (i_btn_change),
        .i_btn_ent        (i_btn_ent),
        .i_drink_sel_cplt (i_drink_sel_cplt),
        .i_sugar_sel_cplt (i_sugar_sel_cplt),
        .i_ice_sel_cplt   (i_ice_sel_cplt),
        .i_pay_success    (i_pay_success),
        .i_pay_nomoney    (i_pay_nomoney),
        .i_pay_soldout    (i_pay_soldout),
        .i_dispense_cplt  (i_dispense_cplt),
        .i_servo_cplt     (i_servo_cplt),
        .i_change_cplt    (i_change_cplt),
        .i_all_soldout    (i_all_soldout),
        .o_insert_en      (o_insert_en),
        .o_drink_sel_en   (o_drink_sel_en),
        .o_sugar_sel_en   (o_sugar_sel_en),
        .o_ice_sel_en     (o_ice_sel_en),
        .o_account_en     (o_account_en),
        .o_soldout_en     (o_soldout_en),
        .o_nomoney_en     (o_nomoney_en),
        .o_re_insert_en   (o_re_insert_en),
        .o_done_en        (o_done_en),
        .o_servo_en       (o_servo_en),
        .o_change_en      (o_change_en),
        .o_close_en       (o_close_en)
    );

    always @(*) begin
        if (o_close_en)
            debug_state = ST_CLOSE;
        else if (o_change_en)
            debug_state = ST_CHANGE;
        else if (o_servo_en)
            debug_state = ST_SERVO;
        else if (o_done_en)
            debug_state = ST_DONE;
        else if (o_re_insert_en)
            debug_state = ST_RE_INSERT;
        else if (o_nomoney_en)
            debug_state = ST_NO_MONEY;
        else if (o_soldout_en)
            debug_state = ST_SOLD_OUT;
        else if (o_account_en)
            debug_state = ST_ACCOUNT;
        else if (o_ice_sel_en)
            debug_state = ST_ICE_SEL;
        else if (o_sugar_sel_en)
            debug_state = ST_SUGAR_SEL;
        else if (o_drink_sel_en)
            debug_state = ST_DRINK_SEL;
        else
            debug_state = ST_INSERT;
    end

    test_fnd_decoder u_state_decoder (
        .i_state(debug_state),
        .o_ja   (o_ja)
    );
endmodule

// Debug counterpart of top_master_fsm. Selector and payment behavior is
// unchanged; only the 8-bit external state display output is added.
module top_master_fsm_fnd (
    input  wire        clk,
    input  wire        arst,
    input  wire        change,
    input  wire        ent,
    input  wire [4:0]  i_drink_sel,
    input  wire [4:0]  i_sugar_sel,
    input  wire [4:0]  i_ice_sel,
    input  wire [31:0] i_inventory_out,
    input  wire [31:0] i_statue_out,
    input  wire        i_dispense_cplt,
    input  wire        i_servo_cplt,
    input  wire        i_change_cplt,

    output wire [14:0] led,
    output wire [31:0] o_order_info,
    output wire        o_insert_en,
    output wire        o_account_en,
    output wire        o_soldout_en,
    output wire        o_nomoney_en,
    output wire        o_re_insert_en,
    output wire        o_done_en,
    output wire        o_servo_en,
    output wire        o_change_en,
    output wire        o_close_en,
    output wire [7:0]  o_ja
);
    wire drink_sel_cplt;
    wire sugar_sel_cplt;
    wire ice_sel_cplt;
    wire pay_success;
    wire pay_nomoney;
    wire pay_soldout;
    wire servo_cplt;
    wire all_soldout;

    wire drink_sel_done;
    wire sugar_sel_done;
    wire ice_sel_done;

    wire drink_sel_en;
    wire sugar_sel_en;
    wire ice_sel_en;

    wire [4:0] drink_out;
    wire [4:0] sugar_led;
    wire [4:0] ice_led;

    wire apple_inv;
    wire orange_inv;
    wire mango_inv;
    wire grape_inv;
    wire pine_inv;
    wire led_state;

    assign led_state = o_insert_en   || drink_sel_en ||
                       sugar_sel_en  || ice_sel_en   ||
                       o_account_en  || o_soldout_en ||
                       o_nomoney_en  || o_re_insert_en;

    master_fsm_fnd U_MASTER_FSM (
        .i_clk            (clk),
        .i_arst           (arst),
        .i_btn_change     (change),
        .i_btn_ent        (ent),
        .i_drink_sel_cplt (drink_sel_cplt),
        .i_sugar_sel_cplt (sugar_sel_cplt),
        .i_ice_sel_cplt   (ice_sel_cplt),
        .i_pay_success    (pay_success),
        .i_pay_nomoney    (pay_nomoney),
        .i_pay_soldout    (pay_soldout),
        .i_dispense_cplt  (i_dispense_cplt),
        .i_servo_cplt     (servo_cplt),
        .i_change_cplt    (i_change_cplt),
        .i_all_soldout    (all_soldout),
        .o_insert_en      (o_insert_en),
        .o_drink_sel_en   (drink_sel_en),
        .o_sugar_sel_en   (sugar_sel_en),
        .o_ice_sel_en     (ice_sel_en),
        .o_account_en     (o_account_en),
        .o_soldout_en     (o_soldout_en),
        .o_nomoney_en     (o_nomoney_en),
        .o_re_insert_en   (o_re_insert_en),
        .o_done_en        (o_done_en),
        .o_servo_en       (o_servo_en),
        .o_change_en      (o_change_en),
        .o_close_en       (o_close_en),
        .o_ja             (o_ja)
    );

    drink_selector_dbg U_DRINK_SELECTOR (
        .clk        (clk),
        .arst       (arst),
        .drink_sel  (i_drink_sel),
        .flag_state (drink_sel_en),
        .flag_rst   (pay_success),
        .flag_cplt  (drink_sel_done),
        .drink_out  (drink_out)
    );

    sugar_selector_dbg U_SUGAR_SELECTOR (
        .clk        (clk),
        .arst       (arst),
        .sugar_sel  (i_sugar_sel),
        .flag_state (sugar_sel_en),
        .flag_rst   (pay_success),
        .flag_cplt  (sugar_sel_done),
        .led_sugar  (sugar_led)
    );

    ice_selector_dbg U_ICE_SELECTOR (
        .clk        (clk),
        .arst       (arst),
        .ice_sel    (i_ice_sel),
        .flag_state (ice_sel_en),
        .flag_rst   (pay_success),
        .flag_cplt  (ice_sel_done),
        .led_ice    (ice_led)
    );

    led_out_gate_dbg U_LED_OUT_GATE (
        .i_state_en (led_state),
        .apple_inv  (apple_inv),
        .orange_inv (orange_inv),
        .mango_inv  (mango_inv),
        .grape_inv  (grape_inv),
        .pine_inv   (pine_inv),
        .led_sugar  (sugar_led),
        .led_ice    (ice_led),
        .led        (led)
    );

    sw_ctrl_gate_dbg U_SW_CTRL_GATE (
        .sw_drink         (i_drink_sel),
        .sw_sugar         (i_sugar_sel),
        .sw_ice           (i_ice_sel),
        .i_cplt_drink_sel (drink_sel_done),
        .i_cplt_sugar_sel (sugar_sel_done),
        .i_cplt_ice_sel   (ice_sel_done),
        .i_cplt_servo     (i_servo_cplt),
        .o_cplt_drink_sel (drink_sel_cplt),
        .o_cplt_sugar_sel (sugar_sel_cplt),
        .o_cplt_ice_sel   (ice_sel_cplt),
        .o_cplt_servo     (servo_cplt)
    );

    drink_selector_mux_dbg U_DRINK_SELECTOR_MUX (
        .i_drink_out  (drink_out),
        .o_order_info (o_order_info)
    );

    account_flag_mux_dbg U_ACCOUNT_FLAG_MUX (
        .i_state_en   (o_account_en),
        .i_statue_out (i_statue_out),
        .o_pay_success(pay_success),
        .o_pay_nomoney(pay_nomoney),
        .o_pay_soldout(pay_soldout)
    );

    masterinf2fsm_inventory_dbg U_MASTERINF2FSM_INVENTRY (
        .i_state_en     (o_change_en),
        .i_inventory_out(i_inventory_out),
        .o_inv_apple    (apple_inv),
        .o_inv_orange   (orange_inv),
        .o_inv_mango    (mango_inv),
        .o_inv_grape    (grape_inv),
        .o_inv_pine     (pine_inv),
        .o_all_soldout  (all_soldout)
    );
endmodule
