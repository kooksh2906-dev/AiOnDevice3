`timescale 1ns / 1ps


module tb_half_adder_behavioral;

    reg a, b;
    wire s, c;

    half_adder_behavioral dut(
        .a(a),
        .b(b),
        .s(s),
        .c(c)
    );

    initial begin
        $display("Time\t a  b | s  c");
        $monitor("%4t\t%b %b | %b %b",$time, a, b, s, c);
            // 입력의 변화
            a = 0; b = 0;   #10;
            a = 0; b = 1;   #10;
            a = 1; b = 0;   #10;
            a = 1; b = 1;   #10;
        $finish;
    end

endmodule


module tb_half_adder_N_bit;

    parameter N = 8;

    reg inc;
    reg [N-1:0] load_data;
    wire [N-1:0] sum;

    half_adder_N_bit #(N) uut(
        .inc(inc),
        .load_data(load_data),
        .sum(sum)
    );

    initial begin
        $display("Time\t      inc\t load_data\t |\tsum");
        $monitor("%0t\t  %b\t %b\t |\t%b",$time, inc, load_data, sum);
        inc = 0; load_data = 8'b0000_0000; #10;
        inc = 1; load_data = 8'b0000_0000; #10;
        inc = 1; load_data = 8'b0000_0001; #10;
        inc = 1; load_data = 8'b0000_1111; #10;
        inc = 1; load_data = 8'b1111_1111; #10;
        inc = 0; load_data = 8'b1010_1010; #10;
        inc = 1; load_data = 8'b1010_1010; #10;
        #10 $finish;
    end
        
endmodule


module tb_full_adder_structural;
    
    // 입력 신호
    reg a, b, cin;
    
    // 출력 신호
    wire sum, carry;

    full_adder_structual dut(
        .a(a),
        .b(b),
        .cin(cin),
        .sum(sum),
        .carry(carry)
    );
    
    // 테스트 시나리오
    initial begin
        $display("A B Cin | Sum Carry");
        $display("-------------------");

        // 8가지만 조합 테스트
        a = 0; b = 0; cin = 0;  #10;
        $display("%b %b %b | %b %b",a, b, cin, sum, carry);

        a = 0; b = 0; cin = 1;  #10;
        $display("%b %b %b | %b %b",a, b, cin, sum, carry);

        a = 0; b = 1; cin = 0;  #10;
        $display("%b %b %b | %b %b",a, b, cin, sum, carry);

        a = 0; b = 1; cin = 1;  #10;
        $display("%b %b %b | %b %b",a, b, cin, sum, carry);

        a = 1; b = 0; cin = 0;  #10;
        $display("%b %b %b | %b %b",a, b, cin, sum, carry);

        a = 1; b = 0; cin = 1;  #10;
        $display("%b %b %b | %b %b",a, b, cin, sum, carry);

        a = 1; b = 1; cin = 0;  #10;
        $display("%b %b %b | %b %b",a, b, cin, sum, carry);

        a = 1; b = 1; cin = 1;  #10;
        $display("%b %b %b | %b %b",a, b, cin, sum, carry);

        $finish;
    end

endmodule


module tb_full_adder;

    reg a, b, cin;
    wire sum, carry;

    parameter USE_DATAFLOW = 0;

    generate
        if(USE_DATAFLOW == 0) begin : behav
            full_adder_behavioral uut(
                .a(a),
                .b(b),
                .cin(cin),
                .sum(sum),
                .carry(carry)
            );            
        end 
        else begin : dataf
            full_adder_dataflow uut(
                .a(a),
                .b(b),
                .cin(cin),
                .sum(sum),
                .carry(carry)
            );            
        end
    endgenerate

    initial begin
        a = 0; b = 0; cin = 0;
        repeat (8) begin
            #10;
            {a, b, cin} = {a, b, cin} + 1;
        end
        #10;
        $finish;
    end

    initial begin
        $display("Time\t a b cin | sum carry");
        $monitor("%0dns\t %b %b %b | %b %b", $time, a, b, cin, sum, carry);
    end
    
endmodule


module tb_fadder_4bit_structural;

    reg [3:0] a, b;
    reg cin;
    wire [3:0] sum;
    wire carry;

    fadder_4bit_structual uut(
        .a(a),
        .b(b),
        .cin(cin),
        .sum(sum),
        .carry(carry)
    );

    initial begin
        // 테스트
        cin = 0; a = 4'b0000; b = 4'b0000; #10;
        cin = 0; a = 4'b0001; b = 4'b0001; #10;
        cin = 1; a = 4'b0010; b = 4'b0011; #10;
        cin = 0; a = 4'b1111; b = 4'b0001; #10;
        cin = 1; a = 4'b1010; b = 4'b0101; #10;
        cin = 0; a = 4'b1111; b = 4'b1111; #10;
        cin = 1; a = 4'b1111; b = 4'b1111; #10;
        
        $finish;
    end
    
endmodule

// N-bit fadder testbench
module tb_n_bit_adder;

    // 파라메터 맞춰야 함 !!
    parameter N = 8;

    reg [N-1:0] a, b;
    reg cin;
    wire [N-1:0] sum;
    wire carry;

    n_bit_adder_structural #(.N(N)) uut(
        .a(a),
        .b(b),
        .cin(cin),
        .sum(sum),
        .carry(carry)
    );

    initial begin
        // 초기값
        a = 0; b = 0; cin = 0;
        #10;     // 10나노 이후에

        // (decimal) 100 + 50 = 150 , 파라미터가 8이니깐 8비트 짜리
        a = 8'd100; b = 8'd50; cin = 0;
        #10;

        // 200 + 100 -> 8비트 초과 캐리 발생
        a = 8'd200; b = 8'd100; cin = 0;
        #10;

        // 모든 비트가 1일때(최대값)
        a = {N{1'b1}};  // N비트를 모두 1로 채움
        b = {N{1'b1}};
        cin = 1;
        #10;

        repeat (5) begin
            #10;
            a = $random;
            b = $random;
            cin = $random % 2;
        end
        #20;
        $finish;
    end
    
endmodule


module tb_fadd_sub_4bit;

    reg [3:0] a, b;      // 입력값
    reg s;               // 연산 선택 (0: 덧셈, 1: 뺄셈)
    wire [3:0] sum;      // 출력 합/차
    wire carry;          // 캐리/빌림 출력

    // 테스트할 모듈 인스턴스화
    fadd_sub_4bit_structural uut (
        .a(a),
        .b(b),
        .s(s),
        .sum(sum),
        .carry(carry)
    );

    integer i, j;

    initial begin
        // 시뮬레이션 시작 메시지
        $display("Time\t a    b    s | sum  carry");
        $monitor("%0dns\t %b %b %b | %b   %b", $time, a, b, s, sum, carry);

        // 모든 조합 테스트 (a,b는 4비트, s는 0과 1)
        for (i = 0; i < 16; i = i + 1) begin
            for (j = 0; j < 16; j = j + 1) begin
                a = i;
                b = j;

                // 덧셈 테스트 (s=0)
                s = 0;
                #10;

                // 뺄셈 테스트 (s=1)
                s = 1;
                #10;
            end
        end

        $finish;  // 시뮬레이션 종료
    end

endmodule



// 0618

module tb_comparator;

    reg a, b;
    wire equal, greator, less;

    comparator_dataflow uut(
        .a(a), .b(b),
        .equal(equal), .greator(greator), .less(less)
    );

    initial begin
        $display("Time\t a  b | equal  greator  less");
        $monitor("%4t\t %b  %b | %b  %b  %b",$time, a, b, equal, greator, less);

        a = 0; b = 0; #10;  //equal : 1
        a = 0; b = 1; #10;
        a = 1; b = 0; #10;
        a = 1; b = 1; #10;

        $finish;
    end
    
endmodule


module tb_comparator_4bit;

    reg [3:0] a, b;
    wire equal, greator, less;

    comparator_Nbit #(.N(4)) dut(
        .a(a), .b(b),
        .equal(equal), .greator(greator), .less(less) 
    );

    integer i, j;

    initial begin
        for (i = 0; i < 16; i = i + 1) begin
            for (j = 0; j < 16; j = j + 1) begin
                a = i;
                b = j;
                #5;         // 신호 안정화 대기
            end
        end
        $finish;
    end
    
endmodule

module tb_encoder_4_2;

    reg [3:0] signal;
    wire [1:0] code;

    encoder_4_2 uut(
        .signal(signal),
        .code(code)
    );
    
    initial begin
        signal = 4'b0000;
        // 각 입력을 하나씩 켜서 테스트
        #10 signal = 4'b0001;       // 00
        #10 signal = 4'b0010;       // 01
        #10 signal = 4'b0100;       // 10
        #10 signal = 4'b1000;       // 11

        #10 signal = 4'b0000;       // 디폴트 조건 때문에 11
        #10 signal = 4'b0011;       // 두개의 신호가 있기 때문에 디폴트로 11

        #10 $finish;
    end
endmodule

// decoder

module tb_decoder_2_4;

    reg [1:0] code;
    wire [3:0] signal;

    decoder_2_4 uut(
        .code(code),
        .signal(signal)
    );
    
    initial begin
        code = 2'b00;   // 초기화

        // 각 입력을 하나씩 켜서 테스트
        #10 code = 2'b00;       // 00
        #10 code = 2'b01;       // 01
        #10 code = 2'b10;       // 10
        #10 code = 2'b11;       // 11

        #10 $finish;
    end
endmodule

// FND

// module tb_mux_8_1;

//     reg [7:0] d;
//     reg [2:0] s;
//     wire f;

//     mux_8_1 uut(
//         .d(d), .s(s), .f(f)
//     );

//     initial begin
//         d = 8'b11001010;

//         s = 3'b000; #10;
//         s = 3'b001; #10;
//         s = 3'b010; #10;
//         s = 3'b011; #10;
//         s = 3'b100; #10;
//         s = 3'b101; #10;
//         s = 3'b110; #10;
//         s = 3'b111; #10;

//         $finish;
//     end
// endmodule

module tb_demux_1_4;

    reg d;                // 입력
    reg [1:0] s;          // 선택 신호
    wire [3:0] f;         // 출력

    // 테스트할 대상 모듈 인스턴스화
    demux_1_4 uut (
        .d(d),
        .s(s),
        .f(f)
    );

    initial begin
        $display("Time\t d s\t|\tf");
        $monitor("%4t\t %b %b\t|\t%b", $time, d, s, f);

        // 테스트 시나리오 시작
        d = 1;

        s = 2'b00; #10;  // f = 0001
        s = 2'b01; #10;  // f = 0010
        s = 2'b10; #10;  // f = 0100
        s = 2'b11; #10;  // f = 1000

        d = 0;           // 입력을 0으로 바꾸고 확인
        s = 2'b00; #10;  // f = 0000
        s = 2'b01; #10;  // f = 0000
        s = 2'b10; #10;  // f = 0000
        s = 2'b11; #10;  // f = 0000

        $finish;
    end

endmodule


module tb_bin_to_bcd;

    reg [11:0] bin;
    wire [15:0] bcd;

    bin_to_dec uut(
        .bin(bin),
        .bcd(bcd)
    );

    initial begin

        bin = 12'b0;
        // 계산기에 decimal 값으로 찍어보면 나옴
        #10 bin = 12'b0000_0000_0000;  // 0, 빈값
        #10 bin = 12'b0000_0000_0001;  // 1
        #10 bin = 12'b0000_0000_1001;  // 9
        #10 bin = 12'b0000_0001_0100;  // 20
        #10 bin = 12'b0000_1011_1001;  // 185
        #10 bin = 12'b1011_0110_1101;  // 2925 (예시값)
        #10 bin = 12'b1111_1111_1111;  // 4095 (최대값)

        #20 $stop;
    end
endmodule