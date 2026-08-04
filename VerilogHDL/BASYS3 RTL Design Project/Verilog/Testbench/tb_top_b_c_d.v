`timescale 1ns / 1ps

// ============================================================
//  tb_top_b_c_d.v (대망의 최종 통합 테스트벤치)
//  검증 대상: top_b_c_d_wrapper 
//  역할: Team A (Main FSM)가 되어 자판기의 모든 시나리오 지휘
// ============================================================

`define CHECK(label, got, exp) \
    if ((got) !== (exp)) begin \
        $display("  [FAIL] %s | got=%0d exp=%0d (t=%0t ns)", label, got, exp, $time); \
        fail_count = fail_count + 1; \
    end else \
        $display("  [PASS] %s | value=%0d", label, got);

`define CHECK_HEX(label, got, exp) \
    if ((got) !== (exp)) begin \
        $display("  [FAIL] %s | got=0x%08X exp=0x%08X (t=%0t ns)", label, got, exp, $time); \
        fail_count = fail_count + 1; \
    end else \
        $display("  [PASS] %s | value=0x%08X", label, got);

`define CHECK_BIT(label, vec, bit_pos, exp) \
    if (((((vec) >> (bit_pos)) & 1'b1) !== (exp))) begin \
        $display("  [FAIL] %s | bit[%0d] got=%0d exp=%0d (t=%0t ns)", \
                 label, bit_pos, (((vec) >> (bit_pos)) & 1'b1), exp, $time); \
        fail_count = fail_count + 1; \
    end else begin \
        $display("  [PASS] %s | bit[%0d]=%0d", \
                 label, bit_pos, (((vec) >> (bit_pos)) & 1'b1)); \
    end

module tb_top_b_c_d;

    // ── 1. 시스템 신호 ──────────────────────────────
    reg clk;
    reg reset_n;

    // ── 2. 물리적 버튼 입력 ─────────────────────────
    reg btn_100_in, btn_500_in, btn_1000_in;
    
    // ── 3. FSM ↔ 하드웨어 출력 ─────────────────────────
    wire [6:0] seg;
    wire [3:0] an;
    wire [15:0] o_led;
    wire o_servo_pwm;

    // ── 4. Team A (FSM) 소켓 핀들 ──────────────────────
    reg [3:0] fsm_state;
    reg       update_en;

    reg        req_write, req_read;
    reg [31:0] order_info;
    
    wire        done_write, done_read;
    wire [31:0] status_out, inventory_out;

    reg  flag_SERVO, flag_CHANGE, flag_DONE;
    wire flag_cplt_SERVO, flag_cplt_CHANGE, flag_cplt_DONE;

    integer fail_count;

    // ── DUT 인스턴스 ─────────────────────────────────
    top_b_c_d_wrapper uut (
        .clk(clk), .reset_n(reset_n),
        .btn_100_in(btn_100_in), .btn_500_in(btn_500_in), .btn_1000_in(btn_1000_in),
        .seg(seg), .an(an), .o_led(o_led), .o_servo_pwm(o_servo_pwm),
        .fsm_state(fsm_state), .update_en(update_en),
        .req_write(req_write), .req_read(req_read), .order_info(order_info),
        .done_write(done_write), .done_read(done_read),
        .status_out(status_out), .inventory_out(inventory_out),
        .flag_SERVO(flag_SERVO), .flag_CHANGE(flag_CHANGE), .flag_DONE(flag_DONE),
        .flag_cplt_SERVO(flag_cplt_SERVO), .flag_cplt_CHANGE(flag_cplt_CHANGE), .flag_cplt_DONE(flag_cplt_DONE)
    );

    // ── 클럭 생성 (100MHz) ───────────────────────────
    initial clk = 0;
    always #5 clk = ~clk;

    // =========================================================
    // 태스크 1: 공통 reset sequence
    // =========================================================
    task apply_reset;
        begin
            reset_n <= 0;
            btn_100_in <= 0;
            btn_500_in <= 0;
            btn_1000_in <= 0;
            fsm_state <= 4'd0;
            update_en <= 0;
            req_write <= 0;
            req_read <= 0;
            order_info <= 0;
            flag_SERVO <= 0;
            flag_CHANGE <= 0;
            flag_DONE <= 0;

            repeat(10) @(posedge clk);
            reset_n <= 1;
            repeat(20) @(posedge clk);
        end
    endtask

    // =========================================================
    // 태스크 2: 물리 버튼 누르기 (디바운싱 고려)
    // =========================================================
    task press_btn;
        input integer btn_type; // 100, 500, 1000
        begin
            @(posedge clk);
            if(btn_type == 100)       btn_100_in <= 1;
            else if(btn_type == 500)  btn_500_in <= 1;
            else if(btn_type == 1000) btn_1000_in <= 1;
            
            // 디바운서(DEBOUNCE_TIME=10 기준)를 통과하도록 20클럭 동안 길게 누름
            repeat(20) @(posedge clk);
            
            btn_100_in <= 0; btn_500_in <= 0; btn_1000_in <= 0;
            
            // 버튼에서 손 떼고 잠시 대기
            repeat(20) @(posedge clk); 
        end
    endtask

    task press_btn_long;
        input integer btn_type;
        input integer hold_cycles;
        begin
            @(posedge clk);
            if(btn_type == 100)       btn_100_in <= 1;
            else if(btn_type == 500)  btn_500_in <= 1;
            else if(btn_type == 1000) btn_1000_in <= 1;

            repeat(hold_cycles) @(posedge clk);

            btn_100_in <= 0;
            btn_500_in <= 0;
            btn_1000_in <= 0;

            repeat(30) @(posedge clk);
        end
    endtask

    // =========================================================
    // 태스크 3: 완료 신호 timeout 대기
    // =========================================================
    task wait_done_write_timeout;
        integer i;
        begin
            i = 0;
            while (!done_write && i < 1000) begin
                @(posedge clk);
                i = i + 1;
            end

            if (!done_write) begin
                $display("  [FAIL] done_write TIMEOUT (t=%0t ns)", $time);
                fail_count = fail_count + 1;
            end else begin
                $display("  [PASS] done_write asserted");
            end
        end
    endtask

    task wait_done_read_timeout;
        integer i;
        begin
            i = 0;
            while (!done_read && i < 1000) begin
                @(posedge clk);
                i = i + 1;
            end

            if (!done_read) begin
                $display("  [FAIL] done_read TIMEOUT (t=%0t ns)", $time);
                fail_count = fail_count + 1;
            end else begin
                $display("  [PASS] done_read asserted");
            end
        end
    endtask

    task wait_led_done_timeout;
        integer i;
        begin
            i = 0;
            while (!flag_cplt_DONE && i < 5000) begin
                @(posedge clk);
                i = i + 1;
            end

            if (!flag_cplt_DONE) begin
                $display("  [FAIL] flag_cplt_DONE TIMEOUT (t=%0t ns)", $time);
                fail_count = fail_count + 1;
            end else begin
                $display("  [PASS] flag_cplt_DONE asserted");
                `CHECK_HEX("LED 완료 시 o_led=0xFFFF", o_led, 16'hFFFF)
            end
        end
    endtask

    task wait_servo_open_timeout;
        integer i;
        begin
            i = 0;
            while (!flag_cplt_SERVO && i < 5000) begin
                @(posedge clk);
                i = i + 1;
            end

            if (!flag_cplt_SERVO) begin
                $display("  [FAIL] flag_cplt_SERVO TIMEOUT (t=%0t ns)", $time);
                fail_count = fail_count + 1;
            end else begin
                $display("  [PASS] flag_cplt_SERVO asserted");
            end
        end
    endtask

    task wait_servo_close_timeout;
        integer i;
        begin
            i = 0;
            while (!flag_cplt_CHANGE && i < 5000) begin
                @(posedge clk);
                i = i + 1;
            end

            if (!flag_cplt_CHANGE) begin
                $display("  [FAIL] flag_cplt_CHANGE TIMEOUT (t=%0t ns)", $time);
                fail_count = fail_count + 1;
            end else begin
                $display("  [PASS] flag_cplt_CHANGE asserted");
            end
        end
    endtask

    // =========================================================
    // 태스크 4: 내부 금액 및 실패 시 D팀 미구동 검사
    // =========================================================
    task check_money;
        input [15:0] expected_money;
        begin
            #1;
            if (uut.w_current_money !== expected_money) begin
                $display("  [FAIL] current_money | got=%0d exp=%0d (t=%0t ns)",
                         uut.w_current_money, expected_money, $time);
                fail_count = fail_count + 1;
            end else begin
                $display("  [PASS] current_money=%0d", expected_money);
            end
        end
    endtask

    task guard_no_d_activity;
        input integer observe_cycles;
        integer i;
        reg seen_led_done;
        reg seen_servo_open;
        reg seen_servo_close;
        begin
            seen_led_done    = 0;
            seen_servo_open  = 0;
            seen_servo_close = 0;

            for (i = 0; i < observe_cycles; i = i + 1) begin
                @(posedge clk);
                if (flag_cplt_DONE)   seen_led_done    = 1;
                if (flag_cplt_SERVO)  seen_servo_open  = 1;
                if (flag_cplt_CHANGE) seen_servo_close = 1;
            end

            if (seen_led_done || seen_servo_open || seen_servo_close) begin
                $display("  [FAIL] D module unexpectedly activated during failure status");
                fail_count = fail_count + 1;
            end else begin
                $display("  [PASS] D module remained idle during failure status");
            end
        end
    endtask

    task check_change_completes_when_closed;
        input integer observe_cycles;
        integer i;
        integer change_done_count;
        begin
            change_done_count = 0;

            @(posedge clk);
            flag_CHANGE <= 1'b1;

            // 입력을 여러 클럭 유지해도 완료는 한 번만 발생해야 한다.
            repeat(10) begin
                @(posedge clk);
                if (flag_cplt_CHANGE)
                    change_done_count = change_done_count + 1;
            end

            flag_CHANGE <= 1'b0;

            for (i = 0; i < observe_cycles; i = i + 1) begin
                @(posedge clk);
                if (flag_cplt_CHANGE)
                    change_done_count = change_done_count + 1;
            end

            if (change_done_count != 1) begin
                $display("  [FAIL] closed CHANGE completion count | got=%0d exp=1",
                         change_done_count);
                fail_count = fail_count + 1;
            end else begin
                $display("  [PASS] closed CHANGE completed exactly once");
            end

            `CHECK("closed CHANGE keeps servo_opened=0",
                   uut.u_servo.servo_opened, 1'b0)
            `CHECK("closed CHANGE returns state IDLE",
                   uut.u_servo.state, 3'd0)
            `CHECK("closed CHANGE keeps CLOSE_PULSE",
                   uut.u_servo.pulse_width, uut.u_servo.CLOSE_PULSE)
        end
    endtask

    // =========================================================
    // 태스크 5: AXI Master에게 결제 및 수거 지시 (3연타 콤보 자동화!)
    // =========================================================
    task do_payment_and_read;
        input [31:0] order_cmd; // 음료 코드
        begin
            order_info <= order_cmd;
            
            // 1. 마스터야 결제해!
            @(posedge clk); req_write <= 1; @(posedge clk); req_write <= 0;
            wait_done_write_timeout;
            
            // 2. 마스터야 결과 읽어와!
            @(posedge clk); req_read <= 1; @(posedge clk); req_read <= 0;
            wait_done_read_timeout;

            @(posedge clk);
            #1;
        end
    endtask

    // =========================================================
    // 메인 시나리오
    // =========================================================
    initial begin
        fail_count = 0;

        apply_reset;

        $display("\n========================================================");
        $display(" 🚀 Team A, B, C, D 풀-통합 시스템 검증 시작! 🚀");
        $display("========================================================\n");

        // ────────────────────────────────────────────────────
        // Phase 0: Reset 직후 초기 상태 검증
        // ────────────────────────────────────────────────────
        $display("===== Phase 0: Reset 초기 상태 검증 =====");
        check_money(16'd0);
        `CHECK_HEX("Reset 후 o_led=0x0000", o_led, 16'h0000)
        `CHECK("Reset 후 flag_cplt_DONE=0", flag_cplt_DONE, 1'b0)
        `CHECK("Reset 후 flag_cplt_SERVO=0", flag_cplt_SERVO, 1'b0)
        `CHECK("Reset 후 flag_cplt_CHANGE=0", flag_cplt_CHANGE, 1'b0)
        `CHECK("Reset 후 done_write=0", done_write, 1'b0)
        `CHECK("Reset 후 done_read=0", done_read, 1'b0)
        `CHECK("Reset 후 servo_opened=0", uut.u_servo.servo_opened, 1'b0)

        // ────────────────────────────────────────────────────
        // Phase 0B: 버튼을 길게 눌러도 1회만 카운트되는지 검증
        // ────────────────────────────────────────────────────
        $display("\n===== Phase 0B: 버튼 길게 누름 1회 카운트 검증 =====");
        check_money(16'd0);
        press_btn_long(1000, 100);
        check_money(16'd1000);

        // Phase 1을 깨끗한 초기 상태에서 시작하기 위해 reset 재적용
        apply_reset;
        check_money(16'd0);

        // ────────────────────────────────────────────────────
        // Phase 0C: 닫힌 서보에 대한 CHANGE 즉시 완료 검증
        // ────────────────────────────────────────────────────
        $display("\n===== Phase 0C: Servo 닫힘 상태 CHANGE 즉시 완료 검증 =====");
        check_change_completes_when_closed(100);
        `CHECK("servo_opened remains 0", uut.u_servo.servo_opened, 1'b0)

        // ────────────────────────────────────────────────────
        // Phase 1: 현금 투입 및 해피 패스 (1500원 투입 -> 사과 1200원 구매)
        // ────────────────────────────────────────────────────
        $display("===== Phase 1: 버튼 투입 및 정상 결제 시나리오 =====");
        press_btn(1000); // 1000원 찰칵
        check_money(16'd1000);
        press_btn(500);  // 500원 찰칵
        check_money(16'd1500);
        $display("  -> 버튼 입력 완료 (1500원 장전)");
        
        do_payment_and_read(32'h00004000); // 사과주스 결제 지시
        `CHECK("Phase 1 STATUS (SUCCESS=1)", status_out, 32'd1)
        `CHECK_BIT("Phase 1 사과 재고 아직 있음 inventory[14]=1", inventory_out, 14, 1'b1)

        if(status_out == 32'd1) begin
            fsm_state <= 4'd5; // 'donE' 문자 출력 상태

            // LED 제조 -> 서보 열림 -> 서보 닫힘 콤보
            @(posedge clk); flag_DONE <= 1; @(posedge clk); flag_DONE <= 0;
            wait_led_done_timeout;
            
            @(posedge clk); flag_SERVO <= 1; @(posedge clk); flag_SERVO <= 0;
            wait_servo_open_timeout;

            @(posedge clk); flag_CHANGE <= 1; @(posedge clk); flag_CHANGE <= 0;
            wait_servo_close_timeout;

            // ⭐️ 핵심: 결제 끝났으니 잔돈(300원)을 내 지갑에 덮어써라!
            @(posedge clk); update_en <= 1; 
            @(posedge clk); update_en <= 0;
            repeat(2) @(posedge clk);
            check_money(16'd300);
            fsm_state <= 4'd0; // 다시 INSERT 상태로 복귀
        end
        repeat(100) @(posedge clk);

        // ────────────────────────────────────────────────────
        // Phase 2: 잔액 부족 방어 (남은 300원으로 1900원 포도 구매 시도)
        // ────────────────────────────────────────────────────
        $display("\n===== Phase 2: 연속 구매 & 잔액 부족 (LESS) 방어 =====");
        do_payment_and_read(32'h00000800); // 포도주스 결제 지시
        `CHECK("Phase 2 STATUS (NO_MONEY=2)", status_out, 32'd2)
        guard_no_d_activity(100);
        check_money(16'd300);

        if(status_out == 32'd2) begin
            fsm_state <= 4'd4; // 'LESS' 문자 출력 상태로 변경
            $display("  -> 돈이 모자랍니다! (FND에 LESS 출력 중, 하드웨어 미구동)");
            repeat(50) @(posedge clk);
            fsm_state <= 4'd0;
        end
        repeat(100) @(posedge clk);

        // ────────────────────────────────────────────────────
        // Phase 3: 재고 고갈 방어 (사과 1개 남은 거 다 뽑기)
        // ────────────────────────────────────────────────────
        $display("\n===== Phase 3: 품절 (nonE) 방어 시나리오 =====");
        press_btn(1000); press_btn(1000); press_btn(1000); // 3000원 추가 충전 (지갑: 3300원)
        check_money(16'd3300);
        
        // 사과(현재 재고 1개 남음) 구매 시도 -> 성공해야 함
        do_payment_and_read(32'h00004000);
        `CHECK("사과 마지막 1개 구매 성공 (STATUS=1)", status_out, 32'd1)
        `CHECK_BIT("사과 구매 후 inventory[14]=0", inventory_out, 14, 1'b0)
        @(posedge clk); update_en <= 1; @(posedge clk); update_en <= 0; // 잔돈 갱신
        repeat(2) @(posedge clk);
        check_money(16'd2100);
        
        // 사과 또 구매 시도 -> 품절 컷 당해야 함
        do_payment_and_read(32'h00004000);
        `CHECK("사과 품절 거절 (STATUS=3)", status_out, 32'd3)
        guard_no_d_activity(100);
        check_money(16'd2100);
        
        if(status_out == 32'd3) begin
            fsm_state <= 4'd6; // 'nonE' 문자 출력 상태로 변경
            $display("  -> 품절입니다! (FND에 nonE 출력 중, 하드웨어 미구동)");
            repeat(50) @(posedge clk);
        end
        repeat(100) @(posedge clk);

        // ────────────────────────────────────────────────────
        // Phase 3B: 잘못된 주문 정보 방어 검증
        // ────────────────────────────────────────────────────
        $display("\n===== Phase 3B: Invalid Order 방어 검증 =====");

        do_payment_and_read(32'h00000000);
        `CHECK("선택 없음 invalid order STATUS (=2)", status_out, 32'd2)
        guard_no_d_activity(100);
        check_money(16'd2100);

        do_payment_and_read(32'h00006000);
        `CHECK("다중 선택 invalid order STATUS (=2)", status_out, 32'd2)
        guard_no_d_activity(100);
        check_money(16'd2100);

        // ────────────────────────────────────────────────────
        // Phase 4: 잔돈 반환 시나리오 (거스름돈 레버 돌림)
        // ────────────────────────────────────────────────────
        $display("\n===== Phase 4: 잔돈 반환 (CHANGE) 시나리오 =====");
        $display("  -> 사용자가 거스름돈 반환 레버를 돌렸습니다!");
        fsm_state <= 4'd10; // CHANGE 상태 (돈통 모듈이 알아서 돈을 0으로 비움)
        repeat(5) @(posedge clk);
        check_money(16'd0);
        
        fsm_state <= 4'd0; // 다시 대기 상태로
        repeat(100) @(posedge clk);

        // ── 최종 리포트 ─────────────────────────────────────
        $display("\n╔══════════════════════════════════════════════╗");
        if (fail_count == 0)
            $display("║  ALL SYSTEMS GREEN! (모든 시나리오 통과!)    ║");
        else
            $display("║  FAIL: %0d 개 케이스 실패                 ║", fail_count);
        $display("╚══════════════════════════════════════════════╝\n");

        $finish;
    end
endmodule
