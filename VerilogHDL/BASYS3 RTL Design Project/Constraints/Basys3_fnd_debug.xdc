## Basys3 debug constraints for top_a_b_c_d_fnd_debug
## IMPORTANT: Disable final_top_a_b_c_d_basys3.xdc and every other board XDC.
## Enable only this file while synthesizing the FND debug top.
## Target top-level ports:
## clk, arst, btn_enter, btn_100, btn_500, btn_1000, btn_refund,
## sw[14:0], led[15:0], seg[6:0], an[3:0], servo_out, ja_dbg[7:0],
## ext_stock_led[4:0], ext_sugar_bar[4:0], ext_ice_bar[4:0]

## =========================================================
## Clock: 100 MHz system clock
## =========================================================
set_property -dict { PACKAGE_PIN W5 IOSTANDARD LVCMOS33 } [get_ports clk]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clk]

## =========================================================
## Reset: physical SW15, active-high asynchronous reset
## =========================================================
set_property -dict { PACKAGE_PIN R2 IOSTANDARD LVCMOS33 } [get_ports arst]

## =========================================================
## Switches
## sw[14:10] : drink, sw[9:5] : sugar, sw[4:0] : ice
## =========================================================
set_property -dict { PACKAGE_PIN V17 IOSTANDARD LVCMOS33 } [get_ports {sw[0]}]
set_property -dict { PACKAGE_PIN V16 IOSTANDARD LVCMOS33 } [get_ports {sw[1]}]
set_property -dict { PACKAGE_PIN W16 IOSTANDARD LVCMOS33 } [get_ports {sw[2]}]
set_property -dict { PACKAGE_PIN W17 IOSTANDARD LVCMOS33 } [get_ports {sw[3]}]
set_property -dict { PACKAGE_PIN W15 IOSTANDARD LVCMOS33 } [get_ports {sw[4]}]
set_property -dict { PACKAGE_PIN V15 IOSTANDARD LVCMOS33 } [get_ports {sw[5]}]
set_property -dict { PACKAGE_PIN W14 IOSTANDARD LVCMOS33 } [get_ports {sw[6]}]
set_property -dict { PACKAGE_PIN W13 IOSTANDARD LVCMOS33 } [get_ports {sw[7]}]
set_property -dict { PACKAGE_PIN V2  IOSTANDARD LVCMOS33 } [get_ports {sw[8]}]
set_property -dict { PACKAGE_PIN T3  IOSTANDARD LVCMOS33 } [get_ports {sw[9]}]
set_property -dict { PACKAGE_PIN T2  IOSTANDARD LVCMOS33 } [get_ports {sw[10]}]
set_property -dict { PACKAGE_PIN R3  IOSTANDARD LVCMOS33 } [get_ports {sw[11]}]
set_property -dict { PACKAGE_PIN W2  IOSTANDARD LVCMOS33 } [get_ports {sw[12]}]
set_property -dict { PACKAGE_PIN U1  IOSTANDARD LVCMOS33 } [get_ports {sw[13]}]
set_property -dict { PACKAGE_PIN T1  IOSTANDARD LVCMOS33 } [get_ports {sw[14]}]

## =========================================================
## Buttons: btnL=100, btnC=500, btnR=1000, btnU=Enter, btnD=Refund
## =========================================================
set_property -dict { PACKAGE_PIN T18 IOSTANDARD LVCMOS33 } [get_ports btn_enter]
set_property -dict { PACKAGE_PIN W19 IOSTANDARD LVCMOS33 } [get_ports btn_100]
set_property -dict { PACKAGE_PIN U18 IOSTANDARD LVCMOS33 } [get_ports btn_500]
set_property -dict { PACKAGE_PIN T17 IOSTANDARD LVCMOS33 } [get_ports btn_1000]
set_property -dict { PACKAGE_PIN U17 IOSTANDARD LVCMOS33 } [get_ports btn_refund]

