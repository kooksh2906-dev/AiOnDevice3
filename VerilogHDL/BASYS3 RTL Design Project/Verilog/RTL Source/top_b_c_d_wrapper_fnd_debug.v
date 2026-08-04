`timescale 1ns / 1ps

// Debug-only copy of top_b_c_d_wrapper.
// The money-register state remains untouched while the on-board FND gets an
// independent display state so DONE/SERVO can show the remaining balance.
module top_b_c_d_wrapper_fnd_debug (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        btn_100_in,
    input  wire        btn_500_in,
    input  wire        btn_1000_in,
    output wire [6:0]  seg,
    output wire [3:0]  an,
    output wire [15:0] o_led,
    output wire        o_servo_pwm,

    input  wire [3:0]  fsm_state,
    input  wire        show_balance_on_fnd,
    input  wire        update_en,
    input  wire        req_write,
    input  wire        req_read,
    input  wire [31:0] order_info,
    output wire        done_write,
    output wire        done_read,
    output wire [31:0] status_out,
    output wire [31:0] inventory_out,

    input  wire flag_SERVO,
    input  wire flag_CHANGE,
    input  wire flag_DONE,
    output wire flag_cplt_SERVO,
    output wire flag_cplt_CHANGE,
    output wire flag_cplt_DONE
);
    localparam BCD_STATE_MONEY      = 4'd0;

    wire arst;
    wire [3:0] money_state;
    wire [3:0] fnd_state;

    wire w_btn_100;
    wire w_btn_500;
    wire w_btn_1000;
    wire [15:0] w_current_money;
    wire [31:0] w_change_out;

    wire [31:0] axi_awaddr;
    wire [31:0] axi_wdata;
    wire [31:0] axi_araddr;
    wire [31:0] axi_rdata;
    wire [3:0]  axi_wstrb;
    wire [1:0]  axi_bresp;
    wire [1:0]  axi_rresp;
    wire axi_awvalid;
    wire axi_awready;
    wire axi_wvalid;
    wire axi_wready;
    wire axi_bvalid;
    wire axi_bready;
    wire axi_arvalid;
    wire axi_arready;
    wire axi_rvalid;
    wire axi_rready;

    assign arst = ~reset_n;

    // Never alter the state seen by money_register. In particular, CHANGE
    // must still clear current_money exactly as in the final wrapper.
    assign money_state = fsm_state;

    // DONE keeps state code 5 and therefore displays "donE". Only SERVO
    // asserts show_balance_on_fnd and selects numeric remaining-money mode.
    assign fnd_state = show_balance_on_fnd ? BCD_STATE_MONEY : fsm_state;

    btn_conditioner u_btn_100 (
        .clk(clk), .arst(arst),
        .btn_in(btn_100_in), .btn_out(w_btn_100)
    );

    btn_conditioner u_btn_500 (
        .clk(clk), .arst(arst),
        .btn_in(btn_500_in), .btn_out(w_btn_500)
    );

    btn_conditioner u_btn_1000 (
        .clk(clk), .arst(arst),
        .btn_in(btn_1000_in), .btn_out(w_btn_1000)
    );

    money_register u_money_reg (
        .clk          (clk),
        .arst         (arst),
        .state        (money_state),
        .btn_100      (w_btn_100),
        .btn_500      (w_btn_500),
        .btn_1000     (w_btn_1000),
        .update_en    (update_en),
        .change_in    (w_change_out[15:0]),
        .current_money(w_current_money)
    );

    fnd_display_ctrl u_fnd_ctrl (
        .clk  (clk),
        .arst (arst),
        .state(fnd_state),
        .value(w_current_money),
        .seg  (seg),
        .an   (an)
    );

    axi4_master_inf u_axi_master (
        .M_AXI_ACLK   (clk),
        .M_AXI_ARESETN(reset_n),
        .req_write    (req_write),
        .order_info   (order_info),
        .money_in     ({16'd0, w_current_money}),
        .done_write   (done_write),
        .req_read     (req_read),
        .done_read    (done_read),
        .status_out   (status_out),
        .inventory_out(inventory_out),
        .change_out   (w_change_out),
        .M_AXI_AWADDR (axi_awaddr),
        .M_AXI_AWVALID(axi_awvalid),
        .M_AXI_AWREADY(axi_awready),
        .M_AXI_WDATA  (axi_wdata),
        .M_AXI_WSTRB  (axi_wstrb),
        .M_AXI_WVALID (axi_wvalid),
        .M_AXI_WREADY (axi_wready),
        .M_AXI_BRESP  (axi_bresp),
        .M_AXI_BVALID (axi_bvalid),
        .M_AXI_BREADY (axi_bready),
        .M_AXI_ARADDR (axi_araddr),
        .M_AXI_ARVALID(axi_arvalid),
        .M_AXI_ARREADY(axi_arready),
        .M_AXI_RDATA  (axi_rdata),
        .M_AXI_RRESP  (axi_rresp),
        .M_AXI_RVALID (axi_rvalid),
        .M_AXI_RREADY (axi_rready)
    );

    axi_vending_slave_v1_0_S00_AXI_fnd_debug u_axi_slave (
        .S_AXI_ACLK   (clk),
        .S_AXI_ARESETN(reset_n),
        .S_AXI_AWADDR (axi_awaddr[4:0]),
        .S_AXI_AWPROT (3'b000),
        .S_AXI_AWVALID(axi_awvalid),
        .S_AXI_AWREADY(axi_awready),
        .S_AXI_WDATA  (axi_wdata),
        .S_AXI_WSTRB  (axi_wstrb),
        .S_AXI_WVALID (axi_wvalid),
        .S_AXI_WREADY (axi_wready),
        .S_AXI_BRESP  (axi_bresp),
        .S_AXI_BVALID (axi_bvalid),
        .S_AXI_BREADY (axi_bready),
        .S_AXI_ARADDR (axi_araddr[4:0]),
        .S_AXI_ARPROT (3'b000),
        .S_AXI_ARVALID(axi_arvalid),
        .S_AXI_ARREADY(axi_arready),
        .S_AXI_RDATA  (axi_rdata),
        .S_AXI_RRESP  (axi_rresp),
        .S_AXI_RVALID (axi_rvalid),
        .S_AXI_RREADY (axi_rready)
    );

    led_animation_ctrl u_led (
        .clk           (clk),
        .reset_p       (arst),
        .flag_DONE     (flag_DONE),
        .led           (o_led),
        .flag_cplt_DONE(flag_cplt_DONE)
    );

    servo_pwm u_servo (
        .clk             (clk),
        .reset_p         (arst),
        .flag_SERVO      (flag_SERVO),
        .flag_CHANGE     (flag_CHANGE),
        .servo_out       (o_servo_pwm),
        .flag_cplt_SERVO (flag_cplt_SERVO),
        .flag_cplt_CHANGE(flag_cplt_CHANGE)
    );
endmodule
