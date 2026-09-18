# Synthesize the packaged RTL top and check the 100 MHz OOC timing target.

set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ..]]
set build_dir   [file join $project_dir build trace_buffer_synth]

file mkdir $build_dir

create_project -force trace_buffer_synth $build_dir \
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

add_files -fileset constrs_1 -norecurse \
  [list [file join $project_dir constraints circular_trace_buffer_ooc.xdc]]

set_property top circular_trace_buffer_ip [current_fileset]
update_compile_order -fileset sources_1

synth_design \
  -top circular_trace_buffer_ip \
  -part xc7a35tcpg236-1 \
  -mode out_of_context

opt_design
place_design
route_design

report_utilization \
  -file [file join $project_dir build trace_buffer_utilization.rpt]
report_timing_summary \
  -delay_type min_max \
  -max_paths 10 \
  -file [file join $project_dir build trace_buffer_timing_summary.rpt]
report_route_status \
  -file [file join $project_dir build trace_buffer_route_status.rpt]

set setup_paths [get_timing_paths -delay_type max -max_paths 1]
set hold_paths  [get_timing_paths -delay_type min -max_paths 1]
set setup_slack [get_property SLACK $setup_paths]
set hold_slack  [get_property SLACK $hold_paths]

puts "Trace Buffer setup slack at 100 MHz: $setup_slack ns"
puts "Trace Buffer hold slack: $hold_slack ns"
if {$setup_slack < 0.0 || $hold_slack < 0.0} {
  error "Trace Buffer failed setup/hold timing"
}

set unrouted_nets [get_nets -quiet -hierarchical -filter {
  ROUTE_STATUS == "UNROUTED" || ROUTE_STATUS == "PARTIALLY_ROUTED"
}]
if {[llength $unrouted_nets] != 0} {
  error "Trace Buffer has [llength $unrouted_nets] unrouted/partial nets"
}

write_checkpoint -force \
  [file join $project_dir build circular_trace_buffer_ip_routed.dcp]

puts "Trace Buffer routed implementation and 100 MHz timing: PASS"
close_project
