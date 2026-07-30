# EdgeScope-Lite (comparison B) overlay for the frozen common Base SoC.
#
# Run:
#   vivado -mode batch -source comparison/edgescope_lite/hw/block_design.tcl

set b_script_dir [file dirname [file normalize [info script]]]
set b_repo_root [file normalize [file join $b_script_dir ../../..]]
set b_base_tcl [file join $b_repo_root comparison common base_soc.tcl]
set b_build_dir [file join $b_script_dir build]
set b_project_name {edgescope_lite_reference}

if {![file exists $b_base_tcl]} {
  error "Common Base SoC script is missing: $b_base_tcl"
}

# Recreate the frozen base, reopen it, then clone it so A and B never share a
# mutated Vivado project.
source $b_base_tcl
set b_base_project [file join $b_repo_root comparison common build base_soc \
  edgescope_comparison_base.xpr]
if {![file exists $b_base_project]} {
  error "Common Base project was not generated: $b_base_project"
}
open_project $b_base_project
file mkdir $b_build_dir
save_project_as -force $b_project_name $b_build_dir

set bd_file_candidates [get_files -quiet */base_soc.bd]
if {[llength $bd_file_candidates] != 1} {
  error "Expected one base_soc.bd, found: $bd_file_candidates"
}
open_bd_design [lindex $bd_file_candidates 0]
current_bd_design base_soc

set_property ip_repo_paths [list [file join $b_repo_root ip_repo]] \
  [current_project]
update_ip_catalog
foreach vlnv {
  user.org:user:probe_sampler:1.0
  user.org:user:basic_trigger_engine:1.0
  user.org:user:circular_trace_buffer:1.0
} {
  if {[llength [get_ipdefs -all -quiet $vlnv]] != 1} {
    error "Required packaged IP is missing: $vlnv"
  }
}

# Common deterministic stimulus (the same generator used by comparison A).
set generator_source [file join $b_repo_root comparison common rtl \
  test_pattern_generator.sv]
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

set sampler [create_bd_cell -type ip \
  -vlnv user.org:user:probe_sampler:1.0 probe_sampler_0]
set trigger [create_bd_cell -type ip \
  -vlnv user.org:user:basic_trigger_engine:1.0 basic_trigger_engine_0]
set trace [create_bd_cell -type ip \
  -vlnv user.org:user:circular_trace_buffer:1.0 circular_trace_buffer_0]

connect_bd_net [get_bd_pins $generator/probe_test_o] \
  [get_bd_pins $sampler/probe_i]
connect_bd_net [get_bd_pins $sampler/sample_data_o] \
  [get_bd_pins $trigger/sample_data_i] \
  [get_bd_pins $trace/sample_data_i]
connect_bd_net [get_bd_pins $sampler/sample_valid_o] \
  [get_bd_pins $trigger/sample_valid_i] \
  [get_bd_pins $trace/sample_valid_i]
connect_bd_net [get_bd_pins $trigger/trigger_pulse_o] \
  [get_bd_pins $trace/trigger_pulse_i]

# Capture memory: analyzer writes Port A, MicroBlaze reads Port B.
set capture_bram [create_bd_cell -type ip \
  -vlnv xilinx.com:ip:blk_mem_gen:8.4 capture_bram]
set_property -dict [list \
  CONFIG.Memory_Type {True_Dual_Port_RAM} \
  CONFIG.Enable_32bit_Address {true} \
  CONFIG.Assume_Synchronous_Clk {true} \
  CONFIG.Use_Byte_Write_Enable {true} \
  CONFIG.Byte_Size {8} \
  CONFIG.Write_Width_A {32} \
  CONFIG.Write_Depth_A {1024} \
  CONFIG.Read_Width_A {32} \
  CONFIG.Write_Width_B {32} \
  CONFIG.Read_Width_B {32} \
  CONFIG.Enable_A {Use_ENA_Pin} \
  CONFIG.Enable_B {Use_ENB_Pin} \
  CONFIG.Register_PortA_Output_of_Memory_Primitives {false} \
  CONFIG.Register_PortB_Output_of_Memory_Primitives {false} \
] $capture_bram

set bram_ctrl [create_bd_cell -type ip \
  -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 axi_bram_ctrl_capture]
