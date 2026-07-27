`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// Testbench for basic_trigger_engine
// -----------------------------------------------------------------------------
// Verilog-2001 self-checking testbench.
//
// Covered behavior:
//   1. Synchronous active-low reset
//   2. No trigger while disarmed
//   3. No edge trigger on the first valid sample after ARM
//   4. Selected-channel rising and falling edge triggers
//   5. Unselected-channel changes are ignored
//   6. sample_valid_i gates both trigger detection and sample history
//   7. Masked pattern comparison and pattern-entry trigger
//   8. No retrigger while a pattern remains matched
//   9. Zero pattern mask disables pattern triggering
//  10. trigger_pulse_o is aligned with the triggering sample
//  11. Trigger pulse deasserts after the trigger-capture clock edge
//  12. No retrigger before CLEAR
//  13. CLEAR followed by ARM enables another trigger
//  14. trigger_count_o increments exactly once per trigger
// -----------------------------------------------------------------------------

module tb_basic_trigger_engine;

    localparam [1:0] TRIGGER_DISABLED = 2'b00;
    localparam [1:0] TRIGGER_RISING   = 2'b01;
    localparam [1:0] TRIGGER_FALLING  = 2'b10;
    localparam [1:0] TRIGGER_PATTERN  = 2'b11;

    localparam integer CLOCK_PERIOD_NS = 10;

    reg         clk_i;
    reg         rst_ni;
    reg  [7:0]  sample_data_i;
    reg         sample_valid_i;
    reg         arm_i;
    reg         clear_i;
    reg  [1:0]  mode_i;
    reg  [2:0]  edge_channel_i;
    reg  [7:0]  pattern_value_i;
    reg  [7:0]  pattern_mask_i;

    wire        trigger_pulse_o;
    wire        armed_o;
    wire        triggered_o;
    wire [31:0] trigger_count_o;

    integer test_count;
    integer error_count;
    integer expected_trigger_count;

    basic_trigger_engine dut (
        .clk_i             (clk_i),
        .rst_ni            (rst_ni),
        .sample_data_i     (sample_data_i),
        .sample_valid_i    (sample_valid_i),
        .arm_i             (arm_i),
        .clear_i           (clear_i),
        .mode_i            (mode_i),
        .edge_channel_i    (edge_channel_i),
        .pattern_value_i   (pattern_value_i),
        .pattern_mask_i    (pattern_mask_i),
        .trigger_pulse_o   (trigger_pulse_o),
        .armed_o           (armed_o),
        .triggered_o       (triggered_o),
        .trigger_count_o   (trigger_count_o)
    );

    initial begin
        clk_i = 1'b0;
    end

    always #(CLOCK_PERIOD_NS / 2) clk_i = ~clk_i;

    // -------------------------------------------------------------------------
    // Common check tasks
    // -------------------------------------------------------------------------

    task check_1bit;
        input                    actual;
        input                    expected;
        input [8*96-1:0]         check_name;
        begin
            test_count = test_count + 1;
            if (actual !== expected) begin
                error_count = error_count + 1;
                $display("[%0t] FAIL: %0s, expected=%b, actual=%b",
                         $time, check_name, expected, actual);
            end
            else begin
                $display("[%0t] PASS: %0s", $time, check_name);
            end
        end
    endtask

    task check_8bit;
        input [7:0]              actual;
        input [7:0]              expected;
        input [8*96-1:0]         check_name;
        begin
            test_count = test_count + 1;
            if (actual !== expected) begin
                error_count = error_count + 1;
                $display("[%0t] FAIL: %0s, expected=0x%02h, actual=0x%02h",
                         $time, check_name, expected, actual);
            end
            else begin
                $display("[%0t] PASS: %0s", $time, check_name);
            end
        end
    endtask

    task check_32bit;
        input [31:0]             actual;
        input [31:0]             expected;
        input [8*96-1:0]         check_name;
        begin
            test_count = test_count + 1;
            if (actual !== expected) begin
                error_count = error_count + 1;
                $display("[%0t] FAIL: %0s, expected=%0d, actual=%0d",
                         $time, check_name, expected, actual);
            end
            else begin
                $display("[%0t] PASS: %0s", $time, check_name);
            end
        end
    endtask

    // ARM and CLEAR are driven just after a rising edge and consumed on the
    // next rising edge. This avoids races with the DUT's sequential logic.
    task apply_arm;
        begin
            @(posedge clk_i);
            #1;
            arm_i = 1'b1;

            #1;
            check_1bit(trigger_pulse_o, 1'b0,
                       "ARM command suppresses trigger_pulse_o");

            @(posedge clk_i);
            #1;
            arm_i = 1'b0;

            check_1bit(armed_o, 1'b1,
                       "ARM sets armed_o");
            check_1bit(triggered_o, 1'b0,
                       "ARM clears triggered_o");
            check_32bit(trigger_count_o, expected_trigger_count,
                        "ARM does not change trigger_count_o");
        end
    endtask

    task apply_clear;
        begin
            @(posedge clk_i);
            #1;
            clear_i = 1'b1;

            #1;
            check_1bit(trigger_pulse_o, 1'b0,
                       "CLEAR command suppresses trigger_pulse_o");

            @(posedge clk_i);
            #1;
            clear_i = 1'b0;

            check_1bit(armed_o, 1'b0,
                       "CLEAR clears armed_o");
            check_1bit(triggered_o, 1'b0,
                       "CLEAR clears triggered_o");
            check_32bit(trigger_count_o, expected_trigger_count,
                        "CLEAR preserves cumulative trigger_count_o");
        end
    endtask

    // Drive one sample for a complete sample cycle.
    //
    // The sample and sample_valid_i are changed just after a rising edge.
    // trigger_pulse_o is then checked during the same sample cycle and again
    // at the falling edge. On the following rising edge, the DUT captures the
    // trigger state and the pulse must deassert.
    task drive_sample;
        input [7:0]              sample_value;
        input                    sample_is_valid;
        input                    expected_pulse;
        input [8*96-1:0]         sample_name;
        begin
            @(posedge clk_i);
            #1;
            sample_data_i  = sample_value;
            sample_valid_i = sample_is_valid;

            // Check the combinational trigger in the current sample cycle.
            #1;
            check_1bit(trigger_pulse_o, expected_pulse, sample_name);

            if (expected_pulse) begin
                check_1bit(sample_valid_i, 1'b1,
                           "Trigger is aligned with sample_valid_i");
                check_8bit(sample_data_i, sample_value,
                           "Trigger is aligned with the expected current sample");
            end

            // Check that the pulse remains valid throughout the sample cycle.
            @(negedge clk_i);
            #1;
            check_1bit(trigger_pulse_o, expected_pulse,
                       "Trigger pulse remains stable until capture edge");

            // The DUT consumes the sample at this edge.
            @(posedge clk_i);
            #1;

            if (expected_pulse) begin
                expected_trigger_count = expected_trigger_count + 1;

                check_1bit(triggered_o, 1'b1,
                           "Trigger event sets triggered_o");
                check_32bit(trigger_count_o, expected_trigger_count,
                            "Trigger event increments trigger_count_o once");
                check_1bit(trigger_pulse_o, 1'b0,
                           "Trigger pulse deasserts after capture edge");
            end
            else begin
                check_32bit(trigger_count_o, expected_trigger_count,
                            "Non-triggering sample does not change trigger_count_o");
            end

            sample_valid_i = 1'b0;
            #1;
            check_1bit(trigger_pulse_o, 1'b0,
                       "sample_valid_i=0 suppresses trigger_pulse_o");
        end
    endtask

    // -------------------------------------------------------------------------
    // Test sequence
    // -------------------------------------------------------------------------

    initial begin
        rst_ni                = 1'b0;
        sample_data_i         = 8'h00;
        sample_valid_i        = 1'b0;
        arm_i                 = 1'b0;
        clear_i               = 1'b0;
        mode_i                = TRIGGER_DISABLED;
        edge_channel_i        = 3'd0;
        pattern_value_i       = 8'h00;
        pattern_mask_i        = 8'h00;
        test_count            = 0;
        error_count           = 0;
        expected_trigger_count = 0;

        $dumpfile("tb_basic_trigger_engine.vcd");
        $dumpvars(0, tb_basic_trigger_engine);

        $display("");
        $display("============================================================");
        $display(" Basic Trigger Engine Verilog Testbench Start");
        $display("============================================================");

        // ---------------------------------------------------------------------
        // TEST 1: Synchronous active-low reset
        // ---------------------------------------------------------------------
        $display("");
        $display("[TEST 1] Reset state");

        repeat (2) @(posedge clk_i);
        #1;

        check_1bit(armed_o, 1'b0,
                   "Reset clears armed_o");
        check_1bit(triggered_o, 1'b0,
                   "Reset clears triggered_o");
        check_1bit(trigger_pulse_o, 1'b0,
                   "Reset keeps trigger_pulse_o low");
        check_32bit(trigger_count_o, 32'd0,
                    "Reset clears trigger_count_o");

        rst_ni = 1'b1;

        // ---------------------------------------------------------------------
        // TEST 2: Input activity before ARM must not trigger
        // ---------------------------------------------------------------------
        $display("");
        $display("[TEST 2] No trigger before ARM");

        mode_i          = TRIGGER_PATTERN;
        pattern_value_i = 8'hA5;
        pattern_mask_i  = 8'hFF;

        drive_sample(8'hA5, 1'b1, 1'b0,
                     "Matching pattern before ARM does not trigger");

        // ---------------------------------------------------------------------
        // TEST 3: First valid sample after ARM cannot cause edge trigger
        // ---------------------------------------------------------------------
        $display("");
        $display("[TEST 3] First valid edge sample after ARM");

        mode_i         = TRIGGER_RISING;
        edge_channel_i = 3'd0;

        apply_arm;
        drive_sample(8'h01, 1'b1, 1'b0,
                     "First valid sample after ARM does not cause rising trigger");
        apply_clear;

        // ---------------------------------------------------------------------
        // TEST 4: Rising edge and selected-channel behavior
        // ---------------------------------------------------------------------
        $display("");
        $display("[TEST 4] Selected-channel rising trigger");

        mode_i         = TRIGGER_RISING;
        edge_channel_i = 3'd0;

        apply_arm;
        drive_sample(8'h00, 1'b1, 1'b0,
                     "Rising test captures first baseline sample");
        drive_sample(8'h02, 1'b1, 1'b0,
                     "Unselected channel 1 rising edge is ignored");
        drive_sample(8'h03, 1'b1, 1'b1,
                     "Selected channel 0 rising edge triggers");

        // The engine is still armed, but triggered_o blocks every new pulse.
        drive_sample(8'h00, 1'b1, 1'b0,
                     "No additional trigger before CLEAR");
        drive_sample(8'h01, 1'b1, 1'b0,
                     "Repeated rising condition is blocked before CLEAR");

        // ---------------------------------------------------------------------
        // TEST 5: Falling edge and unselected-channel behavior
        // ---------------------------------------------------------------------
        $display("");
        $display("[TEST 5] Selected-channel falling trigger");

        apply_clear;
        mode_i         = TRIGGER_FALLING;
        edge_channel_i = 3'd1;

        apply_arm;
        drive_sample(8'h03, 1'b1, 1'b0,
                     "Falling test captures first baseline sample");
        drive_sample(8'h02, 1'b1, 1'b0,
                     "Unselected channel 0 falling edge is ignored");
        drive_sample(8'h00, 1'b1, 1'b1,
                     "Selected channel 1 falling edge triggers");

        // ---------------------------------------------------------------------
        // TEST 6: sample_valid_i=0 must not update previous_sample
        // ---------------------------------------------------------------------
        $display("");
        $display("[TEST 6] Invalid sample does not update history");

        apply_clear;
        mode_i         = TRIGGER_RISING;
        edge_channel_i = 3'd0;

        apply_arm;
        drive_sample(8'h00, 1'b1, 1'b0,
                     "Valid zero establishes the rising-edge baseline");
        drive_sample(8'h01, 1'b0, 1'b0,
                     "Invalid high sample causes no trigger and no history update");
        drive_sample(8'h01, 1'b1, 1'b1,
                     "Next valid high sample still detects zero-to-one transition");

        // ---------------------------------------------------------------------
        // TEST 7: Masked pattern comparison and entry trigger
        // ---------------------------------------------------------------------
        $display("");
        $display("[TEST 7] Masked pattern-entry trigger");

        apply_clear;
        mode_i          = TRIGGER_PATTERN;
        pattern_value_i = 8'hA5;
        pattern_mask_i  = 8'hF0;

        apply_arm;
        drive_sample(8'h55, 1'b1, 1'b0,
                     "Nonmatching masked pattern does not trigger");
        drive_sample(8'hAF, 1'b1, 1'b1,
                     "Only masked upper nibble is compared");
        drive_sample(8'hA0, 1'b1, 1'b0,
                     "Maintained pattern match causes no additional trigger");
        drive_sample(8'hA7, 1'b1, 1'b0,
                     "Pattern remains one-shot until CLEAR");

        // ---------------------------------------------------------------------
        // TEST 8: Pattern mode may trigger on first valid sample after ARM
        // ---------------------------------------------------------------------
        $display("");
        $display("[TEST 8] Pattern trigger on first valid sample");

        apply_clear;
        mode_i          = TRIGGER_PATTERN;
        pattern_value_i = 8'h3C;
        pattern_mask_i  = 8'hFF;

        apply_arm;
        drive_sample(8'h3C, 1'b1, 1'b1,
                     "First valid matching pattern sample triggers");

        // ---------------------------------------------------------------------
        // TEST 9: A zero pattern mask disables pattern triggering
        // ---------------------------------------------------------------------
        $display("");
        $display("[TEST 9] Zero pattern mask");

        apply_clear;
        mode_i          = TRIGGER_PATTERN;
        pattern_value_i = 8'hA5;
        pattern_mask_i  = 8'h00;

        apply_arm;
        drive_sample(8'h00, 1'b1, 1'b0,
                     "Zero mask prevents trigger for all-zero sample");
        drive_sample(8'hFF, 1'b1, 1'b0,
                     "Zero mask prevents trigger for all-one sample");

        // ---------------------------------------------------------------------
        // TEST 10: Disabled mode must never trigger
        // ---------------------------------------------------------------------
        $display("");
        $display("[TEST 10] Disabled trigger mode");

        apply_clear;
        mode_i         = TRIGGER_DISABLED;
        edge_channel_i = 3'd0;

        apply_arm;
        drive_sample(8'h00, 1'b1, 1'b0,
                     "Disabled mode accepts baseline without trigger");
        drive_sample(8'hFF, 1'b1, 1'b0,
                     "Disabled mode ignores edge and pattern conditions");

        // ---------------------------------------------------------------------
        // TEST 11: CLEAR and re-ARM restore operation
        // ---------------------------------------------------------------------
        $display("");
        $display("[TEST 11] CLEAR followed by re-ARM");

        apply_clear;
        mode_i         = TRIGGER_RISING;
        edge_channel_i = 3'd2;

        apply_arm;
        drive_sample(8'h00, 1'b1, 1'b0,
                     "First run captures channel 2 low baseline");
        drive_sample(8'h04, 1'b1, 1'b1,
                     "First run detects channel 2 rising edge");

        apply_clear;
        apply_arm;
        drive_sample(8'h00, 1'b1, 1'b0,
                     "Re-armed run captures a new low baseline");
        drive_sample(8'h04, 1'b1, 1'b1,
                     "Re-armed run detects another rising edge");

        // ---------------------------------------------------------------------
        // Final checks and summary
        // ---------------------------------------------------------------------
        check_32bit(trigger_count_o, expected_trigger_count,
                    "Final trigger_count_o equals total accepted triggers");

        $display("");
        $display("============================================================");
        if (error_count == 0) begin
            $display(" ALL TESTS PASSED: %0d checks, %0d trigger events",
                     test_count, expected_trigger_count);
        end
        else begin
            $display(" TEST FAILED: %0d of %0d checks failed",
                     error_count, test_count);
        end
        $display("============================================================");
        $display("");

        #10;
        $finish;
    end

    // Stop the simulation if a coding or clocking error causes a deadlock.
    initial begin
        #10000;
        $display("[%0t] FAIL: Simulation timeout", $time);
        $finish;
    end

endmodule
