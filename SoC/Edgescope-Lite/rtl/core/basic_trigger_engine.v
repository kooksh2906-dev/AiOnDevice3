`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// 모듈명 : Basic Trigger Engine
// -----------------------------------------------------------------------------
// [모듈의 역할]
// Probe Sampler가 전달한 8비트 유효 샘플을 실시간으로 감시하다가,
// 사용자가 설정한 Rising/Falling/Pattern 조건이 만족되는 정확한 샘플에서
// trigger_pulse_o를 발생시키는 Trigger 판정 모듈이다.
//
// [지원 Trigger Mode]
//   2'b00 : Disabled - Trigger 기능 비활성화
//   2'b01 : Rising   - 선택 채널의 0 -> 1 변화 검출
//   2'b10 : Falling  - 선택 채널의 1 -> 0 변화 검출
//   2'b11 : Pattern  - Mask가 적용된 Pattern으로 진입하는 순간 검출
//
// [핵심 설계 특징]
//   1. sample_valid_i가 1인 샘플만 Trigger 판정과 이력 저장에 사용한다.
//   2. ARM 직후 첫 유효 샘플은 Edge 비교 기준으로만 저장한다.
//   3. trigger_pulse_o는 조합 출력이므로 Trigger 샘플과 같은 Cycle에 발생한다.
//   4. Trigger가 한 번 발생하면 CLEAR 또는 새로운 ARM 전까지 재발생하지 않는다.
//   5. rst_ni는 Active-low이지만 clk_i의 상승 에지에서 처리되는 동기식 Reset이다.
//
// [예상 상태 레지스터 수]
//   previous_sample_q  :  8 FF - 직전 유효 샘플
//   history_valid_q    :  1 FF - 직전 샘플 이력의 유효 여부
//   previous_match_q   :  1 FF - 직전 Pattern 일치 여부
//   armed_o            :  1 FF - Trigger 감시 활성 상태
//   triggered_o        :  1 FF - Trigger 발생 완료 상태
//   trigger_count_o    : 32 FF - Reset 이후 누적 Trigger 횟수
//                         -----
//                         총 44 FF
//
// [신호 이름의 접미사]
//   _i : 모듈의 입력 신호
//   _o : 모듈의 출력 신호
//   _q : Flip-Flop에 저장되는 현재 상태
//   _w : wire 형태의 조합 신호
//   _r : always 조합 블록에서 결정되는 reg 형태의 조합 신호
// -----------------------------------------------------------------------------

module basic_trigger_engine (
    // -------------------------------------------------------------------------
    // Clock 및 Reset
    // -------------------------------------------------------------------------
    // 모든 내부 상태 레지스터는 clk_i의 상승 에지에서 갱신된다.
    input  wire        clk_i,

    // Active-low 동기식 Reset:
    // rst_ni가 0인 상태에서 clk_i 상승 에지가 발생해야 Reset이 적용된다.
    input  wire        rst_ni,

    // -------------------------------------------------------------------------
    // Probe Sampler 입력
    // -------------------------------------------------------------------------
    // 현재 검사할 8채널 샘플 데이터.
    input  wire [7:0]  sample_data_i,

    // 현재 sample_data_i가 유효한 샘플임을 알리는 Enable 신호.
    // 0이면 데이터가 바뀌어도 Trigger 판정 및 이전 샘플 이력을 갱신하지 않는다.
    input  wire        sample_valid_i,

    // -------------------------------------------------------------------------
    // 제어 명령
    // -------------------------------------------------------------------------
    // 1 Clock 동안 1이 되는 ARM 명령.
    // 감시를 시작하고 이전 샘플/Pattern 이력을 새로 수집하도록 초기화한다.
    input  wire        arm_i,

    // 1 Clock 동안 1이 되는 CLEAR 명령.
    // 감시 상태와 Trigger 상태를 해제하지만 누적 Trigger Count는 유지한다.
    input  wire        clear_i,

    // -------------------------------------------------------------------------
    // Trigger 설정값
    // -------------------------------------------------------------------------
    // Trigger 종류 선택: Disabled/Rising/Falling/Pattern.
    input  wire [1:0]  mode_i,

    // Rising/Falling Mode에서 검사할 채널 번호(0~7).
    input  wire [2:0]  edge_channel_i,

    // Pattern Mode에서 비교 기준이 되는 8비트 값.
    input  wire [7:0]  pattern_value_i,

    // Pattern 비교에 사용할 비트를 선택하는 Mask.
    // 각 비트가 1이면 비교하고, 0이면 해당 비트를 무시한다.
    input  wire [7:0]  pattern_mask_i,

    // -------------------------------------------------------------------------
    // 상태 및 Trigger 출력
    // -------------------------------------------------------------------------
    // Trigger 조건을 만족한 현재 유효 샘플과 같은 Cycle에 1이 되는 조합 Pulse.
    output wire        trigger_pulse_o,

    // ARM 명령을 받아 Trigger 감시가 활성화되었음을 나타내는 상태.
    output reg         armed_o,

    // ARM 이후 Trigger가 한 번 발생했음을 기억하는 One-shot 상태.
    output reg         triggered_o,

    // 하드웨어 Reset 이후 발생한 Trigger의 누적 횟수.
    output reg  [31:0] trigger_count_o
);

    // -------------------------------------------------------------------------
    // Trigger Mode 상수 정의
    // -------------------------------------------------------------------------
    // mode_i의 2비트 값에 의미 있는 이름을 부여해 case문의 가독성을 높인다.
    // localparam이므로 외부에서 변경할 수 없으며 합성 시 상수로 구현된다.
    localparam [1:0] TRIGGER_DISABLED = 2'b00;
    localparam [1:0] TRIGGER_RISING   = 2'b01;
    localparam [1:0] TRIGGER_FALLING  = 2'b10;
    localparam [1:0] TRIGGER_PATTERN  = 2'b11;

    // -------------------------------------------------------------------------
    // 내부 상태 레지스터
    // -------------------------------------------------------------------------
    // 직전에 수신한 유효 샘플을 저장한다.
    // 현재 샘플과 비교하여 선택 채널의 0->1 또는 1->0 변화를 검출한다.
    reg  [7:0] previous_sample_q;

    // previous_sample_q 안에 비교 가능한 유효 이력이 있는지를 표시한다.
    // ARM 직후에는 0이므로 첫 유효 샘플만으로 가짜 Edge가 발생하지 않는다.
    reg        history_valid_q;

    // 직전 유효 샘플이 Masked Pattern과 일치했는지를 저장한다.
    // 현재는 일치하고 직전에는 불일치할 때만 Pattern '진입'으로 판단한다.
    reg        previous_match_q;

    // -------------------------------------------------------------------------
    // 현재 샘플에 대한 조합 Trigger 조건
    // -------------------------------------------------------------------------
    // 현재 샘플의 Masked Pattern 일치 여부.
    wire current_match_w;

    // 현재 샘플에서 선택 채널의 Rising/Falling 발생 여부.
    wire rising_condition_w;
    wire falling_condition_w;

    // 현재 샘플이 Pattern 불일치 상태에서 일치 상태로 진입했는지 여부.
    wire pattern_condition_w;

    // mode_i에 따라 위 세 조건 중 하나를 선택한 최종 조건.
    // always @(*)에서 할당하므로 reg로 선언됐지만 Flip-Flop은 생성되지 않는다.
    reg  selected_condition_r;

    // -------------------------------------------------------------------------
    // Masked Pattern 비교
    // -------------------------------------------------------------------------
    // Mask가 1인 비트만 남긴 뒤 현재 Sample과 설정 Pattern을 비교한다.
    //
    // 예) sample=8'hAF, value=8'hA5, mask=8'hF0인 경우
    //     AF & F0 = A0, A5 & F0 = A0이므로 현재 Pattern은 일치한다.
    assign current_match_w =
        ((sample_data_i   & pattern_mask_i) ==
         (pattern_value_i & pattern_mask_i));

    // -------------------------------------------------------------------------
    // Rising Edge 조건
    // -------------------------------------------------------------------------
    // ① 비교 가능한 이전 샘플 이력이 존재하고,
    // ② 선택 채널의 이전 값이 0이며,
    // ③ 선택 채널의 현재 값이 1이면 Rising Edge로 판정한다.
    assign rising_condition_w =
        history_valid_q &&
        !previous_sample_q[edge_channel_i] &&
         sample_data_i[edge_channel_i];

    // -------------------------------------------------------------------------
    // Falling Edge 조건
    // -------------------------------------------------------------------------
    // ① 비교 가능한 이전 샘플 이력이 존재하고,
    // ② 선택 채널의 이전 값이 1이며,
    // ③ 선택 채널의 현재 값이 0이면 Falling Edge로 판정한다.
    assign falling_condition_w =
        history_valid_q &&
         previous_sample_q[edge_channel_i] &&
        !sample_data_i[edge_channel_i];

    // -------------------------------------------------------------------------
    // Pattern 진입 조건
    // -------------------------------------------------------------------------
    // ① mask=0이면 모든 입력이 항상 일치하므로 Trigger를 강제로 금지하고,
    // ② 현재 샘플은 Pattern과 일치하며,
    // ③ 직전 유효 샘플은 Pattern과 일치하지 않았을 때만 Trigger 조건이 된다.
    //
    // current_match_w만 사용하면 Pattern이 유지되는 매 유효 샘플마다 조건이
    // 참이 된다. !previous_match_q를 함께 사용하면 불일치->일치 진입 순간만
    // 검출하는 Edge Detector 형태가 된다.
    assign pattern_condition_w =
        (pattern_mask_i != 8'b0) &&
         current_match_w &&
        !previous_match_q;

    // -------------------------------------------------------------------------
    // Trigger Mode 선택 MUX
    // -------------------------------------------------------------------------
    // 현재 mode_i에 대응하는 Trigger 조건 하나를 selected_condition_r로
    // 전달한다. 모든 분기에서 값을 할당하므로 Latch는 생성되지 않는다.
    always @(*) begin
        case (mode_i)
            // 선택 채널의 0->1 변화 조건 선택.
            TRIGGER_RISING:
                selected_condition_r = rising_condition_w;

            // 선택 채널의 1->0 변화 조건 선택.
            TRIGGER_FALLING:
                selected_condition_r = falling_condition_w;

            // Masked Pattern의 불일치->일치 진입 조건 선택.
            TRIGGER_PATTERN:
                selected_condition_r = pattern_condition_w;

            // Disabled Mode에서는 입력 상태와 관계없이 Trigger 금지.
            TRIGGER_DISABLED:
                selected_condition_r = 1'b0;

            // X/Z 또는 예외적인 Mode 값에서도 안전하게 Trigger 금지.
            default:
                selected_condition_r = 1'b0;
        endcase
    end

    // -------------------------------------------------------------------------
    // 최종 Trigger Pulse 생성
    // -------------------------------------------------------------------------
    // 아래 조건을 모두 만족할 때만 trigger_pulse_o가 1이 된다.
    //
    //   armed_o             : ARM 상태에서 감시 중
    //   !triggered_o        : 이번 ARM 구간에서 아직 Trigger되지 않음
    //   !arm_i / !clear_i   : ARM/CLEAR 명령 Cycle에는 Trigger 금지
    //   sample_valid_i      : 현재 sample_data_i가 유효한 샘플
    //   selected_condition_r: 선택 Mode의 Trigger 조건 만족
    //
    // trigger_pulse_o를 FF로 저장하지 않고 조합 출력으로 만든 이유는
    // Trigger 조건을 만족한 sample_data_i와 같은 Cycle에 Pulse를 내보내
    // Circular Trace Buffer가 해당 데이터를 Trigger Sample로 저장하게 하기 위함이다.
    assign trigger_pulse_o =
        armed_o              &&
       !triggered_o          &&
       !arm_i                &&
       !clear_i              &&
        sample_valid_i       &&
        selected_condition_r;

    // -------------------------------------------------------------------------
    // 순차 상태 갱신
    // -------------------------------------------------------------------------
    // clk_i 상승 에지마다 아래 우선순위로 상태를 갱신한다.
    //
    //   1순위 : 동기식 Reset
    //   2순위 : Clear
    //   3순위 : Arm
    //   4순위 : 일반 Sample 처리
    //
    // if - else if 구조이므로 같은 Cycle에 여러 제어 입력이 1이어도
    // 위에 적힌 우선순위가 높은 동작 하나만 수행된다.
    always @(posedge clk_i) begin
        // Active-low 동기식 Reset:
        // rst_ni=0인 상태에서 clk_i 상승 에지가 들어오면 모든 상태를 초기화한다.
        if (!rst_ni) begin
            previous_sample_q <= 8'b0;
            history_valid_q   <= 1'b0;
            previous_match_q  <= 1'b0;
            armed_o           <= 1'b0;
            triggered_o       <= 1'b0;
            trigger_count_o   <= 32'b0;
        end

        // Clear:
        // 현재 ARM/Trigger 상태와 비교 이력을 제거하여 Idle 상태로 돌아간다.
        // Trigger Count는 Reset 이후 누적값이므로 Clear에서 지우지 않는다.
        else if (clear_i) begin
            previous_sample_q <= 8'b0;
            history_valid_q   <= 1'b0;
            previous_match_q  <= 1'b0;
            armed_o           <= 1'b0;
            triggered_o       <= 1'b0;

            // 자기 자신의 값을 다시 대입하여 Count를 그대로 유지한다.
            // 순차회로에서는 이 문장을 생략해도 값이 유지되지만 의도를 명시했다.
            trigger_count_o   <= trigger_count_o;
        end

        // Arm:
        // Trigger 감시를 시작하고 이전 실행의 비교 이력과 Trigger 상태를 지운다.
        // history_valid_q=0이므로 ARM 이후 첫 유효 샘플은 기준값으로만 저장된다.
        else if (arm_i) begin
            previous_sample_q <= 8'b0;
            history_valid_q   <= 1'b0;
            previous_match_q  <= 1'b0;
            armed_o           <= 1'b1;
            triggered_o       <= 1'b0;

            // ARM은 새로운 측정을 시작하지만 누적 Trigger Count는 유지한다.
            trigger_count_o   <= trigger_count_o;
        end

        // Reset/Clear/Arm 명령이 없는 일반 동작 구간.
        else begin
            // 조합 논리에서 현재 샘플의 Trigger가 검출된 경우,
            // 이 Clock Edge에서 Trigger 완료 상태를 저장하고 Count를 1 증가시킨다.
            //
            // Non-blocking assignment(<=)이므로 우변은 Clock Edge 직전 값을 사용한다.
            if (trigger_pulse_o) begin
                triggered_o     <= 1'b1;
                trigger_count_o <= trigger_count_o + 32'd1;
            end

            // 다음 세 조건을 모두 만족할 때만 현재 샘플을 이력으로 저장한다.
            //   armed_o        : ARM 상태
            //   !triggered_o   : 아직 Trigger 전
            //   sample_valid_i : 현재 샘플이 유효함
            //
            // Disarm 상태에서는 불필요한 이력을 수집하지 않는다.
            // Trigger 발생 후에는 Clear 또는 새로운 Arm 전까지 이력을 고정한다.
            if (armed_o && !triggered_o && sample_valid_i) begin
                // 다음 유효 샘플의 Edge 비교에 사용할 현재 샘플 저장.
                previous_sample_q <= sample_data_i;

                // 이제부터 유효한 이전 샘플이 존재함을 표시.
                history_valid_q   <= 1'b1;

                // 다음 Pattern 진입 판정에 사용할 현재 일치 상태 저장.
                previous_match_q  <= current_match_w;
            end
        end
    end

endmodule