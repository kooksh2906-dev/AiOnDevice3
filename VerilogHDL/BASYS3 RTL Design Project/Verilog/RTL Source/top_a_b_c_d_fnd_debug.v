`timescale 1ns / 1ps

// Debug-only A+B+C+D top. The final top_a_b_c_d_wrapper is unchanged.
module top_a_b_c_d_fnd_debug (
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
    output wire        servo_out,
    output wire [7:0]  ja_dbg,
    output wire [4:0]  ext_stock_led,
    output wire [4:0]  ext_sugar_bar,
    output wire [4:0]  ext_ice_bar
);
    wire reset_n;
    wire btn_enter_pulse;
    wire btn_refund_pulse;
    wire fsm_enter_pulse;

    // Board switch mapping used only by this debug top.
    wire [4:0] sw_drink;
    wire [4:0] sw_sugar;
    wire [4:0] sw_ice;

    wire [14:0] fsm_led;
    wire [4:0] inventory_led;
    wire [4:0] sugar_led;
    wire [4:0] ice_led;
    wire [15:0] led_status;
    wire [15:0] led_anim;
    wire led_anim_active;

    wire [31:0] order_info;
    wire [31:0] status_out;
    wire [31:0] inventory_out;
    wire [31:0] inventory_to_fsm;
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

    reg account_en_d;
    reg done_en_d;
    reg servo_en_d;
    reg change_en_d;

    reg req_write;
    reg req_read;
    reg update_en;
    wire done_write;
    wire done_read;

    reg flag_DONE;
    reg flag_SERVO;
    reg flag_CHANGE;
    wire flag_cplt_DONE;
    wire flag_cplt_SERVO;
    wire flag_cplt_CHANGE;

    reg done_cplt_latched;
    reg servo_cplt_latched;
    reg change_cplt_latched;
    reg inventory_valid;
    reg all_soldout_latched;

    reg [3:0] fsm_state;

    wire dispense_cplt_to_fsm;
    wire servo_cplt_to_fsm;
    wire change_cplt_to_fsm;

    assign reset_n = ~arst;
    assign sw_drink = sw[14:10];
    assign sw_sugar = sw[9:5];
    assign sw_ice   = sw[4:0];

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

    top_master_fsm_fnd u_master_fsm (
        .clk             (clk),
        .arst            (arst),
        .change          (btn_refund_pulse),
        .ent             (fsm_enter_pulse),
        .i_drink_sel     (sw_drink),
        .i_sugar_sel     (sw_sugar),
        .i_ice_sel       (sw_ice),
        .i_inventory_out (inventory_to_fsm),
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
        .o_close_en      (o_close_en),
        .o_ja            (ja_dbg)
    );

    assign fsm_enter_pulse = btn_enter_pulse | done_read;
    assign fsm_status_out = done_read ? status_out : 32'd0;

    // Before the first AXI read, show all five inventory LEDs as available.
    // Afterward, display the actual inventory returned by the slave.
    always @(posedge clk or posedge arst) begin
        if (arst)
            inventory_valid <= 1'b0;
        else if (done_read)
            inventory_valid <= 1'b1;
    end

    assign inventory_led = inventory_valid ? inventory_out[14:10] : 5'b11101;

    // Preserve the all-sold-out indication until reset so that the CHANGE
    // completion pulse cannot race the FSM's CLOSE decision.
    always @(posedge clk or posedge arst) begin
        if (arst)
            all_soldout_latched <= 1'b0;
        else if (inventory_out[31])
            all_soldout_latched <= 1'b1;
    end

    assign inventory_to_fsm = {all_soldout_latched, inventory_out[30:0]};

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

            req_write <= o_account_en & ~account_en_d;
            req_read  <= done_write;
            update_en <= done_read && (status_out == 32'd1);

            flag_DONE   <= o_done_en   & ~done_en_d;
            flag_SERVO  <= o_servo_en  & ~servo_en_d;
            flag_CHANGE <= o_change_en & ~change_en_d;
        end
    end

    always @(*) begin
        if (o_close_en)
            fsm_state = 4'd7;
        else if (o_nomoney_en)
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

    top_b_c_d_wrapper_fnd_debug u_bcd (
        .clk              (clk),
        .reset_n          (reset_n),
        .btn_100_in       (btn_100),
        .btn_500_in       (btn_500),
        .btn_1000_in      (btn_1000),
        .seg              (seg),
        .an               (an),
        .o_led            (led_anim),
        .o_servo_pwm      (servo_out),
        .fsm_state        (fsm_state),
        .show_balance_on_fnd(o_servo_en),
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

    // fsm_led already carries {inventory, sugar, ice}; inventory is replaced
    // by the valid-aware value above so reset immediately shows 5'b11101.
    assign sugar_led = fsm_led[9:5];
    assign ice_led   = fsm_led[4:0];
    assign led_status = {1'b0, inventory_led, sugar_led, ice_led};

    // External LED outputs are status-only.
    // They are intentionally connected before the Basys3 LED animation mux.
    // KB-1008SR LED bars are active-high, so no inversion is applied.
    //
    // ext_stock_led[4:0] = inventory availability LEDs
    // ext_sugar_bar[4:0] = sugar level LED bar
    // ext_ice_bar[4:0]   = ice level LED bar
    assign ext_stock_led = inventory_led;
    assign ext_sugar_bar = sugar_led;
    assign ext_ice_bar   = ice_led;

    // Basys3 onboard LED:
    // led[14:10] = inventory group
    // led[9:5]   = sugar group
    // led[4:0]   = ice group
    // During DONE state, onboard LED shows led_anim.
    assign led_anim_active = o_done_en || flag_DONE || done_cplt_latched;
    assign led = led_anim_active ? led_anim : led_status;
endmodule