## =========================================================
## LEDs
## =========================================================
set_property -dict { PACKAGE_PIN U16 IOSTANDARD LVCMOS33 } [get_ports {led[0]}]
set_property -dict { PACKAGE_PIN E19 IOSTANDARD LVCMOS33 } [get_ports {led[1]}]
set_property -dict { PACKAGE_PIN U19 IOSTANDARD LVCMOS33 } [get_ports {led[2]}]
set_property -dict { PACKAGE_PIN V19 IOSTANDARD LVCMOS33 } [get_ports {led[3]}]
set_property -dict { PACKAGE_PIN W18  IOSTANDARD LVCMOS33 } [get_ports {led[4]}]
set_property -dict { PACKAGE_PIN U15 IOSTANDARD LVCMOS33 } [get_ports {led[5]}]
set_property -dict { PACKAGE_PIN U14 IOSTANDARD LVCMOS33 } [get_ports {led[6]}]
set_property -dict { PACKAGE_PIN V14 IOSTANDARD LVCMOS33 } [get_ports {led[7]}]
set_property -dict { PACKAGE_PIN V13 IOSTANDARD LVCMOS33 } [get_ports {led[8]}]
set_property -dict { PACKAGE_PIN V3 IOSTANDARD LVCMOS33 } [get_ports {led[9]}]
set_property -dict { PACKAGE_PIN W3  IOSTANDARD LVCMOS33 } [get_ports {led[10]}]
set_property -dict { PACKAGE_PIN U3  IOSTANDARD LVCMOS33 } [get_ports {led[11]}]
set_property -dict { PACKAGE_PIN P3  IOSTANDARD LVCMOS33 } [get_ports {led[12]}]
set_property -dict { PACKAGE_PIN N3  IOSTANDARD LVCMOS33 } [get_ports {led[13]}]
set_property -dict { PACKAGE_PIN P1  IOSTANDARD LVCMOS33 } [get_ports {led[14]}]
set_property -dict { PACKAGE_PIN L1  IOSTANDARD LVCMOS33 } [get_ports {led[15]}]

## =========================================================
## On-board 7-segment display: seg[0:6]=a:g
## =========================================================
set_property -dict { PACKAGE_PIN W7 IOSTANDARD LVCMOS33 } [get_ports {seg[0]}]
set_property -dict { PACKAGE_PIN W6 IOSTANDARD LVCMOS33 } [get_ports {seg[1]}]
set_property -dict { PACKAGE_PIN U8 IOSTANDARD LVCMOS33 } [get_ports {seg[2]}]
set_property -dict { PACKAGE_PIN V8 IOSTANDARD LVCMOS33 } [get_ports {seg[3]}]
set_property -dict { PACKAGE_PIN U5 IOSTANDARD LVCMOS33 } [get_ports {seg[4]}]
set_property -dict { PACKAGE_PIN V5 IOSTANDARD LVCMOS33 } [get_ports {seg[5]}]
set_property -dict { PACKAGE_PIN U7 IOSTANDARD LVCMOS33 } [get_ports {seg[6]}]

set_property -dict { PACKAGE_PIN U2 IOSTANDARD LVCMOS33 } [get_ports {an[0]}]
set_property -dict { PACKAGE_PIN U4 IOSTANDARD LVCMOS33 } [get_ports {an[1]}]
set_property -dict { PACKAGE_PIN V4 IOSTANDARD LVCMOS33 } [get_ports {an[2]}]
set_property -dict { PACKAGE_PIN W4 IOSTANDARD LVCMOS33 } [get_ports {an[3]}]

## =========================================================
## Servo: PMOD JC1 = K17 (unchanged)
## Use an external 5V servo supply and common ground.
## =========================================================
set_property -dict { PACKAGE_PIN K17 IOSTANDARD LVCMOS33 } [get_ports servo_out]

