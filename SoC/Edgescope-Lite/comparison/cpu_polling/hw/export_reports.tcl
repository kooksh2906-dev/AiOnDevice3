# Run after opening the implemented CPU Polling resource build.

if {[get_property STATUS [current_run]] ni {
    "route_design Complete!" "write_bitstream Complete!"
}} {
    error "Open a completed implementation run before exporting reports."
}

set script_dir [file dirname [file normalize [info script]]]
set report_dir [file normalize [file join $script_dir ../reports]]
file mkdir $report_dir

report_utilization -file [file join $report_dir utilization.rpt]
report_utilization -hierarchical \
    -file [file join $report_dir hierarchical_utilization.rpt]
report_timing_summary -file [file join $report_dir timing_summary.rpt]
report_drc -file [file join $report_dir drc.rpt]

puts "CPU Polling reports exported to $report_dir"
