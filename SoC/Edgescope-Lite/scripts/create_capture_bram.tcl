# Create the EdgeScope-Lite capture Block Memory Generator IP.
#
# Run from any directory:
#   vivado -mode batch -source scripts/create_capture_bram.tcl

set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ..]]
set build_dir   [file join $project_dir build vivado_bram]
set ip_root     [file join $project_dir ip]
set ip_xci      [file join $ip_root capture_bram capture_bram.xci]

file mkdir $build_dir
file mkdir $ip_root

create_project -force capture_bram_gen $build_dir \
  -part xc7a35tcpg236-1

if {[file exists $ip_xci]} {
  read_ip [list $ip_xci]
} else {
  create_ip -name blk_mem_gen \
    -vendor xilinx.com \
    -library ip \
    -version 8.4 \
    -module_name capture_bram \
    -dir $ip_root
}

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
  CONFIG.Load_Init_File {false} \
  CONFIG.Use_RSTA_Pin {false} \
  CONFIG.Use_RSTB_Pin {false} \
] [get_ips capture_bram]

generate_target all [get_ips capture_bram]
create_ip_run -force [get_ips capture_bram]
launch_runs capture_bram_synth_1 -jobs 2
wait_on_run capture_bram_synth_1

set run_status [get_property STATUS [get_runs capture_bram_synth_1]]
puts "capture_bram synthesis status: $run_status"

if {![string match "*Complete*" $run_status]} {
  error "capture_bram out-of-context synthesis failed"
}

set generated_report [file join \
  $build_dir capture_bram_gen.runs capture_bram_synth_1 \
  capture_bram_utilization_synth.rpt]
set final_report \
  [file join $project_dir build capture_bram_utilization.rpt]

if {![file exists $generated_report]} {
  error "capture_bram utilization report was not generated"
}
file copy -force $generated_report $final_report

set report_channel [open $final_report r]
set report_text [read $report_channel]
close $report_channel
if {![regexp {\|\s*RAMB36E1\s*\|\s*1\s*\|} $report_text]} {
  error "capture_bram did not synthesize to exactly one RAMB36E1"
}

puts "capture_bram XCI: $ip_xci"
puts "Capture geometry: 1024 x 32-bit, true dual port, 4 KiB"
puts "Capture resource check: exactly one RAMB36E1"

close_project
