# Build the generated CPU Polling reference project through bitstream and XSA.
#
# Prerequisite:
#   vivado -mode batch -source comparison/cpu_polling/hw/block_design.tcl
#
# Run:
#   vivado -mode batch -source comparison/cpu_polling/hw/build_all.tcl

set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ../../..]]
set project_file [file join $repo_root comparison common build base_soc \
    edgescope_comparison_base.xpr]
set report_dir [file join $repo_root comparison cpu_polling reports]
set xsa_file [file join $script_dir cpu_polling_reference.xsa]

if {![file exists $project_file]} {
    error "CPU Polling project is missing. Run block_design.tcl first: $project_file"
}

set jobs 4
if {[info exists ::env(CPU_POLL_JOBS)] &&
    [string is integer -strict $::env(CPU_POLL_JOBS)] &&
    $::env(CPU_POLL_JOBS) > 0} {
    set jobs $::env(CPU_POLL_JOBS)
}

file mkdir $report_dir
open_project $project_file
set_property top base_soc_wrapper [current_fileset]
update_compile_order -fileset sources_1

puts "CPU_POLL_BUILD: synthesis start"
launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
if {[string first "Complete" $synth_status] < 0} {
    error "CPU_POLL_BUILD: synthesis failed with status '$synth_status'"
}
puts "CPU_POLL_BUILD: synthesis complete"

puts "CPU_POLL_BUILD: implementation/bitstream start"
launch_runs impl_1 -to_step write_bitstream -jobs $jobs
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
if {[string first "Complete" $impl_status] < 0} {
    error "CPU_POLL_BUILD: implementation failed with status '$impl_status'"
}
puts "CPU_POLL_BUILD: implementation/bitstream complete"

open_run impl_1
report_utilization -file [file join $report_dir utilization.rpt]
report_utilization -hierarchical \
    -file [file join $report_dir hierarchical_utilization.rpt]
report_timing_summary -file [file join $report_dir timing_summary.rpt]
report_drc -file [file join $report_dir drc.rpt]

write_hw_platform -fixed -include_bit -force $xsa_file

puts "CPU_POLL_BUILD: PASS"
puts "CPU_POLL_BUILD: XSA=$xsa_file"
puts "CPU_POLL_BUILD: REPORTS=$report_dir"
close_project
