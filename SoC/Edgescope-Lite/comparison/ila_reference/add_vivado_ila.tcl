# Step 3: add the frozen Vivado ILA reference to the common Step-2 design.
#
# Run comparison/common/build_base_with_generator.tcl first, or use:
#   vivado -mode batch \
#     -source comparison/ila_reference/build_step3_ila.tcl
#
# Step 3 freezes only the ILA structure and capture capacity.  Runtime
# comparator conditions and the trigger position are configured in Step 4.

set step3_script_dir [file dirname [file normalize [info script]]]
set step3_common_dir [file normalize [file join \
  $step3_script_dir .. common]]
set step3_project_file [file join \
  $step3_common_dir build base_soc edgescope_comparison_base.xpr]
set step3_generated_dir [file join $step3_script_dir generated]
set step3_design_name {base_soc}
set step3_ila_name {ila_reference_0}
set step3_generator_name {test_pattern_generator_gpio_adapter_0}

proc step3_fail {message} {
  error "ILA_STEP_3_ASSERTION_FAILED: $message"
}

proc step3_assert_equal {label actual expected} {
  if {![string equal -nocase $actual $expected]} {
    step3_fail "$label: actual='$actual', expected='$expected'"
  }
  puts "ASSERT PASS: $label = $actual"
}

proc step3_assert_false {label actual} {
  set normalized [string tolower $actual]
  if {$normalized ni {0 false no}} {
    step3_fail "$label: actual='$actual', expected false/0"
  }
  puts "ASSERT PASS: $label = $actual"
}

proc step3_count_vlnv {vlnv} {
  set count 0
  foreach cell [get_bd_cells -hier -quiet] {
    if {[get_property -quiet VLNV $cell] eq $vlnv} {
      incr count
    }
  }
  return $count
}

proc step3_assert_same_net {reference_pin checked_pin} {
  set reference_net [get_bd_nets -quiet -of_objects \
    [get_bd_pins $reference_pin]]
  set checked_net [get_bd_nets -quiet -of_objects \
    [get_bd_pins $checked_pin]]
  if {$reference_net eq "" || $checked_net eq ""} {
    step3_fail \
      "Unconnected pin while comparing $reference_pin and $checked_pin"
  }
  step3_assert_equal "net $checked_pin" $checked_net $reference_net
}

if {![file exists $step3_project_file]} {
  step3_fail \
    "Run common/build_base_with_generator.tcl first: $step3_project_file"
}

file mkdir $step3_generated_dir

open_project $step3_project_file

set step3_bd_file [get_files -quiet ${step3_design_name}.bd]
if {[llength $step3_bd_file] != 1} {
  step3_fail "Block Design ${step3_design_name}.bd was not found exactly once"
}
open_bd_design $step3_bd_file

set step3_generator [get_bd_cells -quiet $step3_generator_name]
if {[llength $step3_generator] != 1} {
  step3_fail "Common Test Pattern Generator was not found exactly once"
}
step3_assert_equal {Generator VLNV} \
  [get_property VLNV $step3_generator] \
  {xilinx.com:module_ref:test_pattern_generator_gpio_adapter:1.0}

if {[llength [get_bd_nets -quiet -of_objects \
    [get_bd_pins ${step3_generator_name}/probe_test_o]]] != 0} {
  step3_fail \
    "Generator probe_test_o was already connected before ILA Step 3"
}

if {[step3_count_vlnv {xilinx.com:ip:ila:6.2}] != 0} {
  step3_fail "Vivado ILA already exists; rebuild the common Step-2 design"
}

set step3_cells_before_ila [lsort \
  [get_property NAME [get_bd_cells -hier -quiet]]]

set step3_ila [create_bd_cell -type ip \
  -vlnv xilinx.com:ip:ila:6.2 $step3_ila_name]

# Vivado 2024.2 can initially create this IP in AXI monitor mode with many
# probes.  Every structural comparison property is therefore explicit.
set_property -dict [list \
  CONFIG.C_MONITOR_TYPE {Native} \
  CONFIG.C_NUM_OF_PROBES {1} \
  CONFIG.C_DATA_DEPTH {1024} \
  CONFIG.C_PROBE0_WIDTH {8} \
  CONFIG.C_PROBE0_TYPE {0} \
  CONFIG.C_PROBE0_MU_CNT {1} \
  CONFIG.C_INPUT_PIPE_STAGES {0} \
  CONFIG.C_EN_STRG_QUAL {0} \
  CONFIG.C_ADV_TRIGGER {FALSE} \
  CONFIG.C_TRIGIN_EN {false} \
  CONFIG.C_TRIGOUT_EN {false} \
] $step3_ila

connect_bd_net \
  [get_bd_pins clk_wiz/clk_out1] \
  [get_bd_pins ${step3_ila_name}/clk]
