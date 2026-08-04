`timescale 1ns / 1ps

module slave_inventory (
    input  wire        clk,
    input  wire        arst,       // Active-High 리셋 (SW[15] 연결)

    // ── 입력: AXI Slave Wrapper로부터 받는 신호 (Master가 쓴 값) ──
    input  wire        i_ctrl_trigger, // REG_CTRL  (주소 0x00) : SELECT 상태에서 ENTER 눌릴 때 1클럭 펄스
    input  wire [31:0] i_order_info,   // REG_ORDER (주소 0x04) : SW[14:0] 전체 스위치 상태
    input  wire [31:0] i_money_in,     // REG_MONEY (주소 0x08) : 누적 투입 금액

    // ── 출력: AXI Slave Wrapper로 내보내는 신호 (Master가 읽어갈 값) ──
    output reg  [31:0] o_status,       // REG_STATUS (주소 0x0C)
                                       //   0 = IDLE   (대기 / 리셋 직후)
                                       //   1 = SUCCESS (결제 성공)
                                       //   2 = NO_MONEY(투입 금액 부족)
                                       //   3 = SOLD_OUT(재고 없음)
    output wire [31:0] o_inventory,    // REG_INVEN  (주소 0x10) : 비트[14:10] = 주스 재고 ON/OFF
    output reg  [31:0] o_change        // REG_CHANGE (주소 0x14) : 잔돈 반환금
);

   
    reg [13:0] db_price [0:4];   // [0]=사과, [1]=오렌지, [2]=망고, [3]=포도, [4]=파인애플
    reg  [3:0] db_stock [0:4];

    // ----------------------------------------------------------------
    // 트리거 엣지 감지용 이전 값 레지스터
    //    i_ctrl_trigger 가 0→1 되는 순간(상승 엣지)에만 1클럭 동안 HIGH
    // ----------------------------------------------------------------
    reg        i_ctrl_trigger_prev;
    wire       trigger_pulse;
    assign trigger_pulse = i_ctrl_trigger & ~i_ctrl_trigger_prev;

    // ----------------------------------------------------------------
    //    주문 정보 해독기 (Combinational)
    //    i_order_info[14:10] ← D_SELECT (SW[14:10], 주스 5종)
    //    딱 1비트만 HIGH여야 유효 (나머지 비트 조합은 모두 invalid)
    // ----------------------------------------------------------------
    reg [13:0] target_price;
    reg  [3:0] target_stock;
    reg  [2:0] target_idx;     // 배열 인덱스 (0~4)
    reg        is_valid_order;

    always @(*) begin
        is_valid_order = 1'b1;
        case (i_order_info[14:10])
            //          SW비트     인덱스  주스명
            5'b10000: begin target_idx = 3'd0; target_price = db_price[0]; target_stock = db_stock[0]; end // SW14: 사과
            5'b01000: begin target_idx = 3'd1; target_price = db_price[1]; target_stock = db_stock[1]; end // SW13: 오렌지
            5'b00100: begin target_idx = 3'd2; target_price = db_price[2]; target_stock = db_stock[2]; end // SW12: 망고
            5'b00010: begin target_idx = 3'd3; target_price = db_price[3]; target_stock = db_stock[3]; end // SW11: 포도
            5'b00001: begin target_idx = 3'd4; target_price = db_price[4]; target_stock = db_stock[4]; end // SW10: 파인애플
            default:  begin target_idx = 3'd0; target_price = 14'd0;       target_stock = 4'd0;        is_valid_order = 1'b0; end
            //  ↑ 0개, 2개 이상, SW15만 올린 경우 모두 invalid로 처리
        endcase
    end

    // ----------------------------------------------------------------
    // 4. 결제·재고 차감 로직 (Sequential)
    //    trigger_pulse(상승 엣지 1클럭)에서만 평가 → 연속 차감 버그 제거
    // ----------------------------------------------------------------
    always @(posedge clk or posedge arst) begin
        if (arst) begin
            // ── DB 초기화 (SW[15]↑ 또는 외부 리셋) ──────────────────
            db_price[0] <= 14'd1200; db_stock[0] <= 4'd1; // 사과주스
            db_price[1] <= 14'd1500; db_stock[1] <= 4'd0; // 오렌지주스
            db_price[2] <= 14'd1700; db_stock[2] <= 4'd0; // 망고주스
            db_price[3] <= 14'd1900; db_stock[3] <= 4'd0; // 포도주스
            db_price[4] <= 14'd2300; db_stock[4] <= 4'd1; // 파인애플주스

            o_status             <= 32'd0;  // IDLE
            o_change             <= 32'd0;
            i_ctrl_trigger_prev  <= 1'b0;

        end else begin
            // 엣지 감지를 위해 이전 값 항상 갱신
            i_ctrl_trigger_prev <= i_ctrl_trigger;

            if (trigger_pulse) begin
                // ── SELECT 상태에서 ENTER가 눌린 순간 ────────────────
                if (!is_valid_order) begin
                    // 주스 스위치가 0개 또는 2개 이상 → 주문 자체가 무효
                    // (Master FSM 레벨에서 막아야 하지만 Slave도 방어)
                    o_status <= 32'd2;  // NO_MONEY 와 동일 코드 or 별도 정의 가능
                    o_change <= 32'd0;

                end else if (target_stock == 4'd0) begin
                    // ── SOLD_OUT: 재고 없음 ──────────────────────────
                    o_status <= 32'd3;  // SOLD_OUT
                    o_change <= 32'd0;

                end else if (i_money_in >= {18'd0, target_price}) begin
                    // ── SUCCESS: 결제 승인 ───────────────────────────
                    o_status <= 32'd1;  // SUCCESS
                    o_change <= i_money_in - {18'd0, target_price}; // 잔돈
                    db_stock[target_idx] <= db_stock[target_idx] - 4'd1; // 재고 1 차감

                end else begin
                    // ── NO_MONEY: 투입 금액 부족 ────────────────────
                    o_status <= 32'd2;  // NO_MONEY
                    o_change <= 32'd0;
                end

            end
            // trigger_pulse 가 없는 클럭: o_status, o_change, db_stock 모두 Hold
            // (Verilog always 블록의 기본 동작 - 명시적 else 불필요)
        end
    end

 // ----------------------------------------------------------------
    // 5. 실시간 재고 상태 출력 및 전체 품절 플래그
    // ----------------------------------------------------------------
    wire all_sold_out;
    // 모든 재고가 0일 때만 1이 됨
    assign all_sold_out = (db_stock[0] == 0) && (db_stock[1] == 0) && 
                          (db_stock[2] == 0) && (db_stock[3] == 0) && (db_stock[4] == 0);

    assign o_inventory = {
        all_sold_out,    // [31]   ⭐ 추가됨: 1이면 전체 품절 (Master가 이 비트를 보고 CLOSE로 이동)
        15'd0,           // [30:16] 미사용
        1'b0,            // [15]    SW15 = 리셋 전용, LED 없음
        (db_stock[0] > 0),  // [14]  SW14: 사과
        (db_stock[1] > 0),  // [13]  SW13: 오렌지
        (db_stock[2] > 0),  // [12]  SW12: 망고
        (db_stock[3] > 0),  // [11]  SW11: 포도
        (db_stock[4] > 0),  // [10]  SW10: 파인애플
        10'd0            // [9:0]  미사용
    };

endmodule
