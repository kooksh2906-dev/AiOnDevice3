// ==============================================================================
// 모듈명  : axi4_master_inf (AXI4-Lite Master 3연타 콤보 통신 모듈)
// 작성자  : 팀원 B (질문자님)
// 
// [팀원 A (FSM) 님을 위한 사용법]
// 1. 결제를 원할 때: order_info(음료)와 money_in(돈)을 넣고 req_write에 1클럭 펄스를 줍니다.
//    -> 알아서 0x04 -> 0x08 -> 0x00 순서로 3번 쏘고 done_write 펄스로 보고합니다.
// 2. 결과를 원할 때: req_read에 1클럭 펄스를 줍니다.
//    -> 알아서 0x0C -> 0x10 -> 0x14 순서로 3번 읽어와서 출력 핀에 값을 채워두고 
//       done_read 펄스로 보고합니다. 복잡한 AXI 통신은 이 모듈이 다 알아서 합니다!
//
// [팀원 C (Slave) 님을 위한 참고]
// - AXI 통신의 절대 규칙(VALID는 READY를 기다리지 않음, 영수증 의존성 등)을 
//   100% 준수하여 설계된 Safe FSM입니다. 
// - 지연(Delay)이 발생해도 데이터가 유실되지 않도록 튼튼하게 설계되었습니다.
// ==============================================================================
module axi4_master_inf (
    // ==========================================================
    // 1. 글로벌 시스템 신호
    // ==========================================================
    input wire M_AXI_ACLK,
    input wire M_AXI_ARESETN, // Active-Low 리셋

    // ==========================================================
    // 2. 내부 Master FSM(팀원 A)과의 통신 인터페이스
    // ==========================================================
    // [Write 전용 핀] - 결제 시퀀스 시작
    input wire req_write,           // 결제 데이터 쓰기 시작 펄스
    input wire [31:0] order_info,   // 보낼 음료 정보
    input wire [31:0] money_in,     // 보낼 투입 금액
    output reg done_write,          // 3단 쓰기 콤보 완료 펄스

    // [Read 전용 핀] - 결과 읽기 시퀀스 시작
    input wire req_read,            // 결제 결과 읽기 시작 펄스
    output reg done_read,           // 3단 읽기 콤보 완료 펄스
    output reg [31:0] status_out,   // 읽어온 결제 상태 (0,1,2,3)
    output reg [31:0] inventory_out,// 읽어온 재고 현황
    output reg [31:0] change_out,   // 읽어온 반환 잔돈

    // ==========================================================
    // 3. AXI4-Lite 채널 인터페이스
    // ==========================================================
    // [AW] Write Address Channel
    output reg [31:0] M_AXI_AWADDR,
    output reg M_AXI_AWVALID,
    input wire M_AXI_AWREADY,

    // [W] Write Data Channel
    output reg [31:0] M_AXI_WDATA,
    output wire [3:0] M_AXI_WSTRB,
    output reg M_AXI_WVALID,
    input wire M_AXI_WREADY,

    // [B] Write Response Channel
    input wire [1:0] M_AXI_BRESP,
    input wire M_AXI_BVALID,
    output reg M_AXI_BREADY,

    // [AR] Read Address Channel
    output reg [31:0] M_AXI_ARADDR,
    output reg M_AXI_ARVALID,
    input wire M_AXI_ARREADY,

    // [R] Read Data Channel
    input wire [31:0] M_AXI_RDATA,
    input wire [1:0] M_AXI_RRESP,
    input wire M_AXI_RVALID,
    output reg M_AXI_RREADY
);

    // 32비트(4바이트) 데이터를 꽉 채워서 보낸다는 의미 (1111)
    assign M_AXI_WSTRB = 4'b1111; 

    // ==========================================================
    // 상태 머신 (FSM) 및 제어 변수 선언
    // ==========================================================
    localparam S_IDLE    = 3'd0;
    // 쓰기(Write) 전용 상태
    localparam S_WR_AWW  = 3'd1; // AW와 W 채널 동시에 VALID 쏘는 상태
    localparam S_WR_B    = 3'd2; // B 채널 영수증 기다리는 상태
    localparam S_WR_DONE = 3'd3; // 쓰기 콤보 완료 보고
    // 읽기(Read) 전용 상태
    localparam S_RD_AR   = 3'd4; // AR 채널 VALID 쏘는 상태
    localparam S_RD_R    = 3'd5; // R 채널 데이터 기다리는 상태
    localparam S_RD_DONE = 3'd6; // 읽기 콤보 완료 보고

    reg [2:0] state;
    reg [1:0] step;      // 콤보 카운터 (0번, 1번, 2번 주소 쏠 차례 기억용)
    
    // AW채널과 W채널이 병렬로 끝났는지 확인하기 위한 플래그 (규칙 1, 2 준수)
    reg aw_done; 
    reg w_done;

    // ==========================================================
    // 메인 컨트롤 로직 (단일 always 블록 - 가장 안전한 AXI 코딩법)
    // ==========================================================
    always @(posedge M_AXI_ACLK or negedge M_AXI_ARESETN) begin
        if (!M_AXI_ARESETN) begin
            state <= S_IDLE;
            step <= 2'd0;
            aw_done <= 1'b0; w_done <= 1'b0;
            
            // 모든 AXI 출력 핀 및 유저 핀 0으로 초기화
            M_AXI_AWVALID <= 1'b0; M_AXI_WVALID <= 1'b0; M_AXI_BREADY <= 1'b0;
            M_AXI_ARVALID <= 1'b0; M_AXI_RREADY <= 1'b0;
            M_AXI_AWADDR <= 32'd0; M_AXI_WDATA <= 32'd0; M_AXI_ARADDR <= 32'd0;
            
            done_write <= 1'b0; done_read <= 1'b0;
            status_out <= 32'd0; inventory_out <= 32'd0; change_out <= 32'd0;
        end 
        else begin
            case (state)
                // ----------------------------------------------------
                // [대기 상태] 팀원 A의 명령을 기다림
                // ----------------------------------------------------
                S_IDLE: begin
                    done_write <= 1'b0;
                    done_read  <= 1'b0;
                    aw_done <= 1'b0; 
                    w_done <= 1'b0;

                    if (req_write) begin
                        state <= S_WR_AWW;
                        step <= 2'd0; // 0번째 스텝부터 시작
                        M_AXI_AWVALID <= 1'b1; M_AXI_WVALID <= 1'b1;
                        M_AXI_AWADDR <= 32'h04;       // 1타: 0x04 (REG_ORDER)
                        M_AXI_WDATA  <= order_info;   //      음료 정보 전송
                    end 
                    else if (req_read) begin
                        state <= S_RD_AR;
                        step <= 2'd0;
                        M_AXI_ARVALID <= 1'b1;
                        M_AXI_ARADDR <= 32'h0C;       // 1타: 0x0C (REG_STATUS)
                    end
                end

                // ====================================================
                // [WRITE 시퀀스] 주소와 데이터 병렬 전송
                // ====================================================
                S_WR_AWW: begin
                    // AW 채널 눈치게임 (주소 넘겨주기)
                    if (M_AXI_AWVALID && M_AXI_AWREADY) begin
                        M_AXI_AWVALID <= 1'b0; 
                        aw_done <= 1'b1;
                    end
                    // W 채널 눈치게임 (데이터 넘겨주기)
                    if (M_AXI_WVALID && M_AXI_WREADY) begin
                        M_AXI_WVALID <= 1'b0; 
                        w_done <= 1'b1;
                    end

                    // AW와 W가 모두 완료되었다면 영수증(B채널) 받을 준비!
                    if ((aw_done || (M_AXI_AWVALID && M_AXI_AWREADY)) &&
                        (w_done  || (M_AXI_WVALID  && M_AXI_WREADY))) begin
                        
                        state <= S_WR_B;
                        M_AXI_BREADY <= 1'b1; // 슬레이브야 영수증 줘!
                        aw_done <= 1'b0; w_done <= 1'b0; // 다음 스텝을 위해 초기화
                    end
                end

                S_WR_B: begin
                    if (M_AXI_BVALID && M_AXI_BREADY) begin
                        M_AXI_BREADY <= 1'b0;
                        
                        // 영수증 받았으니 다음 스텝 진행
                        if (step == 2'd0) begin // 다음은 1번 스텝
                            step <= 2'd1;
                            state <= S_WR_AWW;
                            M_AXI_AWVALID <= 1'b1; M_AXI_WVALID <= 1'b1;
                            M_AXI_AWADDR <= 32'h08;     // 2타: 0x08 (REG_MONEY)
                            M_AXI_WDATA  <= money_in;   //      투입 금액 전송
                        end 
                        else if (step == 2'd1) begin // 다음은 2번 스텝
                            step <= 2'd2;
                            state <= S_WR_AWW;
                            M_AXI_AWVALID <= 1'b1; M_AXI_WVALID <= 1'b1;
                            M_AXI_AWADDR <= 32'h00;     // 3타: 0x00 (REG_CTRL)
                            M_AXI_WDATA  <= 32'd1;      //      트리거 비트 발사!
                        end 
                        else begin // 3타 콤보 끝!
                            state <= S_WR_DONE;
                            done_write <= 1'b1; // 팀원 A에게 쓰기 끝났다고 보고
                        end
                    end
                end

                S_WR_DONE: begin
                    done_write <= 1'b0;
                    state <= S_IDLE; // 쉬러 돌아감
                end

                // ====================================================
                // [READ 시퀀스] 주소 먼저 주고 데이터 받기
                // ====================================================
                S_RD_AR: begin
                    // AR 채널 눈치게임
                    if (M_AXI_ARVALID && M_AXI_ARREADY) begin
                        M_AXI_ARVALID <= 1'b0;
                        M_AXI_RREADY <= 1'b1; // 주소 넘겼으니 데이터 받을 준비!
                        state <= S_RD_R;
                    end
                end

                S_RD_R: begin
                    if (M_AXI_RVALID && M_AXI_RREADY) begin
                        M_AXI_RREADY <= 1'b0; // 포장된 데이터 수령 완료
                        
                        // 어떤 주소의 데이터인지에 따라 내 레지스터에 분배 저장
                        if (step == 2'd0) status_out <= M_AXI_RDATA;
                        else if (step == 2'd1) inventory_out <= M_AXI_RDATA;
                        else if (step == 2'd2) change_out <= M_AXI_RDATA;

                        // 다음 스텝 진행
                        if (step == 2'd0) begin
                            step <= 2'd1;
                            state <= S_RD_AR;
                            M_AXI_ARVALID <= 1'b1;
                            M_AXI_ARADDR <= 32'h10; // 2타: 0x10 (REG_INVEN)
                        end 
                        else if (step == 2'd1) begin
                            step <= 2'd2;
                            state <= S_RD_AR;
                            M_AXI_ARVALID <= 1'b1;
                            M_AXI_ARADDR <= 32'h14; // 3타: 0x14 (REG_CHANGE)
                        end 
                        else begin // 3타 콤보 끝!
                            state <= S_RD_DONE;
                            done_read <= 1'b1; // 팀원 A에게 읽기 끝났다고 보고
                        end
                    end
                end

                S_RD_DONE: begin
                    done_read <= 1'b0;
                    state <= S_IDLE; // 쉬러 돌아감
                end

                default: begin
                    state <= S_IDLE;
                    
                    // 미지의 상태(예: 노이즈로 인한 3'd7)에 빠졌을 때 
                    // 버스가 꼬이지 않도록 모든 통신 깃발을 강제로 내립니다.
                    M_AXI_AWVALID <= 1'b0;
                    M_AXI_WVALID  <= 1'b0;
                    M_AXI_ARVALID <= 1'b0;
                    M_AXI_BREADY  <= 1'b0;
                    M_AXI_RREADY  <= 1'b0;
                    
                    done_write <= 1'b0;
                    done_read  <= 1'b0;
                end
            endcase
        end
    end

endmodule
