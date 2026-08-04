`timescale 1ns/1ps
//======================================================================
// led_animation_ctrl_tb.v
//
// LED 애니메이션 제어 모듈(led_animation_ctrl) 검증 테스트벤치
//
// 검증 문서의 3가지 시나리오를 순서대로 자동 수행하고,
// self-checking 방식(PASS/FAIL 자동 판정)으로 결과를 출력합니다.
//
//   시나리오 1 : 정상 동작 - 리셋 후 flag_DONE 수신 -> 16단계 점등 -> 완료
//                (flag_DONE가 계속 High로 유지되어도 단 1회만 트리거되는지 확인)
//   시나리오 2 : 애니메이션 도중 비동기 reset_p 인가 -> 즉시 초기화 -> 재시작
//   시나리오 3 : led_cnt 누적 정확성 (16단계, off-by-one 없이 0xFFFF 도달)
//                -> run_full_animation_check 태스크에서 매 단계 기대값과
//                   비교하므로 시나리오 1, 2 안에서 함께 검증됩니다.
//
// ※ 참고: 검증 문서(노션 초안)에서는 입력을 flag_DONE, 출력을
//    flag_cplt_DONE으로 표기하고 있지만, 실제 DUT 포트명은
//    flag_DONE / flag_cplt_DONE 입니다. 동작(상승 에지 검출, FSM,
//    시프트 누적 점등)은 문서 설명과 동일하다고 보고, 본
//    테스트벤치는 실제 DUT 포트명(flag_DONE, flag_cplt_DONE)을 그대로
//    사용합니다.
//
// ※ DUT의 DELAY_MAX가 시뮬레이션용 짧은 값(예: 10)으로 설정되어
//    있어야 합니다. 실제 FPGA용 값(50_000_000)이 그대로 있으면
//    한 단계 점등 간격이 매우 길어져 워치독(타임아웃)에 걸립니다.
//    -> 그 경우 DUT 소스에서 DELAY_MAX를 시뮬레이션용 값으로 바꿔주세요.
//======================================================================

module led_animation_ctrl_tb;

reg clk;
reg reset_p;
reg flag_DONE;

wire [15:0] led;
wire flag_cplt_DONE;

led_animation_ctrl DUT(
    .clk(clk),
    .reset_p(reset_p),
    .flag_DONE(flag_DONE),

    .led(led),
    .flag_cplt_DONE(flag_cplt_DONE)
);

always #5 clk = ~clk;

// ---------------- 기대값(시프트 누적 패턴) 테이블 ----------------
// led_cnt =  0 -> 16'h0001
// led_cnt =  1 -> 16'h0003
//  ...
// led_cnt = 15 -> 16'hFFFF
reg [15:0] expected_led [0:15];
integer i;
integer time_mark [0:15];

// ---------------- 결과 집계 ----------------
integer pass_cnt;
integer fail_cnt;

// ---------------- 파형 덤프 (필요 시 GTKWave 등으로 확인) ----------------
initial begin
    $dumpfile("led_animation_ctrl_tb.vcd");
    $dumpvars(0, led_animation_ctrl_tb);
end

// ---------------- 전체 워치독 (DUT 행 또는 DELAY_MAX 설정 오류 방지) ----------------
initial begin
    #2_000_000;
    $display("[WATCHDOG][%0d] 시간 초과! DELAY_MAX 설정(시뮬레이션용 작은 값)을 확인하세요.", $time);
    $finish;
end

//======================================================================
// 공통 태스크
//======================================================================

// 리셋 인가 (최소 3클럭 유지 후 해제)
task do_reset;
begin
    reset_p = 1;
    flag_DONE   = 0;
    repeat (3) @(posedge clk);
    #1;
    reset_p = 0;
    @(posedge clk);
end
endtask

// flag_DONE 1클럭 폭 펄스 (정상적인 상승 에지 1회 트리거)
// 클럭 엣지와 "동시에" 신호를 바꾸면 시뮬레이터의 이벤트 처리 순서에 따라
// DUT가 엣지를 못 보고 놓치는 레이스 컨디션이 생길 수 있으므로,
// @(posedge clk) 직후 #1만큼 살짝 늦춰서 신호를 변경한다.
task pulse_flag_DONE;
begin
    @(posedge clk);
    #1;
    flag_DONE = 1;
    @(posedge clk);
    #1;
    flag_DONE = 0;
end
endtask

// led 값이 바뀔 때까지 대기 (이벤트 기반: DELAY_MAX 실제 값에 의존하지 않음)
// 일정 시간 내에 변화가 없으면 FAIL 처리 후 진행
task wait_led_change;
begin
    fork : wait_block
        begin
            @(led);
            disable wait_block;
        end
        begin
            #200_000;
            $display("[FAIL][%0d] led 값 변화 대기 중 타임아웃 발생", $time);
            fail_cnt = fail_cnt + 1;
            disable wait_block;
        end
    join
end
endtask

// led_cnt 단계(idx)에서 기대값과 현재 led 값을 비교하여 PASS/FAIL 기록
task check_led_step(input integer idx);
begin
    if (led === expected_led[idx]) begin
        $display("[PASS][%0d] led_cnt=%0d 단계 -> led=0x%04h (기대값 일치)", $time, idx, led);
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("[FAIL][%0d] led_cnt=%0d 단계 -> led=0x%04h (기대값 0x%04h)", $time, idx, led, expected_led[idx]);
        fail_cnt = fail_cnt + 1;
    end
end
endtask

// 16단계 사이의 시간 간격이 전부 동일(=DELAY_MAX클럭 균일 주기)한지 검증.
// 값 자체는 우연히 맞아도, 어느 한 단계가 "값 변화 없음(0->0 등)"으로 숨겨지고
// DONE 상태의 강제 대입이 그 자리를 메우는 off-by-one 버그는 간격이 깨지므로
// (마지막 간격만 비정상적으로 짧아짐) 이 검사로 잡아낼 수 있다.
task check_uniform_timing;
    integer k;
    integer ref_gap;
    integer gap;
    integer uniform_ok;
begin
    ref_gap    = time_mark[1] - time_mark[0];
    uniform_ok = 1;
    for (k = 2; k <= 15; k = k + 1) begin
        gap = time_mark[k] - time_mark[k-1];
        if (gap != ref_gap) begin
            $display("[FAIL][%0d] led_cnt=%0d->%0d 구간 간격=%0dns (기준 간격=%0dns와 불일치) - off-by-one/누락 의심", $time, k-1, k, gap, ref_gap);
            fail_cnt   = fail_cnt + 1;
            uniform_ok = 0;
        end
    end
    if (uniform_ok) begin
        $display("[PASS][%0d] 16단계 점등 간격이 모두 균일(%0dns)함 - off-by-one/단계 누락 없음", $time, ref_gap);
        pass_cnt = pass_cnt + 1;
    end
end
endtask

// 16단계 전체를 순서대로 관찰하며 시나리오1/3 기준(off-by-one 포함)으로 검증
task run_full_animation_check;
    integer step;
begin
    for (step = 0; step <= 15; step = step + 1) begin
        wait_led_change;
        time_mark[step] = $time;
        check_led_step(step);
    end
    check_uniform_timing;
end
endtask

//======================================================================
// 메인 시퀀스
//======================================================================
initial begin
    // 기대값 테이블 생성: (16'h0001 << (i+1)) - 1
    for (i = 0; i <= 15; i = i + 1)
        expected_led[i] = (16'h0001 << (i + 1)) - 1;

    clk      = 0;
    reset_p  = 1;
    flag_DONE    = 0;
    pass_cnt = 0;
    fail_cnt = 0;

    //==================================================================
    // 시나리오 1 : 정상 동작 - 리셋 후 flag_DONE 수신
    //==================================================================
    $display("\n========== 시나리오 1: 정상 동작 (리셋 후 flag_DONE 수신) ==========");
    do_reset;

    // 리셋 해제 직후 IDLE 상태 유지 확인
    repeat (5) @(posedge clk);
    if (led === 16'h0000 && flag_cplt_DONE === 1'b0) begin
        $display("[PASS][%0d] 리셋 해제 후 IDLE 유지 (led=0x0000, flag_cplt_DONE=0)", $time);
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("[FAIL][%0d] 리셋 해제 후 IDLE 상태가 아님 (led=0x%04h, flag_cplt_DONE=%b)", $time, led, flag_cplt_DONE);
        fail_cnt = fail_cnt + 1;
    end

    // flag_DONE를 일부러 "계속 High"로 유지한 채 애니메이션을 끝까지 진행시켜
    // 레벨이 아닌 "상승 에지"에서만 단 한 번 트리거되는지 확인
    @(posedge clk);
    #1;
    flag_DONE = 1; // 바로 내리지 않고 계속 유지

    run_full_animation_check; // led_cnt 0~15 16단계 전부 검사 (시나리오1+3 공통)

    // 마지막 단계 후 flag_cplt_DONE 상승 확인
    wait (flag_cplt_DONE === 1'b1 || $time > 2_000_000);
    if (led === 16'hFFFF && flag_cplt_DONE === 1'b1) begin
        $display("[PASS][%0d] 애니메이션 완료: led=0xFFFF, flag_cplt_DONE=1", $time);
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("[FAIL][%0d] 완료 조건 불일치 (led=0x%04h, flag_cplt_DONE=%b)", $time, led, flag_cplt_DONE);
        fail_cnt = fail_cnt + 1;
    end

    // flag_DONE가 아직 High인 상태를 추가로 유지 -> 재트리거(레벨 트리거) 여부 확인
    repeat (50) @(posedge clk);
    if (led === 16'hFFFF && flag_cplt_DONE === 1'b1) begin
        $display("[PASS][%0d] flag_DONE가 계속 High여도 재트리거 없음 (edge 검출 정상)", $time);
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("[FAIL][%0d] flag_DONE가 계속 High인 상태에서 재트리거 발생(레벨 트리거 의심) led=0x%04h, flag_cplt_DONE=%b", $time, led, flag_cplt_DONE);
        fail_cnt = fail_cnt + 1;
    end

    #1;
    flag_DONE = 0;
    @(posedge clk);

    //==================================================================
    // 시나리오 2 : 애니메이션 도중 비동기 reset_p
    //==================================================================
    $display("\n========== 시나리오 2: 애니메이션 도중 비동기 리셋 ==========");
    do_reset;
    repeat (3) @(posedge clk);

    pulse_flag_DONE; // 애니메이션 시작

    // led_cnt가 중간 지점(5단계)에 도달할 때까지 진행
    repeat (5) wait_led_change;
    $display("[INFO][%0d] 애니메이션 중간 지점 도달 (led=0x%04h) -> 지금 reset_p 인가", $time, led);

    // 클럭 에지와 무관한(비동기) 임의의 시점에 reset_p 인가
    #3;
    reset_p = 1;
    #1; // 클럭 에지를 기다리지 않고 즉시 결과 확인 -> 비동기 리셋 검증
    if (led === 16'h0000 && flag_cplt_DONE === 1'b0) begin
        $display("[PASS][%0d] reset_p 인가 즉시(비동기) led=0x0000, flag_cplt_DONE=0", $time);
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("[FAIL][%0d] 비동기 리셋이 즉시 반영되지 않음 (led=0x%04h, flag_cplt_DONE=%b)", $time, led, flag_cplt_DONE);
        fail_cnt = fail_cnt + 1;
    end

    repeat (3) @(posedge clk);
    #1;
    reset_p = 0;

    // 리셋 해제 후 flag_DONE 없이 IDLE 유지되는지 확인
    repeat (5) @(posedge clk);
    if (led === 16'h0000 && flag_cplt_DONE === 1'b0) begin
        $display("[PASS][%0d] 리셋 해제 후 flag_DONE 없을 때 IDLE 유지", $time);
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("[FAIL][%0d] 리셋 해제 후 IDLE 상태가 아님 (led=0x%04h, flag_cplt_DONE=%b)", $time, led, flag_cplt_DONE);
        fail_cnt = fail_cnt + 1;
    end

    // 재시작: flag_DONE 펄스 후 처음부터 정상적으로 재개되는지 전체 검증
    $display("[INFO][%0d] 리셋 이후 재시작 검증 시작", $time);
    pulse_flag_DONE;
    run_full_animation_check;

    wait (flag_cplt_DONE === 1'b1 || $time > 4_000_000);
    if (led === 16'hFFFF && flag_cplt_DONE === 1'b1) begin
        $display("[PASS][%0d] 리셋 후 재시작 애니메이션 정상 완료", $time);
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("[FAIL][%0d] 리셋 후 재시작 애니메이션 완료 실패", $time);
        fail_cnt = fail_cnt + 1;
    end

    //==================================================================
    // 결과 요약
    //==================================================================
    $display("\n========================================");
    $display(" 검증 결과 요약 : PASS=%0d  FAIL=%0d", pass_cnt, fail_cnt);
    if (fail_cnt == 0)
        $display(" >>> 전체 시나리오 PASS <<<");
    else
        $display(" >>> 일부 시나리오 FAIL 발생 - 위 로그를 확인하세요 <<<");
    $display("========================================\n");

    $finish;
end

endmodule