## =========================================================
## External 1-digit FND on JA PMOD
## Board-observed active-low polarity: segment ON=0, OFF=1.
## Wire the display common pin according to the actual external module.
## ja_dbg[7]=dp, [6]=g, [5]=f, [4]=e, [3]=d, [2]=c, [1]=b, [0]=a
## Use one series resistor (typically 220~470 ohm) per segment.
## =========================================================
set_property PACKAGE_PIN J1 [get_ports {ja_dbg[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ja_dbg[0]}]

set_property PACKAGE_PIN L2 [get_ports {ja_dbg[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ja_dbg[1]}]

set_property PACKAGE_PIN J2 [get_ports {ja_dbg[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ja_dbg[2]}]

set_property PACKAGE_PIN G2 [get_ports {ja_dbg[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ja_dbg[3]}]

set_property PACKAGE_PIN H1 [get_ports {ja_dbg[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ja_dbg[4]}]

set_property PACKAGE_PIN K2 [get_ports {ja_dbg[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ja_dbg[5]}]

set_property PACKAGE_PIN H2 [get_ports {ja_dbg[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ja_dbg[6]}]

set_property PACKAGE_PIN G3 [get_ports {ja_dbg[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ja_dbg[7]}]

## =========================================================
## External status LEDs (active-high, no inversion)
## JA is reserved for the external FSM FND; JC1 is servo_out.
## The 15 outputs use all eight JB signals and the seven free JC signals.
## =========================================================

## External stock LEDs: JB1, JB2, JB3, JB4, JB7
set_property -dict { PACKAGE_PIN A14 IOSTANDARD LVCMOS33 } [get_ports {ext_stock_led[0]}]
set_property -dict { PACKAGE_PIN A16 IOSTANDARD LVCMOS33 } [get_ports {ext_stock_led[1]}]
set_property -dict { PACKAGE_PIN B15 IOSTANDARD LVCMOS33 } [get_ports {ext_stock_led[2]}]
set_property -dict { PACKAGE_PIN B16 IOSTANDARD LVCMOS33 } [get_ports {ext_stock_led[3]}]
set_property -dict { PACKAGE_PIN A15 IOSTANDARD LVCMOS33 } [get_ports {ext_stock_led[4]}]

## External sugar LED bar, KB-1008SR active-high: JB8, JB9, JB10, JC2, JC3
set_property -dict { PACKAGE_PIN A17 IOSTANDARD LVCMOS33 } [get_ports {ext_sugar_bar[0]}]
set_property -dict { PACKAGE_PIN C15 IOSTANDARD LVCMOS33 } [get_ports {ext_sugar_bar[1]}]
set_property -dict { PACKAGE_PIN C16 IOSTANDARD LVCMOS33 } [get_ports {ext_sugar_bar[2]}]
set_property -dict { PACKAGE_PIN M18 IOSTANDARD LVCMOS33 } [get_ports {ext_sugar_bar[3]}]
set_property -dict { PACKAGE_PIN N17 IOSTANDARD LVCMOS33 } [get_ports {ext_sugar_bar[4]}]

## External ice LED bar, KB-1008SR active-high: JC4, JC7, JC8, JC9, JC10
set_property -dict { PACKAGE_PIN P18 IOSTANDARD LVCMOS33 } [get_ports {ext_ice_bar[0]}]
set_property -dict { PACKAGE_PIN L17 IOSTANDARD LVCMOS33 } [get_ports {ext_ice_bar[1]}]
set_property -dict { PACKAGE_PIN M19 IOSTANDARD LVCMOS33 } [get_ports {ext_ice_bar[2]}]
set_property -dict { PACKAGE_PIN P17 IOSTANDARD LVCMOS33 } [get_ports {ext_ice_bar[3]}]
set_property -dict { PACKAGE_PIN R18 IOSTANDARD LVCMOS33 } [get_ports {ext_ice_bar[4]}]

## =========================================================
## Configuration options
## =========================================================
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
