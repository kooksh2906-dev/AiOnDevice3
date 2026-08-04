`timescale 1ns / 1ps

module servo_pwm(

    input clk,
    input reset_p,

    input flag_SERVO,
    input flag_CHANGE,

    output reg servo_out,

    output reg flag_cplt_SERVO,
    output reg flag_cplt_CHANGE

);

    //==================================================
    // MG996R PWM
    // 100MHz 기준
    // 20ms = 2,000,000 count
    // 2.0ms = 200,000 count
    // 1.5ms = 150,000 count
    //==================================================

    parameter PERIOD_CNT = 2_000_000;// 20ms

    parameter OPEN_PULSE  = 250_000; // 90도
    parameter CLOSE_PULSE = 150_000; // 0도

    reg [21:0] pwm_cnt;

    reg [17:0] pulse_width;

    always @(posedge clk or posedge reset_p) begin

        if(reset_p)
            pwm_cnt <= 0;

        else if(pwm_cnt >= PERIOD_CNT-1)
            pwm_cnt <= 0;

        else
            pwm_cnt <= pwm_cnt + 1;

    end

    always @(*) begin

        if(pwm_cnt < pulse_width)
            servo_out = 1'b1;
        else
            servo_out = 1'b0;

    end

    //==================================================
    // Servo FSM
    //==================================================

    localparam IDLE         = 3'd0;
    localparam OPEN         = 3'd1;
    localparam OPEN_WAIT    = 3'd2;
    localparam CLOSE        = 3'd3;
    localparam CLOSE_WAIT   = 3'd4;

    reg [2:0] state;

    reg [27:0] wait_cnt;

    // 서보가 OPEN 상태인지 저장
    reg servo_opened;

    // CHANGE 요청은 상승엣지에서 한 번만 처리한다. 입력이 여러 클럭
    // 유지되어도 완료 펄스나 CLOSE 동작이 반복되지 않는다.
    reg flag_CHANGE_d;
    wire flag_CHANGE_rise;

    always @(posedge clk or posedge reset_p) begin
        if(reset_p)
            flag_CHANGE_d <= 1'b0;
        else
            flag_CHANGE_d <= flag_CHANGE;
    end

    assign flag_CHANGE_rise = flag_CHANGE & ~flag_CHANGE_d;

    parameter WAIT_TIME = 100_000_000;
    // 실기 : 100_000_000
    // 시뮬 : 1000

    always @(posedge clk or posedge reset_p) begin

        if(reset_p) begin

            state <= IDLE;

            pulse_width <= CLOSE_PULSE;

            wait_cnt <= 0;

            servo_opened <= 0;

            flag_cplt_SERVO <= 0;
            flag_cplt_CHANGE <= 0;

        end

        else begin

            flag_cplt_SERVO <= 0;
            flag_cplt_CHANGE <= 0;

            case(state)

            //------------------------------------
            // 대기
            //------------------------------------
            IDLE : begin

                wait_cnt <= 0;

                if(flag_SERVO) begin

                    pulse_width <= OPEN_PULSE;
                    state <= OPEN;

                end

                else if(flag_CHANGE_rise) begin

                    // 열린 상태에서는 기존과 동일하게 실제 CLOSE 수행
                    if(servo_opened) begin
                        pulse_width <= CLOSE_PULSE;
                        state <= CLOSE;
                    end

                    // 이미 닫혀 있으면 목표 위치에 도달한 상태이므로
                    // 모터를 재구동하지 않고 즉시 1클럭 완료 응답
                    else begin
                        pulse_width <= CLOSE_PULSE;
                        flag_cplt_CHANGE <= 1'b1;
                        state <= IDLE;
                    end
                end

            end

            //------------------------------------
            // 열기
            //------------------------------------
            OPEN : begin

                wait_cnt <= 0;
                state <= OPEN_WAIT;

            end

            OPEN_WAIT : begin

                if(wait_cnt >= WAIT_TIME) begin

                    servo_opened <= 1'b1;

                    flag_cplt_SERVO <= 1'b1;

                    state <= IDLE;

                end

                else
                    wait_cnt <= wait_cnt + 1;

            end

            //------------------------------------
            // 닫기
            //------------------------------------
            CLOSE : begin

                wait_cnt <= 0;
                state <= CLOSE_WAIT;

            end

            CLOSE_WAIT : begin

                if(wait_cnt >= WAIT_TIME) begin

                    servo_opened <= 1'b0;

                    flag_cplt_CHANGE <= 1'b1;

                    state <= IDLE;

                end

                else
                    wait_cnt <= wait_cnt + 1;

            end

            default : begin

                state <= IDLE;

                pulse_width <= CLOSE_PULSE;

                servo_opened <= 1'b0;
                
                wait_cnt <= 0;

            end

            endcase

        end

    end

endmodule
