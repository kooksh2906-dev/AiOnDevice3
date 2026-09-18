`timescale 1ns/1ps

module tb_common_pkg;
  import logic_analyzer_pkg::*;

  initial begin
    if (SPEC_VERSION_MAJOR != 2 || SPEC_VERSION_MINOR != 1)
      $fatal(1, "Common specification version mismatch");
    if (PROBE_WIDTH != 8)
      $fatal(1, "PROBE_WIDTH mismatch");
    if (BRAM_DATA_WIDTH != 32 || BRAM_ADDR_WIDTH != 10)
      $fatal(1, "BRAM geometry mismatch");
    if (CAPTURE_DEPTH != 1024)
      $fatal(1, "CAPTURE_DEPTH mismatch");
    if (PRE_TRIGGER_SAMPLES != 512 || POST_TRIGGER_SAMPLES != 512)
      $fatal(1, "Trigger position mismatch");
    if (TRIGGER_LOGICAL_INDEX != 512)
      $fatal(1, "TRIGGER_LOGICAL_INDEX mismatch");

    $display("EdgeScope-Lite common package: PASS");
  end
endmodule
