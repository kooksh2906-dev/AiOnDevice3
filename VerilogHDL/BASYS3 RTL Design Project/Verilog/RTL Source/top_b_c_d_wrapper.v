`timescale 1ns / 1ps

module top_b_c_d_wrapper (
    // ==========================================
    // 1. 공통 시스템 신호
    // ==========================================
    input wire clk,
    input wire reset_n, // AXI 표준 Active-Low 리셋

    // ==========================================
    // 2. 물리적 외부 세계와의 핀 (사용자 인터페이스)
    // ==========================================
    // [입력] 버튼
    input wire btn_100_in,
    input wire btn_500_in,
    input wire btn_1000_in,
    // [출력] 디스플레이 & 하드웨어 구동계
    output wire [6:0]  seg,
    output wire [3:0]  an,
    output wire [15:0] o_led,
    output wire        o_servo_pwm,

    // ==========================================
    // 3. ⭐️ 팀원 A (Main FSM) 소켓 핀들 (테스트벤치가 제어할 핀)
    // ==========================================
    // FSM 상태 및 돈통 제어
    input wire [3:0] fsm_state,  // FSM의 현재 상태 (화면 출력 및 돈통 초기화용)
    input wire       update_en,  // AXI Read 후 잔돈을 돈통에 덮어쓸지 묻는 허가 핀

    // AXI 마스터 제어
    input wire        req_write,  // 결제 3단 콤보 시작 명령
    input wire        req_read,   // 결과 3단 읽기 시작 명령
    input wire [31:0] order_info, // FSM이 결정한 음료수 주소 (예: 0x4000)
    output wire       done_write, // 마스터의 쓰기 콤보 완료 보고
    output wire       done_read,  // 마스터의 읽기 콤보 완료 보고
    output wire [31:0] status_out,   // 마스터가 읽어온 결제 상태 (0,1,2,3)
    output wire [31:0] inventory_out,// 마스터가 읽어온 재고 현황

    // 근육/시각 제어 (팀원 D)
    input  wire flag_SERVO,
    input  wire flag_CHANGE,
    input  wire flag_DONE,
    output wire flag_cplt_SERVO,
    output wire flag_cplt_CHANGE,
    output wire flag_cplt_DONE
);

    // ==========================================
    // 내부 연결용 와이어 선언
    // ==========================================
    wire arst = ~reset_n; // Active-High 리셋 변환

    wire w_btn_100, w_btn_500, w_btn_1000; // 정제된 1클럭 펄스 버튼
    wire [15:0] w_current_money;           // 돈통에 누적된 현재 금액
    wire [31:0] w_change_out;              // AXI 마스터가 수거해온 잔돈 데이터

    // AXI4-Lite 채널 통신선 (B의 Master와 C의 Slave를 연결할 거대한 도로)
    wire [31:0] axi_awaddr, axi_wdata, axi_araddr, axi_rdata;
    wire [3:0]  axi_wstrb;
    wire [1:0]  axi_bresp, axi_rresp;
    wire axi_awvalid, axi_awready, axi_wvalid, axi_wready;
    wire axi_bvalid, axi_bready, axi_arvalid, axi_arready;
    wire axi_rvalid, axi_rready;

    // ==========================================
    // [팀원 B] 프론트엔드 모듈 인스턴스화
    // ==========================================
    
    // 1. 버튼 정제기 (100, 500, 1000원)
    btn_conditioner u_btn_100  (.clk(clk), .arst(arst), .btn_in(btn_100_in),  .btn_out(w_btn_100));
    btn_conditioner u_btn_500  (.clk(clk), .arst(arst), .btn_in(btn_500_in),  .btn_out(w_btn_500));
    btn_conditioner u_btn_1000 (.clk(clk), .arst(arst), .btn_in(btn_1000_in), .btn_out(w_btn_1000));

    // 2. 돈통 레지스터
    money_register u_money_reg (
        .clk(clk), .arst(arst),
        .state(fsm_state),
        .btn_100(w_btn_100), .btn_500(w_btn_500), .btn_1000(w_btn_1000),
        .update_en(update_en),          // ⭐️ 테스트벤치(FSM)가 잔돈 갱신 시점을 알려줌
        .change_in(w_change_out[15:0]), // ⭐️ AXI 마스터가 읽어온 잔돈을 돈통에 직결!
        .current_money(w_current_money)
    );

    // 3. FND 디스플레이
    fnd_display_ctrl u_fnd_ctrl (
        .clk(clk), .arst(arst),
        .state(fsm_state),
        .value(w_current_money), // 화면에 띄울 돈
        .seg(seg), .an(an)
    );

    // 4. AXI4-Lite Master (통신 모듈)
    axi4_master_inf u_axi_master (
        .M_AXI_ACLK(clk), .M_AXI_ARESETN(reset_n),
        .req_write(req_write), .order_info(order_info),
        .money_in({16'd0, w_current_money}), // 16비트 돈을 32비트로 확장
        .done_write(done_write),
        .req_read(req_read), .done_read(done_read),
        .status_out(status_out), .inventory_out(inventory_out),
        .change_out(w_change_out), // 이 잔돈이 다시 돈통(change_in)으로 흘러 들어감
        // AXI 핀 연결
        .M_AXI_AWADDR(axi_awaddr), .M_AXI_AWVALID(axi_awvalid), .M_AXI_AWREADY(axi_awready),
        .M_AXI_WDATA(axi_wdata), .M_AXI_WSTRB(axi_wstrb), .M_AXI_WVALID(axi_wvalid), .M_AXI_WREADY(axi_wready),
        .M_AXI_BRESP(axi_bresp), .M_AXI_BVALID(axi_bvalid), .M_AXI_BREADY(axi_bready),
        .M_AXI_ARADDR(axi_araddr), .M_AXI_ARVALID(axi_arvalid), .M_AXI_ARREADY(axi_arready),
        .M_AXI_RDATA(axi_rdata), .M_AXI_RRESP(axi_rresp), .M_AXI_RVALID(axi_rvalid), .M_AXI_RREADY(axi_rready)
    );

    // ==========================================
    // [팀원 C] AXI Slave (자판기 코어)
    // ==========================================
    axi_vending_slave_v1_0_S00_AXI u_axi_slave (
        .S_AXI_ACLK(clk), .S_AXI_ARESETN(reset_n),
        // AXI 핀 연결 (마스터와 1:1 직결)
        .S_AXI_AWADDR(axi_awaddr[4:0]), .S_AXI_AWPROT(3'b000), .S_AXI_AWVALID(axi_awvalid), .S_AXI_AWREADY(axi_awready),
        .S_AXI_WDATA(axi_wdata), .S_AXI_WSTRB(axi_wstrb), .S_AXI_WVALID(axi_wvalid), .S_AXI_WREADY(axi_wready),
        .S_AXI_BRESP(axi_bresp), .S_AXI_BVALID(axi_bvalid), .S_AXI_BREADY(axi_bready),
        .S_AXI_ARADDR(axi_araddr[4:0]), .S_AXI_ARPROT(3'b000), .S_AXI_ARVALID(axi_arvalid), .S_AXI_ARREADY(axi_arready),
        .S_AXI_RDATA(axi_rdata), .S_AXI_RRESP(axi_rresp), .S_AXI_RVALID(axi_rvalid), .S_AXI_RREADY(axi_rready)
    );

    // ==========================================
    // [팀원 D] LED & 서보 모터 (구동계)
    // ==========================================
    led_animation_ctrl u_led (
        .clk(clk), .reset_p(arst),
        .flag_DONE(flag_DONE), .led(o_led), .flag_cplt_DONE(flag_cplt_DONE)
    );

    servo_pwm u_servo (
        .clk(clk), .reset_p(arst),
        .flag_SERVO(flag_SERVO), .flag_CHANGE(flag_CHANGE),
        .servo_out(o_servo_pwm),
        .flag_cplt_SERVO(flag_cplt_SERVO), .flag_cplt_CHANGE(flag_cplt_CHANGE)
    );

endmodule
