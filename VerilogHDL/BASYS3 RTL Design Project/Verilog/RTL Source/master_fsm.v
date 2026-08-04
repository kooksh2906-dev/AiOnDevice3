`timescale 1ns / 1ps

// SELECT와 관련되어 동작하는 모듈
// SELECT 단계에서는 SELECT 관련된 레지스터 값은 게속 저장하다가
// DONE 단계로 넘어가기전 모두 리셋하기로

// DRINK_SEL에 동작하는 모듈
module drink_selector(
    input   wire            clk, arst,
    input   wire    [4:0]   drink_sel,
    input   wire            flag_state, // 해당 플래그가 on일때 만 동작하도록
    input   wire            flag_rst,   // 해당 플래그가 on이면 리셋
    //
    output  reg             flag_cplt,  // 해당 모듈의 동작이 완료가 되면, 해당 플래그 on
    output  reg     [4:0]   drink_out   // 고른 음료수의 종류를 AXI SLAVE로 넘겨줘야함
    );

    localparam  IDLE        = 5'b00000,
                APPLE       = 5'b10000,
                ORANGE      = 5'b01000, 
                MANGO       = 5'b00100,
                GRAPE       = 5'b00010,
                PINEAPPLE   = 5'b00001;

    always@(posedge clk, posedge arst) begin
        if(arst)
            {flag_cplt,drink_out} <= 6'b0;
        else if (flag_state) begin 
            case(drink_sel)
                5'b00001    :   {flag_cplt,drink_out} <= {1'b1,PINEAPPLE};
                5'b00010    :   {flag_cplt,drink_out} <= {1'b1,GRAPE};
                5'b00100    :   {flag_cplt,drink_out} <= {1'b1,MANGO};
                5'b01000    :   {flag_cplt,drink_out} <= {1'b1,ORANGE};
                5'b10000    :   {flag_cplt,drink_out} <= {1'b1,APPLE};
                default     :   {flag_cplt,drink_out} <= {1'b0,IDLE};
            endcase
        end
        else // ACCOUNT 단계까지는 레지스터 값을 유지하다가, ACCOUNT_cplt(i_pay_success)를 받으면 리셋
            {flag_cplt,drink_out} <= flag_rst? 6'b0: {1'b0,drink_out};
    end

endmodule

// SUGAR_SEL에 동작하는 모듈
module sugar_selector(
    input   wire            clk, arst,
    input   wire    [4:0]   sugar_sel,
    input   wire            flag_state, // 해당 플래그가 on일때 만 동작하도록
    input   wire            flag_rst,   // 해당 플래그가 on이면 리셋
    //
    output  reg             flag_cplt,  // 해당 모듈의 동작이 완료가 되면, 해당 플래그 on
    output  reg     [4:0]   led_sugar
    );
    localparam  IDLE        = 5'b00000,
                SUGAR_20    = 5'b00001,
                SUGAR_40    = 5'b00011,
                SUGAR_60    = 5'b00111,
                SUGAR_80    = 5'b01111,
                SUGAR_100   = 5'b11111;

    always@(posedge clk, posedge arst) begin
        if(arst)
            {flag_cplt,led_sugar} <= 6'b0;
        else if(flag_state) begin
            case(sugar_sel)
                5'b00001    :   {flag_cplt,led_sugar} <= {1'b1,SUGAR_20};
                5'b00010    :   {flag_cplt,led_sugar} <= {1'b1,SUGAR_40};
                5'b00100    :   {flag_cplt,led_sugar} <= {1'b1,SUGAR_60};
                5'b01000    :   {flag_cplt,led_sugar} <= {1'b1,SUGAR_80};
                5'b10000    :   {flag_cplt,led_sugar} <= {1'b1,SUGAR_100};
                default     :   {flag_cplt,led_sugar} <= {1'b0,IDLE};
            endcase
        end
        else // ACCOUNT 단계까지는 레지스터 값을 유지하다가, ACCOUNT_cplt(i_pay_success)를 받으면 리셋
            {flag_cplt,led_sugar} <= flag_rst? 6'b0: {1'b0,led_sugar};

    end

endmodule

// ICE_SEL에 동작하는 모듈
module ice_selector(
    input   wire            clk, arst,
    input   wire    [4:0]   ice_sel,
    input   wire            flag_state, // 해당 플래그가 on일때 만 동작하도록
    input   wire            flag_rst,   // 해당 플래그가 on이면 리셋
    //
    output  reg             flag_cplt,  // 해당 모듈의 동작이 완료가 되면, 해당 플래그 on
    output  reg     [4:0]   led_ice
    );

    localparam  IDLE    = 5'b00000,
                ICE_1   = 5'b00001,
                ICE_2   = 5'b00011,
                ICE_3   = 5'b00111,
                ICE_4   = 5'b01111,
                ICE_5   = 5'b11111;

    always@(posedge clk, posedge arst) begin
        if(arst)
            {flag_cplt,led_ice} <= 6'b0;
        else if(flag_state) begin
            case(ice_sel)
                5'b00001    :   {flag_cplt,led_ice} <= {1'b1,ICE_1};
                5'b00010    :   {flag_cplt,led_ice} <= {1'b1,ICE_2};
                5'b00100    :   {flag_cplt,led_ice} <= {1'b1,ICE_3};
                5'b01000    :   {flag_cplt,led_ice} <= {1'b1,ICE_4};
                5'b10000    :   {flag_cplt,led_ice} <= {1'b1,ICE_5};
                default     :   {flag_cplt,led_ice} <= {1'b0,IDLE};
            endcase
        end
        else // ACCOUNT 단계까지는 레지스터 값을 유지하다가, ACCOUNT_cplt(i_pay_success)를 받으면 리셋
            {flag_cplt,led_ice} <= flag_rst? 6'b0: {1'b0,led_ice};

    end

endmodule

module master_fsm(
    // 
    input   wire            i_clk,
    input   wire            i_arst,             // Asynchronous Reset (Active High)
    input   wire            i_btn_change,       // 잔돈 반환 레버 버튼
    input   wire            i_btn_ent,          // 선택 및 승인(Enter) 버튼

    // cplt flag
    input   wire            i_drink_sel_cplt,   // 음료 선택 완료
    input   wire            i_sugar_sel_cplt,   // 당도 선택 완료
    input   wire            i_ice_sel_cplt,     // 얼음 선택 완료
    input   wire            i_pay_success,      // 결제 연산 결과: 성공(금액 충분)
    input   wire            i_pay_nomoney,      // 결제 연산 결과: 금액 부족
    input   wire            i_pay_soldout,      // 결제 연산 결과: 재고 부족
    input   wire            i_dispense_cplt,    // 음료 제조 및 LED 애니메이션 완료, 팀원 C가 생성
    input   wire            i_servo_cplt,       // 서보모터 구동 및 원위치 완료, 팀원 C가 생성
    input   wire            i_change_cplt,      // 잔돈 물리 반환 완료, 팀원 C가 생성
    input   wire            i_all_soldout,      // 자판기 전체 품절(영업 종료 조건)
    
    // state flag
    output  reg             o_insert_en,        // 동전 투입 단계 활성화, 팀원 B한테 넘겨줘야 함
    output  reg             o_drink_sel_en,     // 음료 선택 단계 활성화
    output  reg             o_sugar_sel_en,     // 당도 선택 단계 활성화
    output  reg             o_ice_sel_en,       // 얼음 선택 단계 활성화
    output  reg             o_account_en,       // 결제 승인 대기 단계 활성화
    output  reg             o_soldout_en,   	// 선택 음료 품절 경고창 표시, 팀원 B한테 넘겨줘야 함
    output  reg             o_nomoney_en,   	// 잔액 부족 경고창 표시, 팀원 B한테 넘겨줘야 함
    output  reg             o_re_insert_en,     // 금액 추가 투입 유도 표시, 팀원 B한테 넘겨줘야 함
    output  reg             o_done_en,    		// 음료 제조/애니메이션 가동, 팀원 B/팀원 C한테 넘겨줘야 함
    output  reg             o_servo_en,         // 서보모터 배출 가동, 팀원 C한테 넘겨줘야 함
    output  reg             o_change_en, 		// 잔돈 반환기 가동, 팀원 B/팀원 C한테 넘겨줘야 함
    output  reg             o_close_en   		// 영업 종료(CLOSE) 안내 표시, 팀원 B한테 넘겨줘야 함
);

    localparam  INSERT      = 4'd0,
                DRINK_SEL   = 4'd1,
                SUGAR_SEL   = 4'd2,
                ICE_SEL     = 4'd3,
                ACCOUNT     = 4'd4,
                SOLD_OUT    = 4'd5,
                NO_MONEY    = 4'd6,
                RE_INSERT   = 4'd7,
                DONE        = 4'd8,
                SERVO       = 4'd9,
                CHANGE      = 4'd10,
                CLOSE       = 4'd11;

    reg     [3:0]   state, next_state;

    always@(posedge i_clk, posedge i_arst) begin
        if(i_arst)
            state <= INSERT;
        else
            state <= next_state;
    end

    always@(*) begin
        casex({state, i_btn_change, i_btn_ent,
                      i_drink_sel_cplt, // bit[9]
                      i_sugar_sel_cplt, // bit[8]
                      i_ice_sel_cplt,   // bit[7]
                      i_pay_success,    // bit[6]
                      i_pay_nomoney,    // bit[5]
                      i_pay_soldout,    // bit[4]
                      i_dispense_cplt,  // bit[3]
                      i_servo_cplt,     // bit[2]
                      i_change_cplt,    // bit[1]
                      i_all_soldout     // bit[0]
            }) 
            
            // INSERT 상태
            {INSERT, 12'b1xxx_xxxx_xxxx}     :    next_state = CHANGE;
            {INSERT, 12'b01xx_xxxx_xxxx}     :    next_state = DRINK_SEL;
            
            // DRINK_SEL 상태
            {DRINK_SEL, 12'b1xxx_xxxx_xxxx}  :    next_state = CHANGE;
            {DRINK_SEL, 12'b011x_xxxx_xxxx}  :    next_state = SUGAR_SEL;
            
            // SUGAR_SEL 상태
            {SUGAR_SEL, 12'b1xxx_xxxx_xxxx}  :    next_state = CHANGE;
            {SUGAR_SEL, 12'b01x1_xxxx_xxxx}  :    next_state = ICE_SEL;
            
            // ICE_SEL 상태
            {ICE_SEL, 12'b1xxx_xxxx_xxxx}    :    next_state = CHANGE;
            {ICE_SEL, 12'b01xx_1xxx_xxxx}    :    next_state = ACCOUNT;
            
            // ACCOUNT 상태 
            {ACCOUNT, 12'b1xxx_xxxx_xxxx}    :    next_state = CHANGE;
            {ACCOUNT, 12'b01xx_x100_xxxx}    :    next_state = DONE;
            {ACCOUNT, 12'b01xx_x010_xxxx}    :    next_state = NO_MONEY;
            {ACCOUNT, 12'b01xx_x001_xxxx}    :    next_state = SOLD_OUT;
            
            // SOLD_OUT 상태
            {SOLD_OUT, 12'b1xxx_xxxx_xxxx}   :    next_state = CHANGE;
            {SOLD_OUT, 12'b01xx_xxxx_xxxx}   :    next_state = DRINK_SEL;
            
            // NO_MONEY 상태
            {NO_MONEY, 12'b1xxx_xxxx_xxxx}   :    next_state = CHANGE;
            {NO_MONEY, 12'b01xx_xxxx_xxxx}   :    next_state = RE_INSERT;
            
            // RE_INSERT 상태
            {RE_INSERT, 12'b1xxx_xxxx_xxxx}  :    next_state = CHANGE;
            {RE_INSERT, 12'b01xx_xxxx_xxxx}  :    next_state = ACCOUNT;
            
            // DONE 상태
            {DONE, 12'bxxxx_xxxx_1xxx}       :    next_state = SERVO;
            
            // SERVO 상태 
            {SERVO, 12'b1xxx_xxxx_x1xx}      :    next_state = CHANGE;
            
            // CHANGE 상태
            {CHANGE, 12'bxxxx_xxxx_xx10}     :    next_state = INSERT;
            {CHANGE, 12'bxxxx_xxxx_xx11}     :    next_state = CLOSE;
            
            // CLOSE 상태
            {CLOSE, 12'bxxxx_xxxx_xxxx}      :    next_state = CLOSE;
            
            default                          :    next_state = state;
        endcase
    end

    always@(*) begin
        case(state)
            INSERT    : {o_close_en, o_change_en, o_servo_en, o_done_en, o_re_insert_en, o_nomoney_en, o_soldout_en, o_account_en, o_ice_sel_en, o_sugar_sel_en, o_drink_sel_en, o_insert_en} = 12'h001;
            DRINK_SEL : {o_close_en, o_change_en, o_servo_en, o_done_en, o_re_insert_en, o_nomoney_en, o_soldout_en, o_account_en, o_ice_sel_en, o_sugar_sel_en, o_drink_sel_en, o_insert_en} = 12'h002;
            SUGAR_SEL : {o_close_en, o_change_en, o_servo_en, o_done_en, o_re_insert_en, o_nomoney_en, o_soldout_en, o_account_en, o_ice_sel_en, o_sugar_sel_en, o_drink_sel_en, o_insert_en} = 12'h004;
            ICE_SEL   : {o_close_en, o_change_en, o_servo_en, o_done_en, o_re_insert_en, o_nomoney_en, o_soldout_en, o_account_en, o_ice_sel_en, o_sugar_sel_en, o_drink_sel_en, o_insert_en} = 12'h008;
            ACCOUNT   : {o_close_en, o_change_en, o_servo_en, o_done_en, o_re_insert_en, o_nomoney_en, o_soldout_en, o_account_en, o_ice_sel_en, o_sugar_sel_en, o_drink_sel_en, o_insert_en} = 12'h010;
            SOLD_OUT  : {o_close_en, o_change_en, o_servo_en, o_done_en, o_re_insert_en, o_nomoney_en, o_soldout_en, o_account_en, o_ice_sel_en, o_sugar_sel_en, o_drink_sel_en, o_insert_en} = 12'h020;
            NO_MONEY  : {o_close_en, o_change_en, o_servo_en, o_done_en, o_re_insert_en, o_nomoney_en, o_soldout_en, o_account_en, o_ice_sel_en, o_sugar_sel_en, o_drink_sel_en, o_insert_en} = 12'h040;
            RE_INSERT : {o_close_en, o_change_en, o_servo_en, o_done_en, o_re_insert_en, o_nomoney_en, o_soldout_en, o_account_en, o_ice_sel_en, o_sugar_sel_en, o_drink_sel_en, o_insert_en} = 12'h080;
            DONE      : {o_close_en, o_change_en, o_servo_en, o_done_en, o_re_insert_en, o_nomoney_en, o_soldout_en, o_account_en, o_ice_sel_en, o_sugar_sel_en, o_drink_sel_en, o_insert_en} = 12'h100;
            SERVO     : {o_close_en, o_change_en, o_servo_en, o_done_en, o_re_insert_en, o_nomoney_en, o_soldout_en, o_account_en, o_ice_sel_en, o_sugar_sel_en, o_drink_sel_en, o_insert_en} = 12'h200;
            CHANGE    : {o_close_en, o_change_en, o_servo_en, o_done_en, o_re_insert_en, o_nomoney_en, o_soldout_en, o_account_en, o_ice_sel_en, o_sugar_sel_en, o_drink_sel_en, o_insert_en} = 12'h400;
            CLOSE     : {o_close_en, o_change_en, o_servo_en, o_done_en, o_re_insert_en, o_nomoney_en, o_soldout_en, o_account_en, o_ice_sel_en, o_sugar_sel_en, o_drink_sel_en, o_insert_en} = 12'h800;
            default   : {o_close_en, o_change_en, o_servo_en, o_done_en, o_re_insert_en, o_nomoney_en, o_soldout_en, o_account_en, o_ice_sel_en, o_sugar_sel_en, o_drink_sel_en, o_insert_en} = 12'h000;
        endcase
    end

endmodule

// 어차피 각 selector 모듈은 sequntial logic 이고
// 출력 아웃풋은 clk 및 리셋에 따라 동작하므로,
// combinational logic으로먼 구성해도 무방함
module led_out_gate(
    input	wire			i_state_en,	// state 활성화 flag 입력
    input   wire            apple_inv, orange_inv, mango_inv, grape_inv, pine_inv, // 음료 종류 별 재고
    input   wire    [4:0]   led_sugar, led_ice, // 당도, 얼음 별 선택
    //
    output	wire 	[14:0]  led
    );

	assign led = i_state_en? {apple_inv, orange_inv, mango_inv, grape_inv, pine_inv,led_sugar, led_ice}: 15'b0;

endmodule

// sw를 누른 개수와 하위 모듈에서 나오는 cplt flag를 조합하여
// 다음 state로 넘어갈 최종 cplt flag를 만드는 모듈
module sw_ctrl_gate(
    input   wire    [4:0]   sw_drink, sw_sugar, sw_ice,
    input   wire            i_cplt_drink_sel,
    input   wire            i_cplt_sugar_sel,
    input   wire            i_cplt_ice_sel,
    input   wire            i_cplt_servo,

    output  reg             o_cplt_drink_sel,
    output  reg             o_cplt_sugar_sel,
    output  reg             o_cplt_ice_sel,
    output  reg             o_cplt_servo
    );

    localparam  IDLE = 2'd0,
                OFF  = 2'd1,
                ON   = 2'd2;

    wire    [1:0]   drink, sugar, ice;

    assign  drink = (sw_drink == 5'b00000)? OFF:
                    (sw_drink == 5'b00001) ||
                    (sw_drink == 5'b00010) ||
                    (sw_drink == 5'b00100) ||
                    (sw_drink == 5'b01000) ||
                    (sw_drink == 5'b10000) ? ON : IDLE;

    assign  sugar = (sw_sugar == 5'b00000)? OFF:
                    (sw_sugar == 5'b00001) ||
                    (sw_sugar == 5'b00010) ||
                    (sw_sugar == 5'b00100) ||
                    (sw_sugar == 5'b01000) ||
                    (sw_sugar == 5'b10000) ? ON : IDLE;

    assign  ice =   (sw_ice == 5'b00000)? OFF:
                    (sw_ice == 5'b00001) ||
                    (sw_ice == 5'b00010) ||
                    (sw_ice == 5'b00100) ||
                    (sw_ice == 5'b01000) ||
                    (sw_ice == 5'b10000) ? ON : IDLE;

    always@(*) begin
        case({i_cplt_drink_sel,i_cplt_sugar_sel,i_cplt_ice_sel,i_cplt_servo,drink,sugar,ice})
            {4'b1000,ON,OFF,OFF}    : {o_cplt_drink_sel,o_cplt_sugar_sel,o_cplt_ice_sel,o_cplt_servo} = 4'b1000;
            {4'b0100,ON,ON,OFF}     : {o_cplt_drink_sel,o_cplt_sugar_sel,o_cplt_ice_sel,o_cplt_servo} = 4'b0100;
            {4'b0010,ON,ON,ON}      : {o_cplt_drink_sel,o_cplt_sugar_sel,o_cplt_ice_sel,o_cplt_servo} = 4'b0010;
            {4'b0001,OFF,OFF,OFF}   : {o_cplt_drink_sel,o_cplt_sugar_sel,o_cplt_ice_sel,o_cplt_servo} = 4'b0001;
            default                 : {o_cplt_drink_sel,o_cplt_sugar_sel,o_cplt_ice_sel,o_cplt_servo} = 4'b0000;
        endcase
    end

endmodule

// drink_sel에서 고른 음료에 대한 정보를
// AXI master interface로 보냄
// 항상 모든 state에서 활성화를 
module drink_selector_mux(
    input   wire    [4:0]   i_drink_out,
    output  reg     [31:0]  o_order_info
    );

    always@(*) begin
		case(i_drink_out)
			5'b10000    :   o_order_info = 32'h0000_4000; // apple
			5'b01000    :   o_order_info = 32'h0000_2000; // orange
			5'b00100    :   o_order_info = 32'h0000_1000; // mango
			5'b00010    :   o_order_info = 32'h0000_0800; // grape
			5'b00001    :   o_order_info = 32'h0000_0400; // pineapple
			default     :   o_order_info = 32'h0000_0000;
		endcase
	end

endmodule

// slave에서 보낸 master에서 요구한 결제 상태에 대한 정보를 바탕으로
// ACCOUNT에서 각 state로 넘어갈 flag를 만드는 mux 
// ACCOUNT 단계에서만 활성화
module account_flag_mux(
	input	wire			i_state_en,	// state 활성화 flag 입력
    input   wire    [31:0]  i_statue_out, // data from AXI master interface

    output  reg             o_pay_success,
    output  reg             o_pay_nomoney,
    output  reg             o_pay_soldout    
);

    always@(*) begin
		if(i_state_en) begin
			case(i_statue_out)
				32'h0000_0001   :   {o_pay_success,o_pay_nomoney,o_pay_soldout} = 3'b100;
				32'h0000_0002   :   {o_pay_success,o_pay_nomoney,o_pay_soldout} = 3'b010;
				32'h0000_0003   :   {o_pay_success,o_pay_nomoney,o_pay_soldout} = 3'b001;
				default         :   {o_pay_success,o_pay_nomoney,o_pay_soldout} = 3'b000;
			endcase
		end
		else
			{o_pay_success,o_pay_nomoney,o_pay_soldout} = 3'b000;
    end
endmodule

// axi4 master interfaca에서 fsm으로 보내는 재고 정보
// o_all_soldout은 CHANGE 단계에서만 활성화
// 나머지는 led_out_gate랑 연결되므로 
// state 별 활성화 X
module masterinf2fsm_inventory(
	input	wire			i_state_en,	// state 활성화 flag 입력
    input   wire    [31:0]  i_inventory_out,

    output  wire            o_inv_apple,     // 사과 재고 확인 , led_gate의 apple_inv와 연결
    output  wire            o_inv_orange,    // 오렌지 재고 확인, led_gate의 orange_inv와 연결
    output  wire            o_inv_mango,     // 망고 재고 확인, led_gate의 mabgo_inv와 연결
    output  wire            o_inv_grape,     // 포도 재고 확인, led_gate의 grape_inv와 연결
    output  wire            o_inv_pine,      // 파인애플 재고 확인, led_gate의 pine_inv와 연결
    output  wire            o_all_soldout    // connect to i_all_soldout flag
    );

    assign {o_inv_apple,o_inv_orange,o_inv_mango,o_inv_grape,o_inv_pine} = i_inventory_out[14:10];
	assign o_all_soldout = i_state_en? i_inventory_out[31]: 1'b0;

endmodule

module top_master_fsm(
    input   wire            clk,
    input   wire            arst,       		// Asynchronous Reset (Active High)
    input   wire            change,   			// 잔돈 반환 레버 버튼
    input   wire            ent,      			// 선택 및 승인(Enter) 버튼
	input	wire	[4:0]	i_drink_sel,		// 음료수 스위치 5비트
	input	wire	[4:0]	i_sugar_sel,		// 당도 스위치 5비트
	input	wire	[4:0]	i_ice_sel,			// 얼음 스위치 5비트
    //
	input	wire	[31:0]	i_inventory_out,	// master_inf로 부터 받는 음료별 재고 현황
	input	wire	[31:0]	i_statue_out,		// master_inf로 부터 받는 계산 결과
	input   wire            i_dispense_cplt,    // 음료 제조 및 LED 애니메이션 완료, 팀원 C가 생성
    input   wire            i_servo_cplt,       // 서보모터 구동 및 원위치 완료, 팀원 C가 생성
    input   wire            i_change_cplt,      // 잔돈 물리 반환 완료, 팀원 C가 생성
	//
	output	wire	[14:0]	led,
	output	wire	[31:0]	o_order_info,		// master_inf로 넘갸주는 음료 선택 결과
	output  wire            o_insert_en,        // 동전 투입 단계 활성화, 팀원 B한테 넘겨줘야 함
	output  wire            o_account_en,       // 결제 승인 대기 단계 활성화, 팀원 B한테 넘겨줘야 함 
	output  wire            o_soldout_en,   	// 선택 음료 품절 경고창 표시, 팀원 B한테 넘겨줘야 함
    output  wire            o_nomoney_en,   	// 잔액 부족 경고창 표시, 팀원 B한테 넘겨줘야 함
    output  wire            o_re_insert_en,     // 금액 추가 투입 유도 표시, 팀원 B한테 넘겨줘야 함
    output  wire            o_done_en,    		// 음료 제조/애니메이션 가동, 팀원 B/팀원 D한테 넘겨줘야 함
    output  wire            o_servo_en,         // 서보모터 배출 가동, 팀원 D한테 넘겨줘야 함
    output  wire            o_change_en, 		// 잔돈 반환기 가동, 팀원 B/팀원 D한테 넘겨줘야 함
    output  wire            o_close_en   		// 영업 종료(CLOSE) 안내 표시, 팀원 B한테 넘겨줘야 함
    );
	
	// cplt flag
	// servo_cplt는 외부에서 받아와서 내부에서 SW gating 작업이 팡요
	wire			drink_sel_cplt, sugar_sel_cplt, ice_sel_cplt, pay_success, pay_nomoney, pay_soldout, servo_cplt, all_soldout;
	
	// selctor cplt flag
	wire			drink_sel_done, sugar_sel_done, ice_sel_done;
	
	// state en flag
	wire			drink_sel_en, sugar_sel_en, ice_sel_en;
	
	// drink/sugar/ice 별 출력결과
	wire	[4:0]	drink_out, sugar_out, ice_out;
	
	// 음료 품목별 재고
	wire			apple_inv, orange_inv, mango_inv, grape_inv, pine_inv;
	
	// led가 켜져있는 STATE
	wire			led_state;
	
	assign led_state =	o_insert_en		||
						drink_sel_en	||
						sugar_sel_en	||
						ice_sel_en		||
						o_account_en	||
						o_soldout_en	||
						o_nomoney_en	||
						o_re_insert_en;

 master_fsm              U_MASTER_FSM(
        .i_clk              (clk),
        .i_arst             (arst),
        .i_btn_change       (change),
        .i_btn_ent          (ent),
        .i_drink_sel_cplt   (drink_sel_cplt),
        .i_sugar_sel_cplt   (sugar_sel_cplt),
        .i_ice_sel_cplt     (ice_sel_cplt),
        .i_pay_success      (pay_success),
        .i_pay_nomoney      (pay_nomoney),
        .i_pay_soldout      (pay_soldout),
        .i_dispense_cplt    (i_dispense_cplt),	// 외부에서 받는 cplt flag
        .i_servo_cplt       (servo_cplt),		
        .i_change_cplt      (i_change_cplt),	// 외부에서 받는 cplt flag
        .i_all_soldout      (all_soldout),
        .o_insert_en        (o_insert_en),		// 외부로 넘겨주는 state en flag
        .o_drink_sel_en     (drink_sel_en),
        .o_sugar_sel_en     (sugar_sel_en),
        .o_ice_sel_en       (ice_sel_en),
        .o_account_en       (o_account_en),		// 외부로 넘겨주는 state en flag
        .o_soldout_en       (o_soldout_en),		// 외부로 넘겨주는 state en flag
        .o_nomoney_en       (o_nomoney_en),		// 외부로 넘겨주는 state en flag
        .o_re_insert_en     (o_re_insert_en),	// 외부로 넘겨주는 state en flag
        .o_done_en          (o_done_en),		// 외부로 넘겨주는 state en flag
        .o_servo_en         (o_servo_en),		// 외부로 넘겨주는 state en flag
        .o_change_en        (o_change_en),		// 외부로 넘겨주는 state en flag
        .o_close_en         (o_close_en)		// 외부로 넘겨주는 state en flag
    );

    drink_selector          U_DRINK_SELECTOR(
        .clk                (clk),
        .arst               (arst),
        .drink_sel          (i_drink_sel),
        .flag_state         (drink_sel_en),
        .flag_rst           (pay_success),
        .flag_cplt          (drink_sel_done),
        .drink_out          (drink_out)
    );

    sugar_selector          U_SUGAR_SELECTOR(
        .clk                (clk),
        .arst               (arst),
        .sugar_sel          (i_sugar_sel),
        .flag_state         (sugar_sel_en),
        .flag_rst           (pay_success),
        .flag_cplt          (sugar_sel_done),
        .led_sugar          (sugar_out)
    );

    ice_selector            U_ICE_SELECTOR(
        .clk                (clk),
        .arst               (arst),
        .ice_sel            (i_ice_sel),
        .flag_state         (ice_sel_en),
        .flag_rst           (pay_success),
        .flag_cplt          (ice_sel_done),
        .led_ice            (ice_out)
    );

    led_out_gate            U_LED_OUT_GATE(
        .i_state_en         (led_state),
        .apple_inv          (apple_inv),
        .orange_inv         (orange_inv),
        .mango_inv          (mango_inv),
        .grape_inv          (grape_inv),
        .pine_inv           (pine_inv),
        .led_sugar          (sugar_out),
        .led_ice            (ice_out),
        .led                (led)
    );

    sw_ctrl_gate            U_SW_CTRL_GATE(
        .sw_drink           (i_drink_sel),
        .sw_sugar           (i_sugar_sel),
        .sw_ice             (i_ice_sel),
        .i_cplt_drink_sel   (drink_sel_done),
        .i_cplt_sugar_sel   (sugar_sel_done),
        .i_cplt_ice_sel     (ice_sel_done),
        .i_cplt_servo       (i_servo_cplt),
        .o_cplt_drink_sel   (drink_sel_cplt),
        .o_cplt_sugar_sel   (sugar_sel_cplt),
        .o_cplt_ice_sel     (ice_sel_cplt),
        .o_cplt_servo       (servo_cplt)
    );

    drink_selector_mux      U_DRINK_SELECTOR_MUX(
        .i_drink_out        (drink_out),
        .o_order_info       (o_order_info)
    );

    account_flag_mux        U_ACCOUNT_FLAG_MUX(
        .i_state_en         (o_account_en),
        .i_statue_out       (i_statue_out),
        .o_pay_success      (pay_success),
        .o_pay_nomoney      (pay_nomoney),
        .o_pay_soldout      (pay_soldout)
    );

    masterinf2fsm_inventory	U_MATERINF2FSM_INVENTRY(
        .i_state_en         (o_change_en),
        .i_inventory_out    (i_inventory_out),
        .o_inv_apple        (apple_inv),
        .o_inv_orange       (orange_inv),
        .o_inv_mango        (mango_inv),
        .o_inv_grape        (grape_inv),
        .o_inv_pine         (pine_inv),
        .o_all_soldout      (all_soldout)
    );

endmodule

/*
// 최종 써야하는 모듈을 인스턴스화 시킨거니깐
// 인스턴스 이름은 원하는대로 짓고 바로 갔다 써
top_master_fsm          U_TOP_MASTER_FSM (
		// input port
        .clk                (),
        .arst               (), // Asynchronous Reset (Active High)
        .change             (), // 잔돈 반환 레버 버튼
        .ent                (), // 선택 및 승인(Enter) 버튼
        .i_drink_sel        (), // 음료수 스위치 5비트
        .i_sugar_sel        (), // 당도 스위치 5비트
        .i_ice_sel          (), // 얼음 스위치 5비트
        .i_inventory_out    (), // master_inf로 부터 받는 음료별 재고 현황
        .i_statue_out       (), // master_inf로 부터 받는 계산 결과
        .i_dispense_cplt    (), // 음료 제조 및 LED 애니메이션 완료, 팀원 D가 생성
        .i_servo_cplt       (), // 서보모터 구동 및 원위치 완료, 팀원 D가 생성
        .i_change_cplt      (), // 잔돈 물리 반환 완료, 팀원 D가 생성
		// output port
        .led                (),
        .o_order_info       (), // master_inf로 넘갸주는 음료 선택 결과
        .o_insert_en        (), // 동전 투입 단계 활성화, 팀원 B한테 넘겨줘야 함
				.o_account_en		(),	// 계산하는 단계 활성화, 팀원 B한테 넘겨줘야 함
        .o_soldout_en       (), // 선택 음료 품절 경고창 표시, 팀원 B한테 넘겨줘야 함
        .o_nomoney_en       (), // 잔액 부족 경고창 표시, 팀원 B한테 넘겨줘야 함
        .o_re_insert_en     (), // 금액 추가 투입 유도 표시, 팀원 B한테 넘겨줘야 함
        .o_done_en          (), // 음료 제조/애니메이션 가동, 팀원 B/팀원 D한테 넘겨줘야 함
        .o_servo_en         (), // 서보모터 배출 가동, 팀원 D한테 넘겨줘야 함
        .o_change_en        (), // 잔돈 반환기 가동, 팀원 B/팀원 D한테 넘겨줘야 함
        .o_close_en         ()  // 영업 종료(CLOSE) 안내 표시, 팀원 D한테 넘겨줘야 함
    );
*/