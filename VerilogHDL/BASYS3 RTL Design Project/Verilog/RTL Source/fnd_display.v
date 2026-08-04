// ==============================================================================
// 서브 모듈 1 : fnd_display (동적 스캐닝 디스플레이 구동기)
// 설명    : FND는 4자리의 불을 동시에 켤 수 없습니다. (전선이 모자람)
//           따라서 1ms(밀리초)마다 아주 빠른 속도로 천, 백, 십, 일의 자리를
//           번갈아 가며 켜서, 사람 눈에는 4자리가 동시에 켜진 것처럼 착각하게 만듭니다.
// ==============================================================================
module fnd_display (
input clk,
input arst,
input [15:0] display_data, // 화면에 띄울 전체 4자리 데이터 묶음 (16비트)
output [6:0] seg,
output [3:0] an
);

// 1ms 타임 타이머 설정 (100MHz 클럭 기준 100,000번 세면 1ms)
parameter REFRESH_MAX = 100000;
reg [16:0] refresh_cnt;
wire tick_1ms;

// 1ms마다 딱 한 번만 1로 튀는 tick 신호 생성기
always @(posedge clk or posedge arst) begin
    if(arst) refresh_cnt <= 0;
    else begin
        if (refresh_cnt < REFRESH_MAX -1)
            refresh_cnt <= refresh_cnt + 1;
        else
            refresh_cnt <= 0;
    end
end
assign tick_1ms = (refresh_cnt == REFRESH_MAX - 1) ? 1'b1 : 1'b0;

// 1ms가 지날 때마다 다음 자릿수(0->1->2->3->0...)로 넘겨주는 자리표시 카운터
reg [1:0] digit_sel;
always @(posedge clk or posedge arst) begin
    if (arst)
        digit_sel <= 2'b00;
    else if (tick_1ms)
        digit_sel <= digit_sel + 1;
end

// 현재 선택된 자리에 들어갈 숫자값(current_hex)과, 그 자리에 불을 켤 스위치 신호(current_en)
reg [3:0] current_hex;
reg [3:0] current_en;

// digit_sel 값에 따라 16비트 데이터를 4비트씩 쪼개서 선택
always @(digit_sel or display_data) begin
    case (digit_sel)
       2'b00 : begin // [일]의 자리 (오른쪽 끝) 켜기
        current_hex = display_data[3:0];
        current_en = 4'b0001;
       end
       2'b01 : begin // [십]의 자리 켜기
        current_hex = display_data[7:4];
        current_en = 4'b0010;
       end
       2'b10 : begin // [백]의 자리 켜기
        current_hex = display_data[11:8];
        current_en = 4'b0100;
       end
       2'b11 : begin // [천]의 자리 (왼쪽 끝) 켜기
        current_hex = display_data[15:12];
        current_en = 4'b1000;
       end
    endcase
end

// 선택된 4비트 숫자/문자 값을 실제 7개의 LED 패턴(0101010 등)으로 번역해 주는 디코더 조립
decoder_7seg u_decoder(
    .hex_value(current_hex),
    .b(current_en),
    .seg(seg),
    .an(an)
);

endmodule
