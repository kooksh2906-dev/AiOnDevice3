// ==============================================================================
// 서브 모듈 2 : edge_detector_p (엣지 검출기)
// 설명    : 신호가 변하는 찰나의 순간을 포착하여 1클럭 펄스를 만들어냄.
//           버튼을 1초 동안 꾹 누르고 있어도, FSM이 결제를 1번만 하도록 막아주는 핵심 역할.
// ==============================================================================
module edge_detector_p (
    input clk, arst,
    input cp,           // 디바운서를 통과한 입력 신호
    output p_edge,      // Rising Edge (0 -> 1 상승 찰나) 감지 시 1 출력
    output n_edge       // Falling Edge (1 -> 0 하강 찰나) 감지 시 1 출력
);
    
    // 현재 클럭의 입력값(ff_cur)과 1클럭 전의 입력값(ff_old)을 저장하는 플립플롭
    reg ff_cur, ff_old; 

    always @(posedge clk or posedge arst) begin
        if(arst)begin
            ff_cur <= 1'b0;
            ff_old <= 1'b0;
        end
        else begin
            // 매 클럭마다 값을 옆으로 밀어줌 (Shift 연산과 동일)
            ff_old <= ff_cur; // 1클럭 전 과거 값 저장
            ff_cur <= cp;     // 현재 들어오는 새로운 값 저장
        end
    end

    // 엣지 판별 로직 (과거와 현재의 상태 비교)
    // {ff_cur, ff_old} == 2'b10 의 의미: 과거엔 0이었는데(old), 지금은 1이 되었다(cur) -> 상승 엣지
    assign p_edge = ({ff_cur, ff_old} == 2'b10) ? 1'b1 : 1'b0;
    
    // {ff_cur, ff_old} == 2'b01 의 의미: 과거엔 1이었는데(old), 지금은 0이 되었다(cur) -> 하강 엣지
    assign n_edge = ({ff_cur, ff_old} == 2'b01) ? 1'b1 : 1'b0;
    
endmodule
