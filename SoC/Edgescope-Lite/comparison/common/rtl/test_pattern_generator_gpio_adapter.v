`timescale 1ns/1ps
`default_nettype none

// Pure-Verilog Block Design adapter.
//
// Vivado 2024.2 does not allow a SystemVerilog file to be the top file of a
// Module Reference cell.  This synthesis-transparent wrapper keeps the
// functional generator in SystemVerilog while providing a Verilog BD top.
module test_pattern_generator_gpio_adapter (
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 CLK_I CLK" *)
  (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME CLK_I, ASSOCIATED_RESET reset_n_i, FREQ_HZ 100000000" *)
  input  wire         clk_i,

  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 RESET_N_I RST" *)
  (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME RESET_N_I, POLARITY ACTIVE_LOW" *)
  input  wire         reset_n_i,

  (* X_INTERFACE_INFO = "xilinx.com:interface:gpio:1.0 CONTROL_GPIO TRI_O" *)
  (* X_INTERFACE_MODE = "slave" *)
  input  wire [25:0]  control_i,

  (* X_INTERFACE_INFO = "xilinx.com:interface:gpio:1.0 STATUS_GPIO TRI_I" *)
  (* X_INTERFACE_MODE = "slave" *)
  output wire [1:0]   status_o,

  output wire [7:0]   probe_test_o
);

  test_pattern_generator generator_i (
    .clk_i(clk_i),
    .reset_n_i(reset_n_i),
    .control_i(control_i),
    .status_o(status_o),
    .probe_test_o(probe_test_o)
  );

endmodule

`default_nettype wire
