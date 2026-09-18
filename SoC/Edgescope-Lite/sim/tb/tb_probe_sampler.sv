`timescale 1ns/1ps

module tb_probe_sampler;

    localparam time CLK_PERIOD = 10ns;

    logic        clk_i;
    logic        rst_ni;
    logic [7:0]  probe_i;
    logic        enable_i;
    logic        soft_clear_i;
    logic [1:0]  divider_sel_i;
    logic [7:0]  channel_mask_i;
    logic [7:0]  sample_data_o;
    logic        sample_valid_o;
    logic [31:0] sample_count_o;

    int unsigned checks;
    int unsigned errors;

    probe_sampler dut (
        .clk_i           (clk_i),
        .rst_ni          (rst_ni),
        .probe_i         (probe_i),
        .enable_i        (enable_i),
        .soft_clear_i    (soft_clear_i),
        .divider_sel_i   (divider_sel_i),
        .channel_mask_i  (channel_mask_i),
        .sample_data_o   (sample_data_o),
        .sample_valid_o  (sample_valid_o),
        .sample_count_o  (sample_count_o)
    );

    initial clk_i = 1'b0;
    always #(CLK_PERIOD / 2) clk_i = ~clk_i;

    task automatic check_true(
        input logic condition,
        input string message
    );
        checks++;
        if (!condition) begin
            errors++;
            $error("[%0t] %s", $time, message);
        end
    endtask

    task automatic apply_reset;
        begin
            rst_ni         = 1'b0;
            enable_i       = 1'b0;
            soft_clear_i   = 1'b0;
            divider_sel_i  = 2'b00;
            channel_mask_i = 8'hFF;
            probe_i        = 8'h00;

            repeat (3) @(posedge clk_i);
            #1;
            check_true(sample_valid_o == 1'b0,
                       "sample_valid_o must be low during reset");
            check_true(sample_count_o == 32'd0,
                       "sample_count_o must be zero during reset");
            check_true(sample_data_o == 8'h00,
                       "sample_data_o must be zero during reset");

            @(negedge clk_i);
            rst_ni = 1'b1;
        end
    endtask

    task automatic pulse_soft_clear;
        begin
            @(negedge clk_i);
            soft_clear_i = 1'b1;
            @(posedge clk_i);
            #1;
            check_true(sample_valid_o == 1'b0,
                       "soft clear must suppress sample_valid_o");
            check_true(sample_count_o == 32'd0,
                       "soft clear must reset sample_count_o");
            check_true(sample_data_o == 8'h00,
                       "soft clear must reset sample_data_o");
            @(negedge clk_i);
            soft_clear_i = 1'b0;
        end
    endtask

    task automatic test_divider(
        input logic [1:0] divider_sel,
        input int unsigned divider
    );
        int unsigned cycle;
        int unsigned expected_count;
        logic [7:0] expected_sample;
        logic       expected_valid;
        begin
            $display("TEST: divider %0d", divider);
            enable_i       = 1'b0;
            divider_sel_i  = divider_sel;
            channel_mask_i = 8'hA5;
            pulse_soft_clear();

            expected_count  = 0;
            expected_sample = 8'h00;

            @(negedge clk_i);
            enable_i = 1'b1;

            for (cycle = 1; cycle <= divider * 4; cycle++) begin
                probe_i = cycle[7:0] ^ 8'h3C;
                expected_valid = ((cycle % divider) == 0);
                if (expected_valid) begin
                    expected_count++;
                    expected_sample = probe_i & channel_mask_i;
                end

                @(posedge clk_i);
                #1;
                check_true(sample_valid_o == expected_valid,
                           $sformatf("divider %0d valid mismatch at cycle %0d",
                                     divider, cycle));
                check_true(sample_count_o == expected_count,
                           $sformatf("divider %0d count mismatch at cycle %0d",
                                     divider, cycle));
                check_true(sample_data_o == expected_sample,
                           $sformatf("divider %0d data/mask mismatch at cycle %0d",
                                     divider, cycle));

                @(negedge clk_i);
            end

            enable_i = 1'b0;
            probe_i  = 8'hFF;
            repeat (3) begin
                @(posedge clk_i);
                #1;
                check_true(sample_valid_o == 1'b0,
                           "disabled sampler generated sample_valid_o");
                check_true(sample_count_o == expected_count,
                           "disabled sampler changed sample_count_o");
                check_true(sample_data_o == expected_sample,
                           "disabled sampler changed the last sample");
                @(negedge clk_i);
            end
        end
    endtask

    task automatic test_runtime_divider_change;
        begin
            $display("TEST: run-time divider change 8 -> 2");
            enable_i       = 1'b0;
            divider_sel_i  = 2'b11;
            channel_mask_i = 8'hFF;
            pulse_soft_clear();

            @(negedge clk_i);
            enable_i = 1'b1;
            probe_i  = 8'h11;

            repeat (3) begin
                @(posedge clk_i);
                #1;
                check_true(sample_valid_o == 1'b0,
                           "divide-by-8 fired before terminal count");
                @(negedge clk_i);
            end

            divider_sel_i = 2'b01;
            probe_i       = 8'h5A;

            // Configuration-change cycle: divider phase is restarted.
            @(posedge clk_i);
            #1;
            check_true(sample_valid_o == 1'b0,
                       "divider change must restart without a spurious valid");
            @(negedge clk_i);

            // Two complete enabled clocks are required for divide-by-2.
            @(posedge clk_i);
            #1;
            check_true(sample_valid_o == 1'b0,
                       "divide-by-2 fired one clock too early after change");
            @(negedge clk_i);

            @(posedge clk_i);
            #1;
            check_true(sample_valid_o == 1'b1,
                       "divide-by-2 did not fire two clocks after change");
            check_true(sample_data_o == 8'h5A,
                       "sample data was not aligned with changed divider valid");
            check_true(sample_count_o == 32'd1,
                       "sample count incorrect after run-time divider change");
            @(negedge clk_i);

            enable_i = 1'b0;
        end
    endtask

    initial begin
        checks = 0;
        errors = 0;

        apply_reset();
        test_divider(2'b00, 1);
        test_divider(2'b01, 2);
        test_divider(2'b10, 4);
        test_divider(2'b11, 8);
        test_runtime_divider_change();

        pulse_soft_clear();
        check_true(sample_count_o == 32'd0,
                   "final soft clear did not leave count at zero");

        if (errors == 0) begin
            $display("PASS: tb_probe_sampler (%0d checks)", checks);
            $finish;
        end

        $fatal(1, "FAIL: tb_probe_sampler (%0d errors / %0d checks)",
               errors, checks);
    end

endmodule