connect_bd_net \
  [get_bd_pins ${step3_generator_name}/probe_test_o] \
  [get_bd_pins ${step3_ila_name}/probe0]

if {[catch {validate_bd_design} step3_validation_error]} {
  step3_fail "validate_bd_design failed: $step3_validation_error"
}
puts "VALIDATE DESIGN WITH VIVADO ILA: PASS"

step3_assert_equal {ILA count} \
  [step3_count_vlnv {xilinx.com:ip:ila:6.2}] 1
step3_assert_equal {ILA VLNV} \
  [get_property VLNV $step3_ila] {xilinx.com:ip:ila:6.2}
step3_assert_equal {ILA monitor type} \
  [get_property CONFIG.C_MONITOR_TYPE $step3_ila] Native
step3_assert_equal {ILA probe count} \
  [get_property CONFIG.C_NUM_OF_PROBES $step3_ila] 1
step3_assert_equal {ILA capture depth} \
  [get_property CONFIG.C_DATA_DEPTH $step3_ila] 1024
step3_assert_equal {ILA probe0 width} \
  [get_property CONFIG.C_PROBE0_WIDTH $step3_ila] 8
step3_assert_equal {ILA probe0 type DATA_AND_TRIGGER} \
  [get_property CONFIG.C_PROBE0_TYPE $step3_ila] 0
step3_assert_equal {ILA probe0 match units} \
  [get_property CONFIG.C_PROBE0_MU_CNT $step3_ila] 1
step3_assert_equal {ILA input pipeline stages} \
  [get_property CONFIG.C_INPUT_PIPE_STAGES $step3_ila] 0
step3_assert_equal {ILA storage qualification disabled} \
  [get_property CONFIG.C_EN_STRG_QUAL $step3_ila] 0
step3_assert_equal {ILA advanced trigger disabled} \
  [get_property CONFIG.C_ADV_TRIGGER $step3_ila] FALSE
step3_assert_false {ILA TRIG_IN disabled} \
  [get_property CONFIG.C_TRIGIN_EN $step3_ila]
step3_assert_false {ILA TRIG_OUT disabled} \
  [get_property CONFIG.C_TRIGOUT_EN $step3_ila]
step3_assert_equal {ILA clock frequency} \
  [get_property CONFIG.C_ILA_CLK_FREQ $step3_ila] 100000000
step3_assert_equal {Top-level system clock frequency} \
  [get_property CONFIG.FREQ_HZ [get_bd_ports sys_clock]] 100000000

set step3_ila_pins [lsort \
  [get_property NAME [get_bd_pins -quiet -of_objects $step3_ila]]]
step3_assert_equal {ILA physical pins} \
  $step3_ila_pins {clk probe0}
step3_assert_equal {ILA probe0 left index} \
  [get_property LEFT [get_bd_pins ${step3_ila_name}/probe0]] 7
step3_assert_equal {ILA probe0 right index} \
  [get_property RIGHT [get_bd_pins ${step3_ila_name}/probe0]] 0
step3_assert_equal {Generator probe left index} \
  [get_property LEFT \
    [get_bd_pins ${step3_generator_name}/probe_test_o]] 7
step3_assert_equal {Generator probe right index} \
  [get_property RIGHT \
    [get_bd_pins ${step3_generator_name}/probe_test_o]] 0

step3_assert_same_net \
  clk_wiz/clk_out1 ${step3_generator_name}/clk_i
step3_assert_same_net \
  clk_wiz/clk_out1 ${step3_ila_name}/clk
step3_assert_same_net \
  ${step3_generator_name}/probe_test_o ${step3_ila_name}/probe0

step3_assert_equal {System ILA count} \
  [step3_count_vlnv {xilinx.com:ip:system_ila:1.1}] 0
step3_assert_equal {VIO count} \
  [step3_count_vlnv {xilinx.com:ip:vio:3.0}] 0
step3_assert_equal {AXI BRAM Controller count} \
  [step3_count_vlnv {xilinx.com:ip:axi_bram_ctrl:4.1}] 0
step3_assert_equal {AXI GPIO count} \
  [step3_count_vlnv {xilinx.com:ip:axi_gpio:2.0}] 1
step3_assert_equal {Block Memory Generator count} \
  [step3_count_vlnv {xilinx.com:ip:blk_mem_gen:8.4}] 1

if {[llength [get_bd_cells -quiet axi_gpio_probe]] != 0} {
  step3_fail "CPU Polling probe GPIO is forbidden in the ILA reference"
}

foreach step3_cell [get_bd_cells -hier -quiet] {
  set step3_cell_vlnv [get_property -quiet VLNV $step3_cell]
  if {[regexp -nocase \
      {(circular_trace_buffer|probe_sampler|basic_trigger_engine)} \
      $step3_cell_vlnv]} {
    step3_fail \
      "Custom analyzer IP is forbidden in the ILA reference: $step3_cell"
  }
}

