// ==============================================================================
// 모듈명  : btn_conditioner (버튼 입력 정제기 최상위 모듈)
// 설명    : 물리 버튼의 노이즈(채터링)를 제거하고, 버튼을 길게 누르더라도 
//           내부 FSM(Master)에게는 딱 1클럭짜리 깔끔한 펄스(Pulse)만 전달하도록 정제함.
// 구조    : debouncer(노이즈 제거) -> edge_detector_p(1클럭 펄스 생성) 직렬 연결
// ==============================================================================
module btn_conditioner (
    input clk,          // 시스템 글로벌 클럭
    input arst,         // 비동기 리셋 (Active-High)
    input btn_in,       // 물리 버튼 입력 (노이즈 포함, 누르는 동안 계속 1 유지)
    output btn_out      // FSM으로 보내는 최종 출력 (노이즈 없음, 누르는 순간 딱 1클럭만 1)
);

    // 디바운서를 통과한 '노이즈는 없지만 길게 켜져 있는' 신호를 연결하는 내부 전선
    wire w_clean_btn;

    // 1단계: 물리적 노이즈(채터링) 제거기
    debouncer u_debouncer(
        .clk(clk), .arst(arst),
        .noisy_btn(btn_in),
        .clean_btn(w_clean_btn)
    );

    // 2단계: 길게 눌린 신호를 1클럭짜리 짧은 펄스로 압축하는 엣지 검출기
    edge_detector_p u_edge(
        .clk(clk), .arst(arst),
        .cp(w_clean_btn),       // 디바운서를 거친 깨끗한 신호를 입력으로 받음
        .p_edge(btn_out),       // 버튼이 눌리는 찰나(Rising Edge)에 딱 1클럭만 1 출력
        .n_edge()               // 버튼이 떼어지는 순간(Falling Edge)은 사용하지 않으므로 비워둠
    );
    
endmodule
