# Build comparison B through bitstream and export a fixed XSA.
#
# Prerequisite:
#   vivado -mode batch -source comparison/edgescope_lite/hw/block_design.tcl

set script_dir [file dirname [file normalize [info script]]]
set project_file [file join $script_dir build edgescope_lite_reference.xpr]
set report_dir [file normalize [file join $script_dir ../reports]]
set xsa_file [file join $script_dir edgescope_lite_reference.xsa]

if {![file exists $project_file]} {
  error "B project is missing. Run block_design.tcl first."
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

puts "EDGESCOPE_BUILD: synthesis start"
launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
if {[string first "Complete" $synth_status] < 0} {
  error "EDGESCOPE_BUILD: synthesis failed: $synth_status"
}

puts "EDGESCOPE_BUILD: implementation/bitstream start"
launch_runs impl_1 -to_step write_bitstream -jobs $jobs
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
if {[string first "Complete" $impl_status] < 0} {
  error "EDGESCOPE_BUILD: implementation failed: $impl_status"
}

open_run impl_1
report_utilization -file [file join $report_dir utilization.rpt]
report_utilization -hierarchical \
  -file [file join $report_dir hierarchical_utilization.rpt]
report_timing_summary -file [file join $report_dir timing_summary.rpt]
report_drc -file [file join $report_dir drc.rpt]
write_hw_platform -fixed -include_bit -force $xsa_file

set bit_candidates [get_files -quiet -of_objects [get_runs impl_1] *.bit]
puts "EDGESCOPE_BUILD: PASS"
puts "EDGESCOPE_BUILD: XSA=$xsa_file"
puts "EDGESCOPE_BUILD: REPORTS=$report_dir"
puts "EDGESCOPE_BUILD: BIT=$bit_candidates"
close_project
