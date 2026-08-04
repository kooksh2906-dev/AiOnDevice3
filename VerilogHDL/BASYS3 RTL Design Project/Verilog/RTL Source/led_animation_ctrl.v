`timescale 1ns / 1ps

module led_animation_ctrl(
    input clk,
    input reset_p,

    input flag_DONE,

    output reg [15:0] led,
    output reg flag_cplt_DONE
);

    //==================================================
    // 상태 정의
    //==================================================

    parameter IDLE = 2'd0;
    parameter RUN  = 2'd1;
    parameter DONE = 2'd2;

    reg [1:0] state;

    //==================================================
    // flag_DONE 상승엣지 검출
    //==================================================

    reg flag_DONE_d;

    wire flag_DONE_pedge;

    always @(posedge clk or posedge reset_p)
    begin
        if(reset_p)
            flag_DONE_d <= 0;
        else
            flag_DONE_d <= flag_DONE;
    end

    assign flag_DONE_pedge = flag_DONE & ~flag_DONE_d;

    //==================================================
    // 카운터
    //==================================================

    reg [31:0] delay_cnt;
    reg [4:0] led_cnt;

    // 시뮬레이션용
    // parameter DELAY_MAX = 10;

    // FPGA 최종 적용 시
    parameter DELAY_MAX = 50_000_000;

    //==================================================
    // FSM
    //==================================================

    always @(posedge clk or posedge reset_p)
    begin

        if(reset_p)
        begin
            state <= IDLE;

            led <= 16'h0000;

            led_cnt <= 0;
            delay_cnt <= 0;

            flag_cplt_DONE <= 0;
        end

        else
        begin

            case(state)

            //--------------------------------------------------
            // IDLE
            //--------------------------------------------------

            IDLE:
            begin

                led <= 16'h0000;

                led_cnt <= 0;
                delay_cnt <= 0;

                flag_cplt_DONE <= 0;

                if(flag_DONE_pedge)
                    state <= RUN;

            end

            //--------------------------------------------------
            // RUN
            //--------------------------------------------------

            RUN:
            begin

                if(delay_cnt >= DELAY_MAX)
                begin

                    delay_cnt <= 0;
                    //
                    led <= (16'h0001 << (led_cnt + 1)) - 1;
                    if(led_cnt >= 15)
                    begin
                        state <= DONE;
                    end
                    else
                    begin
                        led_cnt <= led_cnt + 1;
                    end

                end
                else
                begin
                    delay_cnt <= delay_cnt + 1;
                end

            end

            //--------------------------------------------------
            // DONE
            //--------------------------------------------------

            DONE:
            begin

                led <= 16'hFFFF;

                flag_cplt_DONE <= 1;
                
                state <= IDLE;

            end

            //--------------------------------------------------
            // 예외 처리
            //--------------------------------------------------

            default:
            begin

                state <= IDLE;

                led <= 16'h0000;

                led_cnt <= 0;
                delay_cnt <= 0;

                flag_cplt_DONE <= 0;

            end

            endcase

        end

    end

endmodule