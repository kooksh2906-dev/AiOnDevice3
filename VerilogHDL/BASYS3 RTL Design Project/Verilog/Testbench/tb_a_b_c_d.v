`timescale 1ns / 1ps

`define CHECK(label, got, exp) \
    if ((got) !== (exp)) begin \
        $display("  [FAIL] %s | got=%0d exp=%0d (t=%0t ns)", label, got, exp, $time); \
        fail_count = fail_count + 1; \
    end else begin \
        $display("  [PASS] %s | value=%0d", label, got); \
    end

`define CHECK_HEX(label, got, exp) \
    if ((got) !== (exp)) begin \
        $display("  [FAIL] %s | got=0x%08X exp=0x%08X (t=%0t ns)", label, got, exp, $time); \
        fail_count = fail_count + 1; \
    end else begin \
        $display("  [PASS] %s | value=0x%08X", label, got); \
    end

`define CHECK_BIT(label, vec, bit_pos, exp) \
    if (((((vec) >> (bit_pos)) & 1'b1) !== (exp))) begin \
        $display("  [FAIL] %s | bit[%0d] got=%0d exp=%0d (t=%0t ns)", \
                 label, bit_pos, (((vec) >> (bit_pos)) & 1'b1), exp, $time); \
        fail_count = fail_count + 1; \
    end else begin \
        $display("  [PASS] %s | bit[%0d]=%0d", \
                 label, bit_pos, (((vec) >> (bit_pos)) & 1'b1)); \
    end

module tb_a_b_c_d;

    localparam ST_INSERT    = 4'd0;
    localparam ST_DRINK_SEL = 4'd1;
    localparam ST_SUGAR_SEL = 4'd2;
    localparam ST_ICE_SEL   = 4'd3;
    localparam ST_ACCOUNT   = 4'd4;
    localparam ST_SOLD_OUT  = 4'd5;
    localparam ST_NO_MONEY  = 4'd6;
    localparam ST_DONE      = 4'd8;
    localparam ST_SERVO     = 4'd9;
    localparam ST_CHANGE    = 4'd10;

    localparam FSM_TIMEOUT = 2000;
    localparam AXI_TIMEOUT = 2000;
    localparam D_TIMEOUT   = 5000;

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
    wire [4:0] ext_stock_led;
    wire [4:0] ext_sugar_bar;
    wire [4:0] ext_ice_bar;
    wire [3:0] dut_fsm_state;

    integer fail_count;
    integer req_write_count;
    integer req_read_count;
    integer update_count;
    integer done_flag_count;
    integer servo_flag_count;
    integer change_flag_count;
    integer account_entry_count;
    integer done_write_count;
    integer done_read_count;
    integer led_full_count;
    integer change_cplt_count;
    integer servo_close_state_count;
    integer ext_status_mismatch_count;
    integer onboard_animation_diff_count;

    reg [3:0] monitored_state_d;
    reg [31:0] captured_order_info;

    top_a_b_c_d_fnd_debug uut (
        .clk        (clk),
        .arst       (arst),
        .btn_enter  (btn_enter),
        .btn_100    (btn_100),
        .btn_500    (btn_500),
        .btn_1000   (btn_1000),
        .btn_refund (btn_refund),
        .sw         (sw),
        .led        (led),
        .seg        (seg),
        .an         (an),
        .servo_out  (servo_out),
        .ja_dbg     (ja_dbg),
        .ext_stock_led(ext_stock_led),
        .ext_sugar_bar(ext_sugar_bar),
        .ext_ice_bar(ext_ice_bar)
    );

    // Keep the production timing parameters intact in RTL while making the
    // full-system self-check practical to run in simulation.
    defparam uut.u_bcd.u_led.DELAY_MAX = 10;
    defparam uut.u_bcd.u_servo.WAIT_TIME = 1000;

    assign dut_fsm_state = uut.u_master_fsm.U_MASTER_FSM.debug_state;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Passive monitors do not drive integration-side control signals.
    always @(posedge clk or posedge arst) begin
        if (arst) begin
            req_write_count    <= 0;
            req_read_count     <= 0;
            update_count       <= 0;
            done_flag_count    <= 0;
            servo_flag_count   <= 0;
            change_flag_count  <= 0;
            account_entry_count <= 0;
            done_write_count   <= 0;
            done_read_count    <= 0;
            led_full_count     <= 0;
            change_cplt_count  <= 0;
            servo_close_state_count <= 0;
            ext_status_mismatch_count <= 0;
            onboard_animation_diff_count <= 0;
            monitored_state_d  <= ST_INSERT;
            captured_order_info <= 32'd0;
        end
        else begin
            monitored_state_d <= dut_fsm_state;

            if (uut.req_write) begin
                req_write_count <= req_write_count + 1;
                captured_order_info <= uut.order_info;
            end
            if (uut.req_read)
                req_read_count <= req_read_count + 1;
            if (uut.update_en)
                update_count <= update_count + 1;
            if (uut.flag_DONE)
                done_flag_count <= done_flag_count + 1;
            if (uut.flag_SERVO)
                servo_flag_count <= servo_flag_count + 1;
            if (uut.flag_CHANGE)
                change_flag_count <= change_flag_count + 1;
            if ((dut_fsm_state == ST_ACCOUNT) &&
                (monitored_state_d != ST_ACCOUNT))
                account_entry_count <= account_entry_count + 1;
            if (uut.done_write)
                done_write_count <= done_write_count + 1;
            if (uut.done_read)
                done_read_count <= done_read_count + 1;
            if (led == 16'hffff)
                led_full_count <= led_full_count + 1;
            if (uut.flag_cplt_CHANGE)
                change_cplt_count <= change_cplt_count + 1;
            if ((uut.u_bcd.u_servo.state == 3'd3) ||
                (uut.u_bcd.u_servo.state == 3'd4))
                servo_close_state_count <= servo_close_state_count + 1;

            // Waveform recommendations: ext_stock_led, ext_sugar_bar,
            // ext_ice_bar, led, uut.flag_DONE, uut.flag_SERVO and
            // uut.flag_CHANGE. External outputs must remain status-only even
            // while the onboard LED is selected from led_anim in DONE.
            if ((ext_stock_led !== uut.inventory_led) ||
                (ext_sugar_bar !== uut.sugar_led) ||
                (ext_ice_bar !== uut.ice_led))
                ext_status_mismatch_count <= ext_status_mismatch_count + 1;

            if (uut.led_anim_active && (led !== uut.led_status))
                onboard_animation_diff_count <= onboard_animation_diff_count + 1;
        end
    end

    task apply_reset;
        begin
            arst       <= 1'b1;
            btn_enter  <= 1'b0;
            btn_100    <= 1'b0;
            btn_500    <= 1'b0;
            btn_1000   <= 1'b0;
            btn_refund <= 1'b0;
            sw         <= 15'd0;

            repeat (10) @(posedge clk);
            arst <= 1'b0;
            repeat (20) @(posedge clk);
        end
    endtask

    task press_money;
        input integer denomination;
        begin
            @(posedge clk);
            if (denomination == 100)
                btn_100 <= 1'b1;
            else if (denomination == 500)
                btn_500 <= 1'b1;
            else if (denomination == 1000)
                btn_1000 <= 1'b1;
            else begin
                $display("  [FAIL] unsupported denomination %0d", denomination);
                fail_count = fail_count + 1;
            end

            repeat (20) @(posedge clk);
            btn_100  <= 1'b0;
            btn_500  <= 1'b0;
            btn_1000 <= 1'b0;
            repeat (20) @(posedge clk);
        end
    endtask

    task press_enter_user;
        begin
            @(posedge clk);
            btn_enter <= 1'b1;
            repeat (20) @(posedge clk);
            btn_enter <= 1'b0;
            repeat (20) @(posedge clk);
        end
    endtask

    task press_refund_user;
        begin
            @(posedge clk);
            btn_refund <= 1'b1;
            repeat (20) @(posedge clk);
            btn_refund <= 1'b0;
            repeat (20) @(posedge clk);
        end
    endtask

    task wait_fsm_state_timeout;
        input [3:0] expected_state;
        input [8*24-1:0] label;
        integer i;
        begin
            i = 0;
            while ((dut_fsm_state !== expected_state) &&
                   (i < FSM_TIMEOUT)) begin
                @(posedge clk);
                i = i + 1;
            end

            if (dut_fsm_state !== expected_state) begin
                $display("  [FAIL] %s TIMEOUT | state=%0d exp=%0d (t=%0t ns)",
                         label, dut_fsm_state,
                         expected_state, $time);
                fail_count = fail_count + 1;
            end
            else
                $display("  [PASS] %s reached", label);
        end
    endtask

    task wait_account_seen_timeout;
        input integer account_count_before;
        integer i;
        begin
            i = 0;
            while ((account_entry_count - account_count_before < 1) &&
                   (i < FSM_TIMEOUT)) begin
                @(posedge clk);
                i = i + 1;
            end
            if (account_entry_count - account_count_before < 1) begin
                $display("  [FAIL] ACCOUNT state TIMEOUT (t=%0t ns)", $time);
                fail_count = fail_count + 1;
            end
            else
                $display("  [PASS] ACCOUNT state reached");
        end
    endtask

    task wait_done_write_timeout;
        input integer done_write_before;
        integer i;
        begin
            i = 0;
            while ((done_write_count - done_write_before < 1) &&
                   (i < AXI_TIMEOUT)) begin
                @(posedge clk);
                i = i + 1;
            end
            if (done_write_count - done_write_before < 1) begin
                $display("  [FAIL] done_write TIMEOUT (t=%0t ns)", $time);
                fail_count = fail_count + 1;
            end
            else
                $display("  [PASS] done_write asserted");
        end
    endtask

    task wait_done_read_timeout;
        input integer done_read_before;
        integer i;
        begin
            i = 0;
            while ((done_read_count - done_read_before < 1) &&
                   (i < AXI_TIMEOUT)) begin
                @(posedge clk);
                i = i + 1;
            end
            if (done_read_count - done_read_before < 1) begin
                $display("  [FAIL] done_read TIMEOUT (t=%0t ns)", $time);
                fail_count = fail_count + 1;
            end
            else
                $display("  [PASS] done_read asserted");
        end
    endtask

    task wait_led_done_timeout;
        integer i;
        begin
            i = 0;
            while (!uut.done_cplt_latched && i < D_TIMEOUT) begin
                @(posedge clk);
                i = i + 1;
            end
            if (!uut.done_cplt_latched) begin
                $display("  [FAIL] latched flag_cplt_DONE TIMEOUT (t=%0t ns)", $time);
                fail_count = fail_count + 1;
            end
            else
                $display("  [PASS] flag_cplt_DONE captured");
        end
    endtask

    task wait_servo_open_timeout;
        integer i;
        begin
            i = 0;
            while (!uut.servo_cplt_latched && i < D_TIMEOUT) begin
                @(posedge clk);
                i = i + 1;
            end
            if (!uut.servo_cplt_latched) begin
                $display("  [FAIL] latched flag_cplt_SERVO TIMEOUT (t=%0t ns)", $time);
                fail_count = fail_count + 1;
            end
            else
                $display("  [PASS] flag_cplt_SERVO captured");
        end
    endtask

    task wait_servo_close_timeout;
        integer i;
        begin
            i = 0;
            while (!uut.change_cplt_latched && i < D_TIMEOUT) begin
                @(posedge clk);
                i = i + 1;
            end
            if (!uut.change_cplt_latched) begin
                $display("  [FAIL] latched flag_cplt_CHANGE TIMEOUT (t=%0t ns)", $time);
                fail_count = fail_count + 1;
            end
            else
                $display("  [PASS] flag_cplt_CHANGE captured");
        end
    endtask

    task check_money;
        input [15:0] expected_money;
        begin
            #1;
            if (uut.u_bcd.w_current_money !== expected_money) begin
                $display("  [FAIL] current_money | got=%0d exp=%0d (t=%0t ns)",
                         uut.u_bcd.w_current_money, expected_money, $time);
                fail_count = fail_count + 1;
            end
            else
                $display("  [PASS] current_money=%0d", expected_money);
        end
    endtask

    // Reusable front half for SUCCESS, NO_MONEY, SOLD_OUT and invalid-order
    // scenarios.  Future tests only need to vary money and the three selectors.
    task prepare_order;
        input [4:0] drink_sel;
        input [4:0] sugar_sel;
        input [4:0] ice_sel;
        integer account_before;
        begin
            account_before = account_entry_count;

            press_enter_user;
            wait_fsm_state_timeout(ST_DRINK_SEL, "DRINK_SEL");

            sw[14:10] <= drink_sel;
            repeat (3) @(posedge clk);
            press_enter_user;
            wait_fsm_state_timeout(ST_SUGAR_SEL, "SUGAR_SEL");

            sw[9:5] <= sugar_sel;
            repeat (3) @(posedge clk);
            press_enter_user;
            wait_fsm_state_timeout(ST_ICE_SEL, "ICE_SEL");

            sw[4:0] <= ice_sel;
            repeat (3) @(posedge clk);
            press_enter_user;
            wait_account_seen_timeout(account_before);
        end
    endtask

    // Complete one successful apple purchase, including dispense, servo open,
    // user refund/change input, servo close and return to INSERT.
    task do_success_purchase_apple;
        input integer purchase_number;
        input expected_inventory_available;
        integer req_write_before;
        integer req_read_before;
        integer update_before;
        integer done_write_before;
        integer done_read_before;
        integer done_flag_before;
        integer servo_flag_before;
        integer change_flag_before;
        integer led_full_before;
        integer ext_mismatch_before;
        integer animation_diff_before;
        begin
            $display("\n  --- Successful apple purchase %0d ---", purchase_number);

            req_write_before   = req_write_count;
            req_read_before    = req_read_count;
            update_before      = update_count;
            done_write_before  = done_write_count;
            done_read_before   = done_read_count;
            done_flag_before   = done_flag_count;
            servo_flag_before  = servo_flag_count;
            change_flag_before = change_flag_count;
            led_full_before    = led_full_count;
            ext_mismatch_before = ext_status_mismatch_count;
            animation_diff_before = onboard_animation_diff_count;

            press_money(1000);
            check_money(16'd1000);
            press_money(500);
            check_money(16'd1500);

            prepare_order(5'b10000, 5'b00001, 5'b00001);
            wait_done_write_timeout(done_write_before);
            wait_done_read_timeout(done_read_before);
            wait_fsm_state_timeout(ST_DONE, "DONE");
            repeat (3) @(posedge clk);

            `CHECK_HEX("captured apple order", captured_order_info, 32'h0000_4000)
            `CHECK("payment status SUCCESS", uut.status_out, 32'd1)
            `CHECK_BIT("apple inventory availability", uut.inventory_out, 14,
                       expected_inventory_available)
            `CHECK("automatic req_write delta",
                   req_write_count - req_write_before, 1)
            `CHECK("automatic req_read delta",
                   req_read_count - req_read_before, 1)
            `CHECK("automatic update delta",
                   update_count - update_before, 1)
            check_money(16'd300);

            // Switches intentionally remain selected until the animation is
            // complete.  The DONE latch must prevent loss of the raw pulse.
            wait_led_done_timeout;
            `CHECK("LED animation reached 0xFFFF",
                   (led_full_count - led_full_before) > 0, 1'b1)
            `CHECK("FSM waits in DONE while switches are on",
                   dut_fsm_state, ST_DONE)
            `CHECK("external stock LED matches inventory status",
                   ext_stock_led, uut.inventory_led)
            `CHECK("external sugar bar matches sugar status",
                   ext_sugar_bar, uut.sugar_led)
            `CHECK("external ice bar matches ice status",
                   ext_ice_bar, uut.ice_led)
            `CHECK("external LEDs stayed status-only during DONE animation",
                   ext_status_mismatch_count - ext_mismatch_before, 0)
            `CHECK("onboard LED selected animation during DONE",
                   (onboard_animation_diff_count - animation_diff_before) > 0,
                   1'b1)

            sw <= 15'd0;
            wait_fsm_state_timeout(ST_SERVO, "SERVO");
            wait_servo_open_timeout;
            `CHECK("servo opened", uut.u_bcd.u_servo.servo_opened, 1'b1)

            // Refund/change is a real conditioned user input.  The latched
            // SERVO completion allows the user to press it later.
            press_refund_user;
            wait_fsm_state_timeout(ST_CHANGE, "CHANGE");
            wait_servo_close_timeout;
            wait_fsm_state_timeout(ST_INSERT, "INSERT return");
            repeat (3) @(posedge clk);

            `CHECK("servo closed", uut.u_bcd.u_servo.servo_opened, 1'b0)
            `CHECK("DONE command pulse delta",
                   done_flag_count - done_flag_before, 1)
            `CHECK("SERVO command pulse delta",
                   servo_flag_count - servo_flag_before, 1)
            `CHECK("CHANGE command pulse delta",
                   change_flag_count - change_flag_before, 1)
            check_money(16'd0);
        end
    endtask

    task run_reset_check;
        begin
            $display("\n===== Phase 0: Reset check =====");
            `CHECK("reset state INSERT",
                   dut_fsm_state, ST_INSERT)
            `CHECK_HEX("reset LED status", led, 16'h7400)
            `CHECK("reset external stock LED", ext_stock_led, 5'b11101)
            `CHECK("reset external sugar bar", ext_sugar_bar, 5'b00000)
            `CHECK("reset external ice bar", ext_ice_bar, 5'b00000)
            check_money(16'd0);
        end
    endtask

    task run_closed_servo_refund_phase;
        integer change_flag_before;
        integer change_cplt_before;
        integer close_state_before;
        begin
            $display("\n===== Phase 0B: Closed-servo refund completion =====");

            `CHECK("servo initially closed",
                   uut.u_bcd.u_servo.servo_opened, 1'b0)
            `CHECK("servo FSM initially IDLE",
                   uut.u_bcd.u_servo.state, 3'd0)
            `CHECK("closed pulse width retained",
                   uut.u_bcd.u_servo.pulse_width,
                   uut.u_bcd.u_servo.CLOSE_PULSE)

            press_money(500);
            check_money(16'd500);

            change_flag_before = change_flag_count;
            change_cplt_before = change_cplt_count;
            close_state_before = servo_close_state_count;

            // 음료 배출 전에 환불: 서보는 한 번도 열린 적이 없다.
            press_refund_user;
            wait_fsm_state_timeout(ST_INSERT, "refund INSERT return");
            repeat (5) @(posedge clk);

            `CHECK("refund CHANGE command delta",
                   change_flag_count - change_flag_before, 1)
            `CHECK("closed CHANGE completion pulse delta",
                   change_cplt_count - change_cplt_before, 1)
            `CHECK("no CLOSE/CLOSE_WAIT motor state",
                   servo_close_state_count - close_state_before, 0)
            `CHECK("servo remains closed",
                   uut.u_bcd.u_servo.servo_opened, 1'b0)
            `CHECK("servo FSM returned IDLE",
                   uut.u_bcd.u_servo.state, 3'd0)
            `CHECK("closed pulse width unchanged",
                   uut.u_bcd.u_servo.pulse_width,
                   uut.u_bcd.u_servo.CLOSE_PULSE)
            check_money(16'd0);

            // 완료 응답은 요청당 정확히 한 번이어야 한다.
            repeat (20) @(posedge clk);
            `CHECK("no repeated CHANGE completion pulse",
                   change_cplt_count - change_cplt_before, 1)
        end
    endtask

    task run_normal_purchase_phase;
        begin
            $display("\n===== Phase 1: Normal purchase =====");
            do_success_purchase_apple(1, 1'b0);
        end
    endtask

    task run_no_money_phase;
        integer req_write_before;
        integer req_read_before;
        integer update_before;
        integer done_write_before;
        integer done_read_before;
        integer done_flag_before;
        integer servo_flag_before;
        integer change_flag_before;
        begin
            $display("\n===== Phase 2: NO_MONEY =====");

            req_write_before   = req_write_count;
            req_read_before    = req_read_count;
            update_before      = update_count;
            done_write_before  = done_write_count;
            done_read_before   = done_read_count;
            done_flag_before   = done_flag_count;
            servo_flag_before  = servo_flag_count;
            change_flag_before = change_flag_count;

            press_money(1000);
            check_money(16'd1000);
            prepare_order(5'b10000, 5'b00001, 5'b00001);
            wait_done_write_timeout(done_write_before);
            wait_done_read_timeout(done_read_before);
            wait_fsm_state_timeout(ST_NO_MONEY, "NO_MONEY");
            repeat (20) @(posedge clk);

            `CHECK_HEX("captured apple order", captured_order_info, 32'h0000_4000)
            `CHECK("NO_MONEY status", uut.status_out, 32'd2)
            `CHECK("FSM state NO_MONEY",
                   dut_fsm_state, ST_NO_MONEY)
            `CHECK("req_write delta", req_write_count - req_write_before, 1)
            `CHECK("req_read delta", req_read_count - req_read_before, 1)
            `CHECK("update delta", update_count - update_before, 0)
            `CHECK("DONE pulse delta", done_flag_count - done_flag_before, 0)
            `CHECK("SERVO pulse delta", servo_flag_count - servo_flag_before, 0)
            `CHECK("CHANGE pulse delta", change_flag_count - change_flag_before, 0)
            check_money(16'd1000);
            `CHECK_BIT("apple inventory still available", uut.inventory_out, 14, 1'b1)
            `CHECK("apple stock not decremented",
                   uut.u_bcd.u_axi_slave.u_inventory_core.db_stock[0], 4'd1)
        end
    endtask

    task run_sold_out_phase;
        integer req_write_before;
        integer req_read_before;
        integer update_before;
        integer done_write_before;
        integer done_read_before;
        integer done_flag_before;
        integer servo_flag_before;
        integer change_flag_before;
        begin
            $display("\n===== Phase 3: SOLD_OUT =====");
            $display("  Exhausting initial apple stock (1)...");

            do_success_purchase_apple(1, 1'b0);

            $display("\n  --- Second apple purchase attempt (expect SOLD_OUT) ---");
            req_write_before   = req_write_count;
            req_read_before    = req_read_count;
            update_before      = update_count;
            done_write_before  = done_write_count;
            done_read_before   = done_read_count;
            done_flag_before   = done_flag_count;
            servo_flag_before  = servo_flag_count;
            change_flag_before = change_flag_count;

            press_money(1000);
            press_money(500);
            check_money(16'd1500);
            prepare_order(5'b10000, 5'b00001, 5'b00001);
            wait_done_write_timeout(done_write_before);
            wait_done_read_timeout(done_read_before);
            wait_fsm_state_timeout(ST_SOLD_OUT, "SOLD_OUT");
            repeat (20) @(posedge clk);

            `CHECK_HEX("captured apple order", captured_order_info, 32'h0000_4000)
            `CHECK("SOLD_OUT status", uut.status_out, 32'd3)
            `CHECK("FSM state SOLD_OUT",
                   dut_fsm_state, ST_SOLD_OUT)
            `CHECK("req_write delta", req_write_count - req_write_before, 1)
            `CHECK("req_read delta", req_read_count - req_read_before, 1)
            `CHECK("update delta", update_count - update_before, 0)
            `CHECK("DONE pulse delta", done_flag_count - done_flag_before, 0)
            `CHECK("SERVO pulse delta", servo_flag_count - servo_flag_before, 0)
            `CHECK("CHANGE pulse delta", change_flag_count - change_flag_before, 0)
            check_money(16'd1500);
            `CHECK_BIT("apple inventory empty", uut.inventory_out, 14, 1'b0)
            `CHECK("apple stock is zero",
                   uut.u_bcd.u_axi_slave.u_inventory_core.db_stock[0], 4'd0)
        end
    endtask

    initial begin
        fail_count = 0;
        apply_reset;

        $display("========================================================");
        $display(" A+B+C+D user-input integration self-check");
        $display("========================================================");

        run_reset_check;
        run_closed_servo_refund_phase;

        apply_reset;
        run_normal_purchase_phase;

        apply_reset;
        run_no_money_phase;

        apply_reset;
        run_sold_out_phase;

        $display("\n========================================================");
        if (fail_count == 0)
            $display("ALL SYSTEMS GREEN");
        else
            $display("FAIL: %0d checks failed", fail_count);
        $display("========================================================\n");
        $finish;
    end

    // Last-resort watchdog in addition to the per-stage timeouts above.
    initial begin
        #500000;
        $display("\n[FAIL] GLOBAL TEST TIMEOUT");
        $display("FAIL: %0d checks failed", fail_count + 1);
        $finish;
    end

endmodule
