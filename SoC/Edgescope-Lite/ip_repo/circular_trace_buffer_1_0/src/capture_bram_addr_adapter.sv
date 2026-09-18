`timescale 1ns/1ps

// Converts the Trace Buffer's 10-bit word index to the byte address used by
// a 32-bit-address Block Memory Generator / AXI BRAM Controller connection.
module capture_bram_addr_adapter (
  input  logic [logic_analyzer_pkg::BRAM_ADDR_WIDTH-1:0] word_addr_i,
  output logic [31:0]                                    byte_addr_o
);
  import logic_analyzer_pkg::*;

  assign byte_addr_o = {
    {(32-BRAM_ADDR_WIDTH-2){1'b0}},
    word_addr_i,
    2'b00
  };
endmodule

