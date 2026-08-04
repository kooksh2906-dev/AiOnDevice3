module money_register (
    input clk,
    input arst,
    input [3:0] state,
    input btn_100, input btn_500, input btn_1000, // 1클럭 펄스로 정제된 버튼 입력
    
    // 💡 수정된 부분: 가격을 빼는 대신, AXI에서 읽어온 잔돈으로 업데이트!
    input update_en,          // AXI Read가 끝난 후 팀원 A(FSM)가 주는 갱신 신호
    input [15:0] change_in,   // AXI 마스터 모듈의 change_out 전선과 연결될 값
    
    output reg [15:0] current_money
);

    parameter INSERT = 4'd0;
    parameter RE_INSERT = 4'd6;
    parameter SERVO = 4'd9;
    parameter CHANGE = 4'd10;

    always @(posedge clk or posedge arst) begin
        if (arst) begin
            current_money <= 16'd0;
        end
        else begin
            // 1순위: 반환 상태(CHANGE)가 되면 돈을 즉시 0원으로 비움
            if(state == CHANGE) begin
                current_money <= 16'd0;
            end
            
            // 2순위: 💡 결제 완료 후, 슬레이브가 계산해 준 '잔돈'으로 내 지갑을 갱신
            else if (update_en) begin
                current_money <= change_in; 
            end

            // 3순위: 돈 넣는 상태(INSERT, RE_INSERT)에서 버튼 펄스에 맞춰 누적
            else if (state == INSERT || state == RE_INSERT) begin
                if (btn_100)       current_money <= current_money + 16'd100;
                else if (btn_500)  current_money <= current_money + 16'd500; 
                else if (btn_1000) current_money <= current_money + 16'd1000;
            end
        end
    end
    
endmodule
