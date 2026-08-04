// ==============================================================================
// 서브 모듈 1 : debouncer (채터링 방지기)
// 설명    : 버튼이 눌릴 때 발생하는 기계적 진동(바운스)을 무시하고,
//           일정 시간(10ms) 동안 안정적으로 눌려있을 때만 진짜 입력으로 인정함.
// ==============================================================================
module debouncer (
    input clk,
    input arst,
    input noisy_btn,    // 덜덜 떨리는 물리 버튼 입력
    output reg clean_btn // 안정화된 버튼 출력
);

    // 시뮬레이션용(10)과 실제 FPGA 보드용(1,000,000 = 100MHz 기준 10ms) 파라미터 분리
    // 보드에 올릴 때는 1000000을 사용해야 함
    parameter DEBOUNCE_TIME = 10;
    
    // 최대 10^6을 카운트하기 위해 20비트 할당 (2^20 = 약 100만)
    reg [19:0] count;

    always @(posedge clk or posedge arst) begin
        if(arst) begin
            count <= 20'd0;
            clean_btn <= 1'b0;
        end
        else begin
            if(noisy_btn == 1'b1) begin
                // 버튼이 눌린 상태 유지 중
                if(count < DEBOUNCE_TIME) begin
                    // 지정된 시간(10ms)이 될 때까지 카운트만 증가
                    count <= count + 1;
                    clean_btn <= 1'b0; // 아직 불안정하므로 출력은 주지 않음
                end
                else begin
                    // 10ms 동안 단 한 번도 안 떨어지고 눌려있었다면 진짜 입력으로 인정!
                    clean_btn <= 1'b1;
                end
            end
            else begin
                // 버튼에서 손을 떼거나, 채터링 때문에 아주 잠깐이라도 0으로 떨어지면 즉시 초기화
                count <= 20'd0;
                clean_btn <= 1'b0;
            end
        end
    end
    
endmodule
