# Build and validate a standalone AXI BRAM Controller + capture BMG subsystem.
# This proves the Catalog IP connection before it is copied into the team BD.

set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ..]]
set build_dir   [file join $project_dir build bram_subsystem_bd]

file mkdir $build_dir

create_project -force bram_subsystem_bd $build_dir \
  -part xc7a35tcpg236-1

create_bd_design capture_bram_subsystem

set axi_bram_ctrl [create_bd_cell -type ip \
  -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 axi_bram_ctrl_0]
set_property -dict [list \
  CONFIG.DATA_WIDTH {32} \
  CONFIG.SINGLE_PORT_BRAM {1} \
] $axi_bram_ctrl

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

connect_bd_intf_net \
  [get_bd_intf_pins axi_bram_ctrl_0/BRAM_PORTA] \
  [get_bd_intf_pins capture_bram/BRAM_PORTB]

make_bd_intf_pins_external \
  [get_bd_intf_pins axi_bram_ctrl_0/S_AXI]
set_property name S_AXI [get_bd_intf_ports S_AXI_0]

make_bd_intf_pins_external \
  [get_bd_intf_pins capture_bram/BRAM_PORTA]
set_property name CAPTURE_PORT_A [get_bd_intf_ports BRAM_PORTA_0]
set_property -dict [list \
  CONFIG.MEM_SIZE {4096} \
  CONFIG.MEM_WIDTH {32} \
  CONFIG.READ_LATENCY {1} \
] [get_bd_intf_ports CAPTURE_PORT_A]

create_bd_port -dir I -type clk -freq_hz 100000000 s_axi_aclk
set_property -dict [list \
  CONFIG.FREQ_HZ {100000000} \
  CONFIG.ASSOCIATED_BUSIF {S_AXI} \
  CONFIG.ASSOCIATED_RESET {s_axi_aresetn} \
] [get_bd_ports s_axi_aclk]

create_bd_port -dir I -type rst s_axi_aresetn
set_property CONFIG.POLARITY ACTIVE_LOW [get_bd_ports s_axi_aresetn]

connect_bd_net \
  [get_bd_ports s_axi_aclk] \
  [get_bd_pins axi_bram_ctrl_0/s_axi_aclk]
connect_bd_net \
  [get_bd_ports s_axi_aresetn] \
  [get_bd_pins axi_bram_ctrl_0/s_axi_aresetn]

assign_bd_address \
  -offset 0x00000000 \
  -range 0x00001000 \
  -target_address_space [get_bd_addr_spaces S_AXI] \
  [get_bd_addr_segs axi_bram_ctrl_0/S_AXI/Mem0] \
  -force

validate_bd_design

set propagated_depth \
  [get_property CONFIG.Write_Depth_A $capture_bram]
if {$propagated_depth != 1024} {
  error "BRAM geometry propagation failed: depth=$propagated_depth, expected=1024"
}

save_bd_design

generate_target all \
  [get_files capture_bram_subsystem.bd]

write_bd_tcl -force \
  [file join $project_dir build capture_bram_subsystem_generated.tcl]

puts "Validated: AXI BRAM Controller BRAM_PORTA -> capture_bram BRAM_PORTB"
puts "External CAPTURE_PORT_A is reserved for Circular Trace Buffer writes"
puts "Validated propagated BRAM geometry: 1024 x 32-bit / 4096 bytes"

close_project
