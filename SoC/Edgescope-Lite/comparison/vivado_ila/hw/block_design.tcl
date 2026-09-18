# Vivado ILA (comparison C) overlay for the frozen common Base SoC.
#
# Vivado 2024.2 usage:
#   vivado -mode batch \
#     -source comparison/vivado_ila/hw/block_design.tcl
#
# The common project is recreated and cloned before this overlay is applied.
# This keeps the A, B, and C resource measurements independent.

set c_script_dir [file dirname [file normalize [info script]]]
set c_repo_root [file normalize [file join $c_script_dir ../../..]]
set c_base_tcl [file join $c_repo_root comparison common base_soc.tcl]
set c_build_dir [file join $c_script_dir build]
set c_project_name {vivado_ila_reference}

if {![file exists $c_base_tcl]} {
  error "Common Base SoC script is missing: $c_base_tcl"
}

# Recreate the frozen base, reopen it, then clone it so C never mutates the A
# or B project.
source $c_base_tcl
set c_base_project [file join $c_repo_root comparison common build base_soc \
  edgescope_comparison_base.xpr]
if {![file exists $c_base_project]} {
  error "Common Base project was not generated: $c_base_project"
}
open_project $c_base_project
file mkdir $c_build_dir
save_project_as -force $c_project_name $c_build_dir

set bd_file_candidates [get_files -quiet */base_soc.bd]
if {[llength $bd_file_candidates] != 1} {
  error "Expected one base_soc.bd, found: $bd_file_candidates"
}
open_bd_design [lindex $bd_file_candidates 0]
current_bd_design base_soc

foreach unexpected_cell {
  test_pattern_generator_0
  vivado_ila_0
  probe_sampler_0
  basic_trigger_engine_0
  circular_trace_buffer_0
  axi_gpio_probe
} {
  if {[llength [get_bd_cells -quiet $unexpected_cell]] != 0} {
    error "Analyzer overlay cell already exists: $unexpected_cell"
  }
}

# Common deterministic stimulus (identical RTL and GPIO control path to A/B).
set generator_source [file join $c_repo_root comparison common rtl \
  test_pattern_generator.sv]
if {![file exists $generator_source]} {
  error "Common Test Pattern Generator is missing: $generator_source"
}
add_files -norecurse $generator_source
set_property FILE_TYPE {Verilog} [get_files [file tail $generator_source]]
update_compile_order -fileset sources_1

set generator [create_bd_cell -type module \
  -reference test_pattern_generator test_pattern_generator_0]
connect_bd_net [get_bd_pins clk_wiz/clk_out1] \
  [get_bd_pins $generator/clk_i]
connect_bd_net [get_bd_pins rst_clk_wiz_100M/peripheral_aresetn] \
  [get_bd_pins $generator/reset_n_i]
connect_bd_net [get_bd_pins axi_gpio_test_ctrl/gpio_io_o] \
  [get_bd_pins $generator/control_i]
connect_bd_net [get_bd_pins $generator/status_o] \
  [get_bd_pins axi_gpio_test_ctrl/gpio2_io_i]

# Functionally comparable 100 MS/s, 8-channel, 1,024-sample reference.
# Trigger position is a run-time Hardware Manager property and is fixed to 512
# by capture_ila.tcl.
set ila [create_bd_cell -type ip \
  -vlnv xilinx.com:ip:ila:6.2 vivado_ila_0]
set_property -dict [list \
  CONFIG.C_MONITOR_TYPE {NATIVE} \
  CONFIG.C_NUM_OF_PROBES {1} \
  CONFIG.C_DATA_DEPTH {1024} \
  CONFIG.C_PROBE0_WIDTH {8} \
  CONFIG.C_PROBE0_TYPE {0} \
  CONFIG.ALL_PROBE_SAME_MU {true} \
  CONFIG.ALL_PROBE_SAME_MU_CNT {1} \
  CONFIG.C_INPUT_PIPE_STAGES {0} \
  CONFIG.C_ADV_TRIGGER {false} \
  CONFIG.C_EN_STRG_QUAL {0} \
  CONFIG.C_TRIGIN_EN {false} \
  CONFIG.C_TRIGOUT_EN {false} \
] $ila

connect_bd_net [get_bd_pins clk_wiz/clk_out1] \
  [get_bd_pins $ila/clk]
connect_bd_net [get_bd_pins $generator/probe_test_o] \
  [get_bd_pins $ila/probe0]

validate_bd_design

foreach {property expected} {
  CONFIG.C_MONITOR_TYPE Native
  CONFIG.C_NUM_OF_PROBES 1
  CONFIG.C_DATA_DEPTH 1024
  CONFIG.C_PROBE0_WIDTH 8
  CONFIG.C_PROBE0_TYPE 0
  CONFIG.ALL_PROBE_SAME_MU true
  CONFIG.ALL_PROBE_SAME_MU_CNT 1
  CONFIG.C_INPUT_PIPE_STAGES 0
  CONFIG.C_ADV_TRIGGER false
  CONFIG.C_EN_STRG_QUAL 0
  CONFIG.C_TRIGIN_EN false
  CONFIG.C_TRIGOUT_EN false
} {
  set actual [get_property $property $ila]
  if {![string equal -nocase $actual $expected]} {
    error "ILA assertion failed: $property=$actual, expected=$expected"
  }
}

set ila_clock_net [get_bd_nets -quiet -of_objects [get_bd_pins $ila/clk]]
set soc_clock_net [get_bd_nets -quiet -of_objects \
  [get_bd_pins clk_wiz/clk_out1]]
if {$ila_clock_net eq "" || $ila_clock_net ne $soc_clock_net} {
  error "ILA clock is not connected to the common 100 MHz clock"
}

set probe_net [get_bd_nets -quiet -of_objects [get_bd_pins $ila/probe0]]
set generator_probe_net [get_bd_nets -quiet -of_objects \
  [get_bd_pins $generator/probe_test_o]]
if {$probe_net eq "" || $probe_net ne $generator_probe_net} {
  error "ILA probe0 is not connected to generator probe_test_o"
}

save_bd_design

set constraints_file [file join $c_script_dir constraints.xdc]
if {[llength [get_files -quiet $constraints_file]] == 0} {
  add_files -fileset constrs_1 -norecurse $constraints_file
}

set bd_file [get_files */base_soc.bd]
generate_target all $bd_file
set wrapper [make_wrapper -files $bd_file -top]
if {[llength [get_files -quiet $wrapper]] == 0} {
  add_files -norecurse $wrapper
}
set_property top base_soc_wrapper [current_fileset]
update_compile_order -fileset sources_1

write_bd_tcl -force [file join $c_script_dir vivado_ila_generated.tcl]
puts "VIVADO_ILA_BD: PASS"
puts "Project: [file join $c_build_dir ${c_project_name}.xpr]"
puts "ILA: xilinx.com:ip:ila:6.2"
puts "Capture: 100 MHz, 8 channels, 1,024 samples, trigger index 512"
close_project
