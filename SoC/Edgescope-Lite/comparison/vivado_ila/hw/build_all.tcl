# Build comparison C through bitstream and export its XSA, LTX, and reports.
#
# Prerequisite:
#   vivado -mode batch \
#     -source comparison/vivado_ila/hw/block_design.tcl
#
# Run:
#   vivado -mode batch -source comparison/vivado_ila/hw/build_all.tcl

set script_dir [file dirname [file normalize [info script]]]
set project_file [file join $script_dir build vivado_ila_reference.xpr]
set report_dir [file normalize [file join $script_dir ../reports]]
set xsa_file [file join $script_dir vivado_ila_reference.xsa]
set bit_file [file join $script_dir vivado_ila_reference.bit]
set ltx_file [file join $script_dir vivado_ila_reference.ltx]

if {![file exists $project_file]} {
  error "C project is missing. Run block_design.tcl first: $project_file"
}

set jobs 4
if {[info exists ::env(EDGESCOPE_JOBS)] &&
    [string is integer -strict $::env(EDGESCOPE_JOBS)] &&
    $::env(EDGESCOPE_JOBS) > 0} {
  set jobs $::env(EDGESCOPE_JOBS)
}

file mkdir $report_dir
open_project $project_file
set_property top base_soc_wrapper [current_fileset]
update_compile_order -fileset sources_1

puts "VIVADO_ILA_BUILD: synthesis start"
launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
if {[string first "Complete" $synth_status] < 0} {
  error "VIVADO_ILA_BUILD: synthesis failed: $synth_status"
}

puts "VIVADO_ILA_BUILD: implementation/bitstream start"
launch_runs impl_1 -to_step write_bitstream -jobs $jobs
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
if {[string first "Complete" $impl_status] < 0} {
  error "VIVADO_ILA_BUILD: implementation failed: $impl_status"
}

open_run impl_1
report_utilization -file [file join $report_dir utilization.rpt]
report_utilization -hierarchical \
  -file [file join $report_dir hierarchical_utilization.rpt]
report_timing_summary -file [file join $report_dir timing_summary.rpt]
report_drc -file [file join $report_dir drc.rpt]

set impl_dir [get_property DIRECTORY [get_runs impl_1]]
set generated_bit [file join $impl_dir base_soc_wrapper.bit]
if {![file exists $generated_bit]} {
  error "Implemented bitstream was not found: $generated_bit"
}
file copy -force $generated_bit $bit_file

# LTX is deliberately exported next to the fixed BIT so GUI/JTAG automation
# can use stable paths independent of Vivado's run directory.
write_debug_probes -force $ltx_file
if {![file exists $ltx_file]} {
  error "Debug probes file was not generated: $ltx_file"
}

write_hw_platform -fixed -include_bit -force $xsa_file
if {![file exists $xsa_file]} {
  error "Hardware platform was not generated: $xsa_file"
}

puts "VIVADO_ILA_BUILD: PASS"
puts "VIVADO_ILA_BUILD: XSA=$xsa_file"
puts "VIVADO_ILA_BUILD: BIT=$bit_file"
puts "VIVADO_ILA_BUILD: LTX=$ltx_file"
puts "VIVADO_ILA_BUILD: REPORTS=$report_dir"
close_project
