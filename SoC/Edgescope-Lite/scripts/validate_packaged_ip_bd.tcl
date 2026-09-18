# Validate the packaged Trace Buffer IP in a reproducible Block Design.

set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ..]]
set build_dir   [file join $project_dir build packaged_ip_bd]
set ip_repo_dir [file join $project_dir ip_repo]

file mkdir $build_dir

create_project -force packaged_ip_bd $build_dir \
  -part xc7a35tcpg236-1

set_property ip_repo_paths [list $ip_repo_dir] [current_project]
update_ip_catalog

if {[llength [get_ipdefs -all \
    user.org:user:circular_trace_buffer:1.0]] != 1} {
  error "Packaged circular_trace_buffer IP was not found in the catalog"
}

create_bd_design packaged_trace_buffer_system

create_bd_cell -type ip \
  -vlnv user.org:user:circular_trace_buffer:1.0 trace_buffer_0

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
] $capture_bram

set axi_bram_ctrl [create_bd_cell -type ip \
  -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 axi_bram_ctrl_0]
set_property -dict [list \
  CONFIG.DATA_WIDTH {32} \
  CONFIG.SINGLE_PORT_BRAM {1} \
] $axi_bram_ctrl

connect_bd_intf_net \
  [get_bd_intf_pins trace_buffer_0/BRAM_PORTA] \
  [get_bd_intf_pins capture_bram/BRAM_PORTA]
connect_bd_intf_net \
  [get_bd_intf_pins axi_bram_ctrl_0/BRAM_PORTA] \
  [get_bd_intf_pins capture_bram/BRAM_PORTB]

make_bd_intf_pins_external \
  [get_bd_intf_pins trace_buffer_0/s_axi]
set_property name TRACE_S_AXI [get_bd_intf_ports s_axi_0]

make_bd_intf_pins_external \
  [get_bd_intf_pins axi_bram_ctrl_0/S_AXI]
set_property name MEMORY_S_AXI [get_bd_intf_ports S_AXI_0]

create_bd_port -dir I -type clk -freq_hz 100000000 s_axi_aclk
set_property -dict [list \
  CONFIG.FREQ_HZ {100000000} \
  CONFIG.ASSOCIATED_BUSIF {TRACE_S_AXI:MEMORY_S_AXI} \
  CONFIG.ASSOCIATED_RESET {s_axi_aresetn} \
] [get_bd_ports s_axi_aclk]

create_bd_port -dir I -type rst s_axi_aresetn
set_property CONFIG.POLARITY ACTIVE_LOW [get_bd_ports s_axi_aresetn]

connect_bd_net \
  [get_bd_ports s_axi_aclk] \
  [get_bd_pins trace_buffer_0/s_axi_aclk] \
  [get_bd_pins axi_bram_ctrl_0/s_axi_aclk]
connect_bd_net \
  [get_bd_ports s_axi_aresetn] \
  [get_bd_pins trace_buffer_0/s_axi_aresetn] \
  [get_bd_pins axi_bram_ctrl_0/s_axi_aresetn]

make_bd_pins_external [get_bd_pins trace_buffer_0/sample_data_i]
set_property name sample_data_i [get_bd_ports sample_data_i_0]
make_bd_pins_external [get_bd_pins trace_buffer_0/sample_valid_i]
set_property name sample_valid_i [get_bd_ports sample_valid_i_0]
make_bd_pins_external [get_bd_pins trace_buffer_0/trigger_pulse_i]
set_property name trigger_pulse_i [get_bd_ports trigger_pulse_i_0]
make_bd_pins_external [get_bd_pins trace_buffer_0/irq_o]
set_property name irq_o [get_bd_ports irq_o_0]

assign_bd_address \
  -offset 0x00000000 \
  -range 0x00001000 \
  -target_address_space [get_bd_addr_spaces TRACE_S_AXI] \
  [get_bd_addr_segs trace_buffer_0/s_axi/reg0] \
  -force

assign_bd_address \
  -offset 0x00000000 \
  -range 0x00001000 \
  -target_address_space [get_bd_addr_spaces MEMORY_S_AXI] \
  [get_bd_addr_segs axi_bram_ctrl_0/S_AXI/Mem0] \
  -force

validate_bd_design

set propagated_depth \
  [get_property CONFIG.Write_Depth_A $capture_bram]
if {$propagated_depth != 1024} {
  error "Packaged BD BRAM depth=$propagated_depth, expected=1024"
}

save_bd_design
generate_target all [get_files packaged_trace_buffer_system.bd]

write_bd_tcl -force \
  [file join $project_dir build packaged_trace_buffer_system_generated.tcl]

set wrapper_files \
  [make_wrapper -files [get_files packaged_trace_buffer_system.bd] -top]
add_files -norecurse [list $wrapper_files]
set_property top packaged_trace_buffer_system_wrapper [current_fileset]
update_compile_order -fileset sources_1

launch_runs synth_1 -jobs 2
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
if {![string match "*Complete*" $synth_status]} {
  error "Packaged Trace Buffer system synthesis failed: $synth_status"
}

open_run synth_1
report_utilization -file \
  [file join $project_dir build packaged_trace_buffer_system_utilization.rpt]

set integrated_bram_count \
  [llength [get_cells -hierarchical -filter {REF_NAME == RAMB36E1}]]
if {$integrated_bram_count != 1} {
  error "Integrated system uses $integrated_bram_count RAMB36E1, expected 1"
}

write_checkpoint -force \
  [file join $project_dir build packaged_trace_buffer_system_synth.dcp]

puts "Packaged IP catalog and Block Design validation: PASS"
puts "Validated propagated BRAM geometry: 1024 x 32-bit / 4096 bytes"
puts "Integrated packaged system synthesis: exactly one RAMB36E1"
close_project
