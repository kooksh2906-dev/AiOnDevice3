// ==============================================================================
// 모듈명  : fnd_display_ctrl (FND 최상위 컨트롤러)
// 설명    : 팀원 A의 FSM에서 현재 상태(state)와 투입/잔돈 금액(value)을 받아,
//           상태에 따라 금액을 출력할지(숫자), 특정 메시지(LESS, donE 등)를
//           출력할지 결정하여 FND 화면으로 띄워주는 최종 우체국 역할.
// ==============================================================================
module fnd_display_ctrl (
input clk,
input arst,
input [3:0] state,      // 팀원 A(FSM)가 알려주는 현재 자판기 상태 (예: 4=잔액부족, 5=결제성공)
input [15:0] value,     // FSM에서 넘겨주는 금액 데이터 (예: 투입된 돈 1500)
output [6:0] seg,       // FND LED의 각 조각(A~G)을 켜고 끄는 7가닥 선
output [3:0] an         // 4자리의 FND 중 어느 자리에 불을 켤지 선택하는 4가닥 선 (자릿수 선택기)
);

// BCD 변환기에서 나온 각 자릿수(천, 백, 십, 일) 데이터를 받을 내부 전선
wire [3:0] th, hu, te, on;
wire [15:0] bcd_data;

// 숫자를 예쁘게 4자리로 쪼개주는 BCD 변환기 조립
bin_to_bcd u_bcd(
    .bin(value[13:0]),  // 최대 9999원까지 표시 가능 (14비트)
    .th(th), .hu(hu), .te(te), .on(on)
);
// 쪼개진 4개의 자릿수 데이터를 하나의 16비트 버스로 묶음
assign bcd_data = {th, hu, te, on};

// 상태에 따라 최종적으로 화면에 쏠 16비트 데이터 (문자냐 숫자냐?)
reg [15:0] final_display_data;

// FSM 상태(state)에 따른 화면 분기 로직 (상태 번호는 팀원 A와 합의된 번호 사용)
always @(*) begin
    case (state)
       // 아래의 HEX 값은 decoder_7seg 모듈에서 정의한 커스텀 문자 코드에 대응함
       4'd4 : final_display_data = 16'hAB55; // LESS (잔액 부족). 'S' 대신 숫자 5의 LED 모양(0101) 사용
       4'd5 : final_display_data = 16'hDEFB; // donE (결제 완료). 'D', 'E', 'F', 'B' 코드 조합
       4'd6 : final_display_data = 16'hFEFB; // nonE (재고 없음). 'n', 'o', 'n', 'E'
       4'd7 : final_display_data = 16'hBFDC; // End  (영업 종료). 'E', 'n', 'd', '빈칸'
       // 상태가 문자를 띄울 상태가 아니라면(IDLE 등), BCD 변환기로 쪼갠 투입 금액(숫자)을 그대로 출력
       default: final_display_data = bcd_data;
    endcase
end

// 결정된 16비트 데이터를 받아, 잔상 효과(동적 스캐닝)로 화면에 불을 켜는 모듈 조립
fnd_display u_ctrl(
    .clk(clk), .arst(arst),
    .display_data(final_display_data),
    .seg(seg),
    .an(an)
);

endmodule
