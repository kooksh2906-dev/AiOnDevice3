# Step 2: add the common deterministic generator to the validated Base SoC.
#
# Run comparison/common/base_soc.tcl first, or use:
#   vivado -mode batch \
#     -source comparison/common/build_base_with_generator.tcl

set script_dir [file dirname [file normalize [info script]]]
set project_file [file join \
  $script_dir build base_soc edgescope_comparison_base.xpr]
set core_rtl_file [file join \
  $script_dir rtl test_pattern_generator.sv]
set adapter_rtl_file [file join \
  $script_dir rtl test_pattern_generator_gpio_adapter.v]
set generated_dir [file join $script_dir generated]

if {![file exists $project_file]} {
  error "Run comparison/common/base_soc.tcl before Step 2: $project_file"
}
if {![file exists $core_rtl_file]} {
  error "Generator core RTL was not found: $core_rtl_file"
}
if {![file exists $adapter_rtl_file]} {
  error "Generator adapter RTL was not found: $adapter_rtl_file"
}

open_project $project_file

foreach rtl_file [list $core_rtl_file $adapter_rtl_file] {
  if {[llength [get_files -quiet [list $rtl_file]]] == 0} {
    add_files -norecurse [list $rtl_file]
  }
}
set_property FILE_TYPE {SystemVerilog} \
  [get_files [list $core_rtl_file]]
set_property FILE_TYPE {Verilog} \
  [get_files [list $adapter_rtl_file]]
update_compile_order -fileset sources_1

open_bd_design [get_files base_soc.bd]

if {[llength \
    [get_bd_cells -quiet test_pattern_generator_gpio_adapter_0]] != 0} {
  error "Generator already exists. Re-run base_soc.tcl before Step 2."
}

if {![can_resolve_reference test_pattern_generator_gpio_adapter]} {
  error "Vivado cannot resolve test_pattern_generator_gpio_adapter"
}

set generator [create_bd_cell -type module \
  -reference test_pattern_generator_gpio_adapter \
  test_pattern_generator_gpio_adapter_0]

connect_bd_net \
  [get_bd_pins clk_wiz/clk_out1] \
  [get_bd_pins test_pattern_generator_gpio_adapter_0/clk_i]
connect_bd_net \
  [get_bd_pins rst_clk_wiz_100M/peripheral_aresetn] \
  [get_bd_pins test_pattern_generator_gpio_adapter_0/reset_n_i]
connect_bd_intf_net \
  [get_bd_intf_pins axi_gpio_test_ctrl/GPIO] \
  [get_bd_intf_pins \
    test_pattern_generator_gpio_adapter_0/CONTROL_GPIO]
connect_bd_intf_net \
  [get_bd_intf_pins axi_gpio_test_ctrl/GPIO2] \
  [get_bd_intf_pins \
    test_pattern_generator_gpio_adapter_0/STATUS_GPIO]

if {[catch {validate_bd_design} validation_error]} {
  error "STEP_2_VALIDATE_FAILED: $validation_error"
}
puts "VALIDATE DESIGN WITH GENERATOR: PASS"

set expected_generator_vlnv \
  {xilinx.com:module_ref:test_pattern_generator_gpio_adapter:1.0}
set generator_vlnv [get_property VLNV $generator]
if {$generator_vlnv ne $expected_generator_vlnv} {
  error "Unexpected module reference VLNV: $generator_vlnv"
}
if {[get_property SELECTED_SIM_MODEL $generator] ne "rtl"} {
  error "Generator module reference is not using the RTL model"
}

foreach pin_name {clk_i reset_n_i control_i status_o probe_test_o} {
  if {[llength \
      [get_bd_pins -quiet \
        test_pattern_generator_gpio_adapter_0/$pin_name]] != 1} {
    error "Generator pin is missing: $pin_name"
  }
}

set generator_clock_net [get_bd_nets -quiet -of_objects \
  [get_bd_pins test_pattern_generator_gpio_adapter_0/clk_i]]
set common_clock_net [get_bd_nets -quiet -of_objects \
  [get_bd_pins clk_wiz/clk_out1]]
if {$generator_clock_net ne $common_clock_net} {
  error "Generator clock is not the common 100 MHz clock"
}

set generator_reset_net [get_bd_nets -quiet -of_objects \
  [get_bd_pins test_pattern_generator_gpio_adapter_0/reset_n_i]]
set common_reset_net [get_bd_nets -quiet -of_objects \
  [get_bd_pins rst_clk_wiz_100M/peripheral_aresetn]]
if {$generator_reset_net ne $common_reset_net} {
  error "Generator reset is not peripheral_aresetn"
}

if {[llength [get_bd_intf_nets -quiet -of_objects \
    [get_bd_intf_pins \
      test_pattern_generator_gpio_adapter_0/CONTROL_GPIO]]] != 1} {
  error "Generator CONTROL_GPIO interface is unconnected"
}
if {[llength [get_bd_intf_nets -quiet -of_objects \
    [get_bd_intf_pins \
      test_pattern_generator_gpio_adapter_0/STATUS_GPIO]]] != 1} {
  error "Generator STATUS_GPIO interface is unconnected"
}

if {[llength [get_bd_cells -hier -quiet \
    -filter {VLNV =~ "xilinx.com:ip:ila:*"}]] != 0} {
  error "ILA must not be added during Step 2"
}

save_bd_design
write_bd_tcl -force [file join \
  $generated_dir base_soc_with_generator_generated.tcl]

puts "TEST_PATTERN_GENERATOR_STEP_2: PASS"
puts "Generator output probe_test_o remains branch-specific."
puts "Step 3 will connect probe_test_o to the Vivado ILA reference."

close_project