set_property -dict [list \
  CONFIG.DATA_WIDTH {32} \
  CONFIG.SINGLE_PORT_BRAM {1} \
] $bram_ctrl

connect_bd_intf_net \
  [get_bd_intf_pins $trace/BRAM_PORTA] \
  [get_bd_intf_pins $capture_bram/BRAM_PORTA]
connect_bd_intf_net \
  [get_bd_intf_pins $bram_ctrl/BRAM_PORTA] \
  [get_bd_intf_pins $capture_bram/BRAM_PORTB]

# Four additional AXI targets: sampler, trigger, trace CSRs, capture memory.
set interconnect [get_bd_cells microblaze_riscv_0_axi_periph]
set_property CONFIG.NUM_MI {8} $interconnect
foreach {mi peripheral} {
  M04_AXI probe_sampler_0/s_axi
  M05_AXI basic_trigger_engine_0/s_axi
  M06_AXI circular_trace_buffer_0/s_axi
  M07_AXI axi_bram_ctrl_capture/S_AXI
} {
  connect_bd_intf_net \
    [get_bd_intf_pins $interconnect/$mi] \
    [get_bd_intf_pins $peripheral]
}

set clock [get_bd_pins clk_wiz/clk_out1]
set resetn [get_bd_pins rst_clk_wiz_100M/peripheral_aresetn]
foreach index {04 05 06 07} {
  connect_bd_net $clock [get_bd_pins $interconnect/M${index}_ACLK]
  connect_bd_net $resetn [get_bd_pins $interconnect/M${index}_ARESETN]
}
connect_bd_net $clock \
  [get_bd_pins $sampler/s_axi_aclk] \
  [get_bd_pins $trigger/s_axi_aclk] \
  [get_bd_pins $trace/s_axi_aclk] \
  [get_bd_pins $bram_ctrl/s_axi_aclk]
connect_bd_net $resetn \
  [get_bd_pins $sampler/s_axi_aresetn] \
  [get_bd_pins $trigger/s_axi_aresetn] \
  [get_bd_pins $trace/s_axi_aresetn] \
  [get_bd_pins $bram_ctrl/s_axi_aresetn]

# Keep the trace completion interrupt connected even though the first app
# intentionally polls STATUS.DONE for a transparent demonstration.
set concat [get_bd_cells microblaze_riscv_0_xlconcat]
set_property CONFIG.NUM_PORTS {3} $concat
connect_bd_net [get_bd_pins $trace/irq_o] [get_bd_pins $concat/In2]

set data_space [get_bd_addr_spaces microblaze_riscv_0/Data]
foreach {offset range segment} {
  0x40010000 0x00001000 probe_sampler_0/s_axi/reg0
  0x40020000 0x00001000 basic_trigger_engine_0/s_axi/reg0
  0x40030000 0x00001000 circular_trace_buffer_0/s_axi/reg0
  0x42000000 0x00001000 axi_bram_ctrl_capture/S_AXI/Mem0
} {
  assign_bd_address -offset $offset -range $range \
    -target_address_space $data_space \
    [get_bd_addr_segs $segment] -force
}

validate_bd_design

# Propagation must not silently double the 1,024-word capture BRAM.
set propagated_depth [get_property CONFIG.Write_Depth_A $capture_bram]
if {$propagated_depth != 1024} {
  error "Capture BRAM depth=$propagated_depth, expected=1024"
}
if {[get_property CONFIG.Write_Width_A $capture_bram] != 32} {
  error "Capture BRAM width changed during propagation"
}

save_bd_design
generate_target all [get_files */base_soc.bd]
set wrapper [make_wrapper -files [get_files */base_soc.bd] -top]
add_files -norecurse $wrapper
set_property top base_soc_wrapper [current_fileset]
update_compile_order -fileset sources_1

write_bd_tcl -force [file join $b_script_dir edgescope_lite_generated.tcl]
puts "EDGESCOPE_LITE_BD: PASS"
puts "Project: [file join $b_build_dir ${b_project_name}.xpr]"
puts "Sampler CSR: 0x40010000"
puts "Trigger CSR: 0x40020000"
puts "Trace CSR:   0x40030000"
puts "Capture RAM: 0x42000000 (4 KiB)"
close_project
