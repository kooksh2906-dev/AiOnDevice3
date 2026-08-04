`timescale 1ns / 1ps

module servo_pwm_tb;

reg clk;
reg reset_p;

reg flag_SERVO;
reg flag_CHANGE;

wire servo_out;

wire flag_cplt_SERVO;
wire flag_cplt_CHANGE;

// DUT 인스턴스화
servo_pwm DUT(
    .clk(clk),
    .reset_p(reset_p),
    .flag_SERVO(flag_SERVO),
    .flag_CHANGE(flag_CHANGE),
    .servo_out(servo_out),
    .flag_cplt_SERVO(flag_cplt_SERVO),
    .flag_cplt_CHANGE(flag_cplt_CHANGE)
);

//==================================================
// 100MHz Clock 생성 (1주기 = 10ns)
//==================================================
always #5 clk = ~clk;

initial begin
    // ✅ 파형 덤프 설정
    $dumpfile("servo_pwm_tb.vcd");
    $dumpvars(0, servo_pwm_tb);

    // 초기값 설정
    clk = 0;
    reset_p = 1;
    flag_SERVO  = 0;
    flag_CHANGE = 0;

    //==================================================
    // [시나리오 1] Reset (초기화)
    // 모든 내부 레지스터가 초기값(IDLE, CLOSE_PULSE 등)을 갖는지 확인
    //==================================================
    #100;
    reset_p = 0;
    #100; // 리셋 후 안정화 대기

    //==================================================
    // [시나리오 4] 예외 상황 (오작동 방지 검증)
    // 서보가 닫혀있는 상태(servo_opened=0)에서 억지로 닫기(CHANGE) 요청
    // -> state가 IDLE을 꼿꼿이 유지하는지 파형에서 확인!
    //==================================================
    flag_CHANGE = 1;
    #20;          // ✅ 2클럭으로 수정 (race condition 방지)
    flag_CHANGE = 0;

    #1000; // 아무 상태 변화도 일어나지 않음을 파형에서 증명하기 위한 대기

    //==================================================
    // [시나리오 2] OPEN 동작 (서보 열기)
    // 메인 컨트롤러의 음료 배출 요청 (정상 동작 시작)
    // -> state가 OPEN으로 변하고 펄스폭이 OPEN_PULSE로 바뀌는지 확인!
    //==================================================
    flag_SERVO = 1;
    #20;          // ✅ 2클럭으로 수정 (race condition 방지)
    flag_SERVO = 0;

    // servo_pwm.v의 WAIT_TIME = 1000 기준 약 10,200ns 소요
    #15000;

    //==================================================
    // [시나리오 3] CHANGE 동작 (서보 닫기)
    // 열려있는 상태(servo_opened=1)에서 정상적인 닫기 요청
    // -> state가 CLOSE로 변하고 펄스폭이 CLOSE_PULSE로 복귀하는지 확인!
    //==================================================
    flag_CHANGE = 1;
    #20;          // ✅ 2클럭으로 수정 (race condition 방지)
    flag_CHANGE = 0;

    // CLOSE 완료 대기
    #15000;

    // 시뮬레이션 종료
    $finish;
end

endmodule