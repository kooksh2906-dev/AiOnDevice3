# Package Circular Trace Buffer as user.org:user:circular_trace_buffer:1.0.

set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ..]]
set build_dir   [file join $project_dir build ip_package]
set package_dir [file join $project_dir ip_repo circular_trace_buffer_1_0]

file mkdir [file dirname $package_dir]
file delete -force $build_dir
file delete -force $package_dir

create_project -force circular_trace_buffer_package $build_dir \
  -part xc7a35tcpg236-1
set_property target_language Verilog [current_project]

add_files -norecurse [list \
  [file join $project_dir rtl include logic_analyzer_pkg.sv] \
  [file join $project_dir rtl core circular_trace_buffer_core.sv] \
  [file join $project_dir rtl bus circular_trace_buffer_axi.sv] \
  [file join $project_dir rtl top capture_bram_addr_adapter.sv] \
  [file join $project_dir rtl top circular_trace_buffer_ip.sv] \
]

set_property file_type SystemVerilog [get_files *.sv]
set_property top circular_trace_buffer_ip [current_fileset]
update_compile_order -fileset sources_1

ipx::package_project \
  -root_dir $package_dir \
  -vendor user.org \
  -library user \
  -taxonomy /UserIP \
  -import_files \
  -set_current true

set core [ipx::current_core]
set_property name {circular_trace_buffer} $core
set_property display_name {EdgeScope Circular Trace Buffer} $core
set_property description \
  {1024-sample circular capture buffer with 512/512 trigger split and AXI4-Lite control} \
  $core
set_property vendor_display_name {EdgeScope-Lite Team} $core
set_property version {1.0} $core
set_property supported_families {artix7 Production} $core

# Infer S_AXI, its clock and active-low reset from standard port names.
ipx::infer_bus_interfaces xilinx.com:interface:aximm_rtl:1.0 $core
ipx::infer_bus_interfaces xilinx.com:signal:clock_rtl:1.0 $core
ipx::infer_bus_interfaces xilinx.com:signal:reset_rtl:1.0 $core

set axi_if [ipx::get_bus_interfaces -of_objects $core s_axi]
if {[llength $axi_if] != 1} {
  error "S_AXI interface inference failed"
}
set_property interface_mode slave $axi_if

set clk_if [ipx::get_bus_interfaces -of_objects $core s_axi_aclk]
if {[llength $clk_if] != 1} {
  error "s_axi_aclk interface inference failed"
}
# AXI, clock and reset association parameters are added by inference.
set freq_hz [ipx::add_bus_parameter FREQ_HZ $clk_if]
set_property value {100000000} $freq_hz

# Add a standard BRAM master interface for direct connection to BMG Port A.
set bram_if [ipx::add_bus_interface BRAM_PORTA $core]
set_property abstraction_type_vlnv \
  xilinx.com:interface:bram_rtl:1.0 $bram_if
set_property bus_type_vlnv \
  xilinx.com:interface:bram:1.0 $bram_if
set_property interface_mode master $bram_if

foreach {parameter_name parameter_value} {
  MASTER_TYPE      BRAM_CTRL
  MEM_ADDRESS_MODE BYTE_ADDRESS
  MEM_SIZE         4096
  MEM_WIDTH        32
  READ_LATENCY     1
} {
  set bus_parameter [ipx::add_bus_parameter $parameter_name $bram_if]
  set_property value $parameter_value $bus_parameter
}

foreach {logical physical} {
  CLK  bram_clk_o
  RST  bram_rst_o
  EN   bram_en_o
  WE   bram_we_o
  ADDR bram_addr_o
  DIN  bram_wrdata_o
  DOUT bram_rddata_i
} {
  set port_map [ipx::add_port_map $logical $bram_if]
  set_property physical_name $physical $port_map
}

# Register irq_o as an active-high level interrupt so Vivado Block Automation
# can connect it to an interrupt controller with the correct sensitivity.
set interrupt_if [ipx::add_bus_interface irq $core]
set_property abstraction_type_vlnv \
  xilinx.com:signal:interrupt_rtl:1.0 $interrupt_if
set_property bus_type_vlnv \
  xilinx.com:signal:interrupt:1.0 $interrupt_if
set_property interface_mode master $interrupt_if

set interrupt_port_map [ipx::add_port_map INTERRUPT $interrupt_if]
set_property physical_name irq_o $interrupt_port_map

set interrupt_sensitivity \
  [ipx::add_bus_parameter SENSITIVITY $interrupt_if]
set_property value {LEVEL_HIGH} $interrupt_sensitivity

ipx::create_xgui_files $core
# package_project initially creates an XGUI file from the HDL top name. The
# final core name above creates the canonical file referenced by component.xml.
file delete -force \
  [file join $package_dir xgui circular_trace_buffer_ip_v1_0.tcl]
ipx::update_checksums $core
set integrity_ok [ipx::check_integrity -quiet $core]
if {!$integrity_ok} {
  error "Packaged IP integrity check failed"
}
ipx::save_core $core

puts "Packaged: $package_dir"
puts "VLNV: user.org:user:circular_trace_buffer:1.0"

close_project