step3_assert_equal {Data address segment count} \
  [llength [get_bd_addr_segs -of_objects \
    [get_bd_addr_spaces microblaze_riscv_0/Data]]] 5
step3_assert_equal {Instruction address segment count} \
  [llength [get_bd_addr_segs -of_objects \
    [get_bd_addr_spaces microblaze_riscv_0/Instruction]]] 1
step3_assert_equal {External interface ports} \
  [lsort [get_property NAME [get_bd_intf_ports]]] {usb_uart}
step3_assert_equal {External scalar ports} \
  [lsort [get_property NAME [get_bd_ports]]] \
  {reset sys_clock usb_uart_rxd usb_uart_txd}

set step3_cells_after_ila [lsort \
  [get_property NAME [get_bd_cells -hier -quiet]]]
set step3_ila_cell_index [lsearch -exact \
  $step3_cells_after_ila $step3_ila_name]
if {$step3_ila_cell_index < 0} {
  step3_fail "ILA cell was not found in the post-addition cell list"
}
set step3_cells_without_ila [lreplace \
  $step3_cells_after_ila $step3_ila_cell_index $step3_ila_cell_index]
step3_assert_equal {Pre-existing Block Design cells unchanged} \
  $step3_cells_without_ila $step3_cells_before_ila

save_bd_design

# Generate the IP/BD output products without running full system synthesis.
# Full synthesis, implementation, bitstream, timing and utilization are Step 5.
generate_target all $step3_bd_file

set step3_generated_tcl [file join \
  $step3_generated_dir ila_reference_step3_generated.tcl]
write_bd_tcl -force $step3_generated_tcl

set step3_property_report [file join \
  $step3_generated_dir ila_reference_step3_properties.rpt]
set step3_property_handle [open $step3_property_report w]
puts $step3_property_handle \
  {Property                                                        Value}
puts $step3_property_handle \
  {------------------------------------------------------------------------}
foreach step3_property [lsort [list_property $step3_ila]] {
  puts $step3_property_handle [format \
    "%-63s %s" \
    $step3_property \
    [get_property -quiet $step3_property $step3_ila]]
}
close $step3_property_handle

set step3_ip_status_report [file join \
  $step3_generated_dir ila_reference_step3_ip_status.rpt]
report_ip_status -file $step3_ip_status_report

set step3_report_file [file join \
  $step3_generated_dir ila_reference_step3_configuration.rpt]
set step3_report_handle [open $step3_report_file w]
puts $step3_report_handle {EdgeScope-Lite Vivado ILA Reference - Step 3}
puts $step3_report_handle {=============================================}
puts $step3_report_handle {Vivado                  : 2024.2}
puts $step3_report_handle {FPGA Part               : xc7a35tcpg236-1}
puts $step3_report_handle {ILA VLNV                : xilinx.com:ip:ila:6.2}
puts $step3_report_handle {Monitor Type            : Native}
puts $step3_report_handle {Probe Count             : 1}
puts $step3_report_handle {Probe0 Width            : 8}
puts $step3_report_handle {Probe0 Type             : 0 (DATA_AND_TRIGGER)}
puts $step3_report_handle {Probe0 Match Units      : 1}
puts $step3_report_handle {Capture Depth           : 1024 samples}
puts $step3_report_handle {Input Pipeline Stages   : 0}
puts $step3_report_handle {Advanced Trigger        : disabled}
puts $step3_report_handle {Storage Qualification   : disabled}
puts $step3_report_handle {TRIG_IN / TRIG_OUT      : disabled / disabled}
puts $step3_report_handle {ILA Clock               : 100000000 Hz}
puts $step3_report_handle \
  {Probe Source            : test_pattern_generator_gpio_adapter_0/probe_test_o[7:0]}
puts $step3_report_handle {Runtime Window Count    : 1 (Step 4 setting)}
puts $step3_report_handle {Runtime Trigger Position: 512 (Step 4 setting)}
puts $step3_report_handle \
  {Capture Geometry        : pre 512, trigger sample + post 511}
puts $step3_report_handle {Validate Design         : PASS}
puts $step3_report_handle {Output Products         : GENERATED}
puts $step3_report_handle \
  {Full Synth/Impl/Bitstream: NOT RUN (reserved for Step 5)}
close $step3_report_handle

puts "VIVADO_ILA_STEP_3: PASS"
puts "Generated Tcl: $step3_generated_tcl"
puts "Configuration report: $step3_report_file"
puts "Property report: $step3_property_report"
puts "IP status report: $step3_ip_status_report"
puts "Pending Step 4: runtime trigger position and three trigger conditions"

close_project
