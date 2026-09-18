# Step 5: synthesize and implement the Vivado ILA reference, then export a
# matched routed checkpoint, bitstream, and debug-probes file.
#
# Prerequisite:
#   comparison/ila_reference/build_step4_trigger_profiles.tcl
#
# The reproducible entry point is:
#   comparison/ila_reference/run_step5_build.sh

set step5_required_vivado_version {2024.2}
set step5_required_part {xc7a35tcpg236-1}
set step5_required_board_part {digilentinc.com:basys3:part0:1.2}
set step5_resume_existing_runs 0
if {$argc == 1 && [lindex $argv 0] eq {--resume}} {
  set step5_resume_existing_runs 1
} elseif {$argc != 0} {
  error "STEP5_USAGE: use no argument for a clean run or --resume"
}

set step5_script_dir [file dirname [file normalize [info script]]]
set step5_common_dir [file normalize [file join \
  $step5_script_dir .. common]]
set step5_project_file [file join \
  $step5_common_dir build base_soc edgescope_comparison_base.xpr]
set step5_output_dir [file join $step5_script_dir build step5]
set step5_generated_dir [file join $step5_script_dir generated]
set step5_debug_hub_xdc [file join \
  $step5_script_dir constraints ila_debug_hub.xdc]

set step5_routed_dcp [file join \
  $step5_output_dir edgescope_ila_reference_routed.dcp]
set step5_bitstream [file join \
  $step5_output_dir edgescope_ila_reference.bit]
set step5_ltx [file join \
  $step5_output_dir debug_nets.ltx]

set step5_timing_report [file join \
  $step5_generated_dir ila_reference_step5_timing_summary.rpt]
set step5_check_timing_report [file join \
  $step5_generated_dir ila_reference_step5_check_timing.rpt]
set step5_bus_skew_report [file join \
  $step5_generated_dir ila_reference_step5_bus_skew.rpt]
set step5_utilization_report [file join \
  $step5_generated_dir ila_reference_step5_utilization.rpt]
set step5_hier_utilization_report [file join \
  $step5_generated_dir ila_reference_step5_hierarchical_utilization.rpt]
set step5_route_report [file join \
  $step5_generated_dir ila_reference_step5_route_status.rpt]
set step5_drc_report [file join \
  $step5_generated_dir ila_reference_step5_drc.rpt]
set step5_methodology_report [file join \
  $step5_generated_dir ila_reference_step5_methodology.rpt]
set step5_cdc_report [file join \
  $step5_generated_dir ila_reference_step5_cdc.rpt]
set step5_io_report [file join \
  $step5_generated_dir ila_reference_step5_io.rpt]
set step5_clock_report [file join \
  $step5_generated_dir ila_reference_step5_clocks.rpt]
set step5_clock_utilization_report [file join \
  $step5_generated_dir ila_reference_step5_clock_utilization.rpt]
set step5_debug_report [file join \
  $step5_generated_dir ila_reference_step5_debug_cores.rpt]
set step5_manifest [file join \
  $step5_generated_dir ila_reference_step5_build_manifest.rpt]
set step5_checksums [file join \
  $step5_generated_dir ila_reference_step5_SHA256SUMS]

proc step5_fail {message} {
  error "ILA_STEP_5_ASSERTION_FAILED: $message"
}

proc step5_assert_equal {label actual expected} {
  if {![string equal -nocase $actual $expected]} {
    step5_fail "$label: actual='$actual', expected='$expected'"
  }
  puts "ASSERT PASS: $label = $actual"
}

proc step5_assert_true {label value} {
  if {![expr {bool($value)}]} {
    step5_fail "$label: expected true, actual='$value'"
  }
  puts "ASSERT PASS: $label"
}

proc step5_assert_run_ok {run_name expected_step} {
  set run_object [get_runs -quiet $run_name]
  if {[llength $run_object] != 1} {
    step5_fail "Run '$run_name' was not found exactly once"
  }

  set progress [get_property PROGRESS $run_object]
  set status [get_property STATUS $run_object]
  set needs_refresh [get_property NEEDS_REFRESH $run_object]

  if {$progress ne {100%} ||
      ![regexp -nocase {complete} $status] ||
      [regexp -nocase {error|fail|cancel} $status]} {
    step5_fail \
      "$run_name did not complete: PROGRESS='$progress', STATUS='$status'"
  }
  if {[expr {bool($needs_refresh)}]} {
    step5_fail "$run_name is stale and NEEDS_REFRESH is true"
  }
  if {![string match -nocase "${expected_step} Complete*" $status]} {
    step5_fail \
      "$run_name stopped at an unexpected step: STATUS='$status'"
  }

  puts \
    "RUN PASS: $run_name PROGRESS=$progress STATUS='$status' NEEDS_REFRESH=$needs_refresh"
}

proc step5_run_is_reusable {run_name expected_step} {
  set run_object [get_runs -quiet $run_name]
  if {[llength $run_object] != 1} {
    return 0
  }
  set progress [get_property PROGRESS $run_object]
  set status [get_property STATUS $run_object]
  set needs_refresh [get_property NEEDS_REFRESH $run_object]
  return [expr {
    $progress eq {100%} &&
    [string match -nocase "${expected_step} Complete*" $status] &&
    ![regexp -nocase {error|fail|cancel} $status] &&
    ![expr {bool($needs_refresh)}]
  }]
}

proc step5_assert_file {label path} {
  if {![file isfile $path]} {
    step5_fail "$label was not created: $path"
  }
  set size [file size $path]
  if {$size <= 0} {
    step5_fail "$label is empty: $path"
  }
  puts "ARTIFACT PASS: $label size=$size path=$path"
}

proc step5_sha256 {path} {
  set result [exec sha256sum -- $path]
  set digest [string tolower [lindex $result 0]]
  if {![regexp {^[0-9a-f]{64}$} $digest]} {
    step5_fail "Invalid SHA-256 result for $path: $digest"
  }
  return $digest
}

proc step5_count_named_cells {glob_pattern} {
  return [llength [get_cells -hier -quiet $glob_pattern]]
}

proc step5_property_exists {object property_name} {
  return [expr {
    [lsearch -exact [list_property $object] $property_name] >= 0
  }]
}

proc step5_write_object_properties {handle heading object} {
  puts $handle $heading
  puts $handle [string repeat {-} 78]
  foreach property_name [lsort [list_property $object]] {
    puts $handle [format \
      "%-50s %s" \
      $property_name \
      [get_property -quiet $property_name $object]]
  }
  puts $handle {}
}

set step5_current_vivado_version [version -short]
if {[string first \
    $step5_required_vivado_version \
    $step5_current_vivado_version] != 0} {
  step5_fail \
    "Vivado $step5_required_vivado_version is required; running $step5_current_vivado_version"
}
if {![file exists $step5_project_file]} {
  step5_fail \
    "Step-4 project was not found; run build_step4_trigger_profiles.tcl first"
}
if {![file isfile $step5_debug_hub_xdc]} {
  step5_fail "Debug Hub constraint was not found: $step5_debug_hub_xdc"
}

file mkdir $step5_output_dir
file mkdir $step5_generated_dir

# Delete only known generated files so an old artifact cannot hide a failed
# current build.
foreach step5_stale_file [list \
    $step5_routed_dcp \
    $step5_bitstream \
    $step5_ltx \
    $step5_timing_report \
    $step5_check_timing_report \
    $step5_bus_skew_report \
    $step5_utilization_report \
    $step5_hier_utilization_report \
    $step5_route_report \
    $step5_drc_report \
    $step5_methodology_report \
    $step5_cdc_report \
    $step5_io_report \
    $step5_clock_report \
    $step5_clock_utilization_report \
    $step5_debug_report \
    $step5_manifest \
    $step5_checksums] {
  if {[file exists $step5_stale_file]} {
    file delete -force $step5_stale_file
  }
}

# Keep memory usage bounded on the development host without changing either
# frozen Vivado run strategy.
set_param general.maxThreads 2

open_project $step5_project_file

step5_assert_equal \
  {FPGA part} \
  [get_property PART [current_project]] \
  $step5_required_part
step5_assert_equal \
  {Board part} \
  [get_property BOARD_PART [current_project]] \
  $step5_required_board_part

set step5_bd_file [get_files -quiet base_soc.bd]
if {[llength $step5_bd_file] != 1} {
  step5_fail "base_soc.bd was not found exactly once"
}
open_bd_design $step5_bd_file
if {[catch {validate_bd_design} step5_bd_validation_error]} {
  step5_fail "Validate Design failed: $step5_bd_validation_error"
}
puts "STEP 5 VALIDATE DESIGN: PASS"
save_bd_design
generate_target all $step5_bd_file

# A module-reference source was previously selected automatically as the top.
# Importing and fixing the BD wrapper here prevents a false Generator-only
# synthesis result.
make_wrapper -files $step5_bd_file -top -import -force
set_property top base_soc_wrapper [get_filesets sources_1]

# Vivado inserts dbg_hub after synthesis.  Register its property constraint as
# implementation-only and process it late, after the debug core exists.
set step5_debug_hub_xdc_files \
  [get_files -quiet [list $step5_debug_hub_xdc]]
if {[llength $step5_debug_hub_xdc_files] == 0} {
  add_files -fileset constrs_1 -norecurse \
    [list $step5_debug_hub_xdc]
  set step5_debug_hub_xdc_files \
    [get_files -quiet [list $step5_debug_hub_xdc]]
}
if {[llength $step5_debug_hub_xdc_files] != 1} {
  step5_fail \
    "Debug Hub XDC was not registered exactly once: $step5_debug_hub_xdc_files"
}
set step5_debug_hub_xdc_file [lindex $step5_debug_hub_xdc_files 0]
set_property USED_IN_SYNTHESIS false $step5_debug_hub_xdc_file
set_property USED_IN_IMPLEMENTATION true $step5_debug_hub_xdc_file
set_property PROCESSING_ORDER LATE $step5_debug_hub_xdc_file

update_compile_order -fileset sources_1
close_bd_design [get_bd_designs base_soc]

step5_assert_equal \
  {Synthesis top} \
  [get_property TOP [get_filesets sources_1]] \
  base_soc_wrapper

set step5_wrapper_files {}
foreach step5_source_file \
    [get_files -quiet -of_objects [get_filesets sources_1]] {
  if {[file tail $step5_source_file] eq {base_soc_wrapper.v}} {
    lappend step5_wrapper_files $step5_source_file
  }
}
if {[llength $step5_wrapper_files] != 1} {
  step5_fail \
    "base_soc_wrapper.v was not registered exactly once: $step5_wrapper_files"
}

set step5_compile_order \
  [get_files -compile_order sources -used_in synthesis]
if {[lsearch -glob $step5_compile_order \
    {*base_soc_wrapper.v}] < 0} {
  step5_fail "base_soc_wrapper.v is absent from the synthesis compile order"
}
puts "ASSERT PASS: BD wrapper is registered in the synthesis compile order"

set step5_synth_run [get_runs synth_1]
set step5_impl_run [get_runs impl_1]
step5_assert_equal \
  {Synthesis strategy} \
  [get_property STRATEGY $step5_synth_run] \
  {Vivado Synthesis Defaults}
step5_assert_equal \
  {Implementation strategy} \
  [get_property STRATEGY $step5_impl_run] \
  {Vivado Implementation Defaults}

if {$step5_resume_existing_runs &&
    [step5_run_is_reusable synth_1 synth_design]} {
  puts "STEP 5 RESUME: reusing completed synth_1"
} else {
  reset_run synth_1
  launch_runs synth_1 -jobs 1
  wait_on_runs synth_1
}
step5_assert_run_ok synth_1 synth_design

open_run synth_1

step5_assert_equal \
  {Synthesized fileset top} \
  [get_property TOP [get_filesets sources_1]] \
  base_soc_wrapper
step5_assert_equal \
  {Synthesized top ports} \
  [lsort [get_property NAME [get_ports -quiet]]] \
  {reset sys_clock usb_uart_rxd usb_uart_txd}

foreach step5_required_hierarchy {
  microblaze_riscv_0
  test_pattern_generator_gpio_adapter_0
  ila_reference_0
  axi_uartlite_0
  axi_timer_0
  axi_gpio_test_ctrl
  microblaze_riscv_0_axi_intc
  lmb_bram
} {
  if {[step5_count_named_cells \
      "*${step5_required_hierarchy}*"] == 0} {
    step5_fail \
      "Required synthesized hierarchy is missing: $step5_required_hierarchy"
  }
  puts \
    "ASSERT PASS: synthesized hierarchy contains $step5_required_hierarchy"
}

foreach step5_forbidden_hierarchy {
  circular_trace_buffer
  probe_sampler
  basic_trigger_engine
  axi_gpio_probe
  system_ila
  vio
} {
  if {[step5_count_named_cells \
      "*${step5_forbidden_hierarchy}*"] != 0} {
    step5_fail \
      "Forbidden comparison hardware was synthesized: $step5_forbidden_hierarchy"
  }
}
puts "ASSERT PASS: no Custom Analyzer, CPU Probe GPIO, System ILA, or VIO"

set step5_blackboxes \
  [get_cells -hier -quiet -filter {IS_BLACKBOX == 1}]
set step5_debug_hub_blackboxes {}
set step5_unexpected_blackboxes {}
foreach step5_blackbox $step5_blackboxes {
  if {[string match -nocase \
      {*dbg_hub*} \
      [get_property NAME $step5_blackbox]]} {
    lappend step5_debug_hub_blackboxes $step5_blackbox
  } else {
    lappend step5_unexpected_blackboxes $step5_blackbox
  }
}
if {[llength $step5_debug_hub_blackboxes] != 1} {
  step5_fail \
    "Expected exactly one synthesis-stage Debug Hub black box: $step5_debug_hub_blackboxes"
}
if {[llength $step5_unexpected_blackboxes] != 0} {
  step5_fail \
    "Unexpected unresolved synthesized black boxes: $step5_unexpected_blackboxes"
}
puts \
  "ASSERT PASS: only the expected implementation-time Debug Hub black box remains"

set step5_ila_debug_cores {}
set step5_debug_hubs {}
foreach step5_debug_core [get_debug_cores -quiet] {
  if {[step5_property_exists \
      $step5_debug_core C_DATA_DEPTH]} {
    lappend step5_ila_debug_cores $step5_debug_core
  }
  if {[string match -nocase \
      {*dbg_hub*} \
      [get_property NAME $step5_debug_core]]} {
    lappend step5_debug_hubs $step5_debug_core
  }
}

if {[llength $step5_ila_debug_cores] != 1} {
  step5_fail \
    "Exactly one synthesized ILA debug core is required: $step5_ila_debug_cores"
}
if {[llength $step5_debug_hubs] != 1} {
  step5_fail \
    "Exactly one synthesized Debug Hub is required: $step5_debug_hubs"
}

set step5_ila_debug_core [lindex $step5_ila_debug_cores 0]
set step5_debug_hub [lindex $step5_debug_hubs 0]
set step5_ila_uuid \
  [string toupper [get_property UUID $step5_ila_debug_core]]
if {![regexp {^[0-9A-F]{32}$} $step5_ila_uuid]} {
  step5_fail "Synthesized ILA UUID is invalid: $step5_ila_uuid"
}
step5_assert_equal \
  {Synthesized ILA data depth} \
  [get_property C_DATA_DEPTH $step5_ila_debug_core] \
  1024
step5_assert_equal \
  {Synthesized ILA input pipeline} \
  [get_property C_INPUT_PIPE_STAGES $step5_ila_debug_core] \
  0
step5_assert_equal \
  {Synthesized ILA advanced trigger} \
  [get_property C_ADV_TRIGGER $step5_ila_debug_core] \
  false
step5_assert_equal \
  {Synthesized ILA storage qualification} \
  [get_property C_EN_STRG_QUAL $step5_ila_debug_core] \
  false

set step5_probe0_candidates {}
foreach step5_debug_port \
    [get_debug_ports -quiet -of_objects $step5_ila_debug_core] {
  if {[string match \
      {*/probe0} \
      [get_property NAME $step5_debug_port]]} {
    lappend step5_probe0_candidates $step5_debug_port
  }
}
if {[llength $step5_probe0_candidates] != 1} {
  step5_fail \
    "Exactly one synthesized ILA probe0 is required: $step5_probe0_candidates"
}
set step5_probe0 [lindex $step5_probe0_candidates 0]
step5_assert_equal \
  {Synthesized ILA probe0 width} \
  [get_property PORT_WIDTH $step5_probe0] \
  8
step5_assert_equal \
  {Synthesized ILA probe0 type} \
  [get_property PROBE_TYPE $step5_probe0] \
  DATA_AND_TRIGGER

step5_assert_equal \
  {Debug Hub USER scan chain} \
  [get_property C_USER_SCAN_CHAIN $step5_debug_hub] \
  1

# The checked-in implementation XDC applies the same setting when impl_1 is
# launched in its child process.  Apply it to this open synthesis checkpoint as
# well so this stage can verify the intended metadata against the real clock.
set_property C_CLK_INPUT_FREQ_HZ 100000000 $step5_debug_hub
set_property C_ENABLE_CLK_DIVIDER false $step5_debug_hub
step5_assert_equal \
  {Debug Hub clock frequency} \
  [get_property C_CLK_INPUT_FREQ_HZ $step5_debug_hub] \
  100000000
step5_assert_equal \
  {Debug Hub clock divider} \
  [get_property C_ENABLE_CLK_DIVIDER $step5_debug_hub] \
  false

set step5_debug_hub_clk_pins \
  [get_pins -quiet dbg_hub/clk]
if {[llength $step5_debug_hub_clk_pins] != 1} {
  step5_fail \
    "Exactly one synthesized Debug Hub clock pin is required: $step5_debug_hub_clk_pins"
}
set step5_debug_hub_clocks \
  [get_clocks -quiet -of_objects $step5_debug_hub_clk_pins]
if {[llength $step5_debug_hub_clocks] == 0} {
  step5_fail "Synthesized Debug Hub clock is unconstrained"
}
set step5_debug_hub_clock_is_100mhz 0
foreach step5_debug_hub_clock $step5_debug_hub_clocks {
  set step5_debug_hub_clock_period \
    [get_property PERIOD $step5_debug_hub_clock]
  if {[string is double -strict $step5_debug_hub_clock_period] &&
      abs(double($step5_debug_hub_clock_period) - 10.0) <= 0.001} {
    set step5_debug_hub_clock_is_100mhz 1
  }
}
step5_assert_true \
  {Synthesized Debug Hub clock period is 10.000 ns} \
  $step5_debug_hub_clock_is_100mhz

set step5_debug_handle [open $step5_debug_report w]
puts $step5_debug_handle \
  {EdgeScope-Lite Vivado ILA Reference - Step 5 Debug Core Readback}
puts $step5_debug_handle \
  {================================================================}
step5_write_object_properties \
  $step5_debug_handle \
  {Synthesized ILA Debug Core} \
  $step5_ila_debug_core
step5_write_object_properties \
  $step5_debug_handle \
  {Synthesized ILA Probe0} \
  $step5_probe0
step5_write_object_properties \
  $step5_debug_handle \
  {Synthesized Debug Hub Configuration} \
  $step5_debug_hub
close $step5_debug_handle

close_design

if {$step5_resume_existing_runs &&
    [step5_run_is_reusable impl_1 route_design]} {
  puts "STEP 5 RESUME: reusing completed impl_1 route_design"
} else {
  reset_run impl_1
  launch_runs impl_1 -to_step route_design -jobs 1
  wait_on_runs impl_1
}
step5_assert_run_ok impl_1 route_design

open_run impl_1

step5_assert_equal \
  {Implemented fileset top} \
  [get_property TOP [get_filesets sources_1]] \
  base_soc_wrapper
step5_assert_equal \
  {Implemented top ports} \
  [lsort [get_property NAME [get_ports -quiet]]] \
  {reset sys_clock usb_uart_rxd usb_uart_txd}

# Confirm that the implementation child process generated dbg_hub using the
# intended frequency rather than merely accepting the parent-session XDC.
set step5_impl_run_dir \
  [get_property DIRECTORY $step5_impl_run]
if {![file isdirectory $step5_impl_run_dir]} {
  step5_fail \
    "Implementation run directory was not found: $step5_impl_run_dir"
}
set step5_debug_hub_stub_find_result [string trim \
  [exec find $step5_impl_run_dir \
    -type f -name dbg_hub_stub.v]]
if {$step5_debug_hub_stub_find_result eq {}} {
  step5_fail "Implemented Debug Hub stub was not generated"
}
set step5_debug_hub_stub_files \
  [split $step5_debug_hub_stub_find_result "\n"]
if {[llength $step5_debug_hub_stub_files] != 1} {
  step5_fail \
    "Expected one implemented Debug Hub stub: $step5_debug_hub_stub_files"
}
set step5_debug_hub_stub \
  [lindex $step5_debug_hub_stub_files 0]
set step5_debug_hub_stub_handle \
  [open $step5_debug_hub_stub r]
set step5_debug_hub_stub_text \
  [read $step5_debug_hub_stub_handle]
close $step5_debug_hub_stub_handle
if {![regexp \
    {C_CLK_INPUT_FREQ_HZ=100000000} \
    $step5_debug_hub_stub_text]} {
  step5_fail \
    "Implemented Debug Hub was not generated for a 100 MHz input clock"
}
if {![regexp \
    {C_ENABLE_CLK_DIVIDER=0} \
    $step5_debug_hub_stub_text]} {
  step5_fail \
    "Implemented Debug Hub clock-divider configuration is unexpected"
}
puts \
  "ASSERT PASS: implemented Debug Hub input frequency = 100000000 Hz"

foreach {step5_port step5_pin} {
  sys_clock     W5
  reset         U18
  usb_uart_rxd  B18
  usb_uart_txd  A18
} {
  set step5_port_object [get_ports -quiet $step5_port]
  if {[llength $step5_port_object] != 1} {
    step5_fail "Implemented top port was not found: $step5_port"
  }
  step5_assert_equal \
    "$step5_port PACKAGE_PIN" \
    [get_property PACKAGE_PIN $step5_port_object] \
    $step5_pin
  step5_assert_equal \
    "$step5_port IOSTANDARD" \
    [get_property IOSTANDARD $step5_port_object] \
    LVCMOS33
}

report_route_status -file $step5_route_report
step5_assert_true \
  {Routing data exists} \
  [report_route_status -has_routing]
step5_assert_true \
  {Design is fully placed} \
  [report_route_status -boolean_check PLACED_FULLY]
step5_assert_true \
  {Design is fully routed} \
  [report_route_status -boolean_check ROUTED_FULLY]
if {[report_route_status -boolean_check ERRORS_IN_ROUTES]} {
  step5_fail "Route errors were found"
}
puts "ASSERT PASS: route errors = 0"

report_timing_summary \
  -delay_type min_max \
  -report_unconstrained \
  -check_timing_verbose \
  -file $step5_timing_report
check_timing -verbose -file $step5_check_timing_report

set step5_check_timing_handle \
  [open $step5_check_timing_report r]
set step5_check_timing_text \
  [read $step5_check_timing_handle]
close $step5_check_timing_handle
foreach step5_zero_timing_check {
  no_clock
  constant_clock
  pulse_width_clock
  unconstrained_internal_endpoints
  multiple_clock
  generated_clocks
  loops
  partial_input_delay
  partial_output_delay
  latch_loops
} {
  if {![regexp \
      "checking ${step5_zero_timing_check} \\(0\\)" \
      $step5_check_timing_text]} {
    step5_fail \
      "Timing coverage check is nonzero or absent: $step5_zero_timing_check"
  }
}
if {![regexp \
    {checking no_input_delay \(2\)} \
    $step5_check_timing_text] ||
    ![regexp \
    {checking no_output_delay \(1\)} \
    $step5_check_timing_text]} {
  step5_fail \
    "Expected only reset/UART external I/O delay notices"
}
puts \
  "TIMING COVERAGE PASS: internal endpoints=0; reset/UART external delays are intentionally not modeled"

# Read the one numeric Design Timing Summary row.  This supplements the
# worst setup/hold path checks below with total negative slack, pulse-width
# slack, and failing-endpoint gates.
set step5_timing_handle [open $step5_timing_report r]
set step5_timing_text [read $step5_timing_handle]
close $step5_timing_handle
set step5_timing_summary_pattern {(?m)^[ \t]*(-?[0-9]+\.[0-9]+)[ \t]+(-?[0-9]+\.[0-9]+)[ \t]+([0-9]+)[ \t]+([0-9]+)[ \t]+(-?[0-9]+\.[0-9]+)[ \t]+(-?[0-9]+\.[0-9]+)[ \t]+([0-9]+)[ \t]+([0-9]+)[ \t]+(-?[0-9]+\.[0-9]+)[ \t]+(-?[0-9]+\.[0-9]+)[ \t]+([0-9]+)[ \t]+([0-9]+)[ \t]*$}
if {![regexp \
    $step5_timing_summary_pattern \
    $step5_timing_text \
    step5_timing_summary_row \
    step5_summary_wns \
    step5_tns \
    step5_tns_failing \
    step5_tns_total \
    step5_summary_whs \
    step5_ths \
    step5_ths_failing \
    step5_ths_total \
    step5_wpws \
    step5_tpws \
    step5_tpws_failing \
    step5_tpws_total]} {
  step5_fail "Design Timing Summary numeric row was not found"
}
foreach {step5_timing_label step5_timing_value} [list \
    TNS $step5_tns \
    THS $step5_ths \
    TPWS $step5_tpws] {
  if {![string is double -strict $step5_timing_value] ||
      abs(double($step5_timing_value)) > 0.0005} {
    step5_fail "$step5_timing_label is not zero: $step5_timing_value ns"
  }
}
if {![string is double -strict $step5_wpws] ||
    double($step5_wpws) < 0.0} {
  step5_fail "Pulse-width timing failed: WPWS=$step5_wpws ns"
}
foreach {step5_endpoint_label step5_endpoint_count} [list \
    {TNS failing endpoints} $step5_tns_failing \
    {THS failing endpoints} $step5_ths_failing \
    {TPWS failing endpoints} $step5_tpws_failing] {
  if {$step5_endpoint_count != 0} {
    step5_fail "$step5_endpoint_label is nonzero: $step5_endpoint_count"
  }
}
puts \
  "TIMING TOTALS PASS: TNS=$step5_tns THS=$step5_ths WPWS=$step5_wpws TPWS=$step5_tpws ns"

set step5_setup_path \
  [get_timing_paths -setup -max_paths 1 -nworst 1]
set step5_hold_path \
  [get_timing_paths -hold -max_paths 1 -nworst 1]
if {[llength $step5_setup_path] != 1} {
  step5_fail "Exactly one worst constrained setup path was not returned"
}
if {[llength $step5_hold_path] != 1} {
  step5_fail "Exactly one worst constrained hold path was not returned"
}

set step5_wns [get_property SLACK $step5_setup_path]
set step5_whs [get_property SLACK $step5_hold_path]
if {![string is double -strict $step5_wns] ||
    [expr {double($step5_wns)}] < 0.0} {
  step5_fail "Setup timing failed: WNS=$step5_wns ns"
}
if {![string is double -strict $step5_whs] ||
    [expr {double($step5_whs)}] < 0.0} {
  step5_fail "Hold timing failed: WHS=$step5_whs ns"
}
puts "TIMING PASS: WNS=$step5_wns ns, WHS=$step5_whs ns"

report_bus_skew \
  -warn_on_violation \
  -file $step5_bus_skew_report
set step5_bus_skew_handle \
  [open $step5_bus_skew_report r]
set step5_bus_skew_text \
  [read $step5_bus_skew_handle]
close $step5_bus_skew_handle
set step5_bus_skew_met_count \
  [regexp -all {Slack \(MET\)} $step5_bus_skew_text]
if {$step5_bus_skew_met_count == 0 ||
    [regexp {Slack \(VIOLATED\)} $step5_bus_skew_text]} {
  step5_fail "One or more bus-skew constraints were not met"
}
puts \
  "BUS SKEW PASS: $step5_bus_skew_met_count constraints met"

set step5_sys_clock_objects \
  [lsort -unique \
    [get_clocks -quiet -of_objects [get_ports sys_clock]]]
if {[llength $step5_sys_clock_objects] != 1} {
  step5_fail \
    "sys_clock must resolve to exactly one timing clock: $step5_sys_clock_objects"
}
set step5_sys_clock_period \
  [get_property PERIOD [lindex $step5_sys_clock_objects 0]]
if {![string is double -strict $step5_sys_clock_period] ||
    abs(double($step5_sys_clock_period) - 10.0) > 0.001} {
  step5_fail \
    "sys_clock period is not 10.000 ns: $step5_sys_clock_period"
}
puts "ASSERT PASS: sys_clock period is 10.000 ns"

set step5_ila_clk_pins {}
foreach step5_pin_object [get_pins -hier -quiet] {
  set step5_pin_name [get_property NAME $step5_pin_object]
  if {[string match {*ila_reference_0*} $step5_pin_name] &&
      [string match {*/clk} $step5_pin_name]} {
    lappend step5_ila_clk_pins $step5_pin_object
  }
}
if {[llength $step5_ila_clk_pins] == 0} {
  step5_fail "No implemented ILA clock pin was found"
}
set step5_ila_clocks \
  [lsort -unique \
    [get_clocks -quiet -of_objects $step5_ila_clk_pins]]
if {[llength $step5_ila_clocks] != 1} {
  step5_fail \
    "Implemented ILA must resolve to exactly one timing clock: $step5_ila_clocks"
}
set step5_ila_clock_period \
  [get_property PERIOD [lindex $step5_ila_clocks 0]]
if {![string is double -strict $step5_ila_clock_period] ||
    abs(double($step5_ila_clock_period) - 10.0) > 0.001} {
  step5_fail \
    "Implemented ILA clock period is not 10.000 ns: $step5_ila_clock_period"
}
puts "ASSERT PASS: Implemented ILA clock period is 10.000 ns"

set step5_drc_name {ila_reference_step5_post_route_drc}
set step5_drc_decks {}
foreach step5_drc_deck_name {default bitstream_checks} {
  set step5_drc_deck \
    [get_drc_ruledecks -quiet $step5_drc_deck_name]
  if {[llength $step5_drc_deck] != 1} {
    step5_fail \
      "Required DRC ruledeck was not found exactly once: $step5_drc_deck_name"
  }
  lappend step5_drc_decks $step5_drc_deck
}
report_drc \
  -name $step5_drc_name \
  -ruledecks $step5_drc_decks \
  -no_waivers \
  -file $step5_drc_report

set step5_drc_error_count 0
set step5_drc_critical_count 0
set step5_drc_warning_count 0
set step5_drc_blocking {}
foreach step5_drc_violation \
    [get_drc_violations -quiet -name $step5_drc_name] {
  set step5_drc_severity [string map \
    {{ } {_} {-} {_}} \
    [string toupper \
      [get_property SEVERITY $step5_drc_violation]]]
  switch -exact -- $step5_drc_severity {
    FATAL -
    ERROR {
      incr step5_drc_error_count
      lappend step5_drc_blocking $step5_drc_violation
    }
    CRITICAL_WARNING {
      incr step5_drc_critical_count
      lappend step5_drc_blocking $step5_drc_violation
    }
    WARNING {
      incr step5_drc_warning_count
    }
  }
}
if {[llength $step5_drc_blocking] != 0} {
  step5_fail \
    "Blocking post-route DRC violations: $step5_drc_blocking"
}
puts \
  "DRC PASS: Error=$step5_drc_error_count Critical=$step5_drc_critical_count Warning=$step5_drc_warning_count"

report_utilization -file $step5_utilization_report
report_utilization \
  -hierarchical \
  -hierarchical_depth 4 \
  -file $step5_hier_utilization_report
report_methodology -file $step5_methodology_report
report_cdc -details -file $step5_cdc_report
set step5_cdc_handle [open $step5_cdc_report r]
set step5_cdc_text [read $step5_cdc_handle]
close $step5_cdc_handle
set step5_cdc_info_count 0
set step5_cdc_blocking_count 0
foreach step5_cdc_line [split $step5_cdc_text "\n"] {
  if {[regexp \
      {^CDC-[0-9]+[ \t]+([^ \t]+)[ \t]+([0-9]+)[ \t]+} \
      $step5_cdc_line \
      step5_cdc_match \
      step5_cdc_severity \
      step5_cdc_count]} {
    if {[string equal -nocase $step5_cdc_severity Info]} {
      incr step5_cdc_info_count $step5_cdc_count
    } else {
      incr step5_cdc_blocking_count $step5_cdc_count
    }
  }
}
if {$step5_cdc_info_count == 0} {
  step5_fail "CDC report did not contain any classified crossings"
}
if {$step5_cdc_blocking_count != 0} {
  step5_fail \
    "CDC report contains non-Info crossings: $step5_cdc_blocking_count"
}
puts \
  "CDC PASS: $step5_cdc_info_count crossings are synchronized Info; non-Info=0"
report_io -file $step5_io_report
report_clocks -file $step5_clock_report
report_clock_utilization \
  -file $step5_clock_utilization_report

set step5_debug_handle [open $step5_debug_report a]
puts $step5_debug_handle {Implemented Debug Hub generation}
puts $step5_debug_handle \
  {------------------------------------------------------------------------------}
puts $step5_debug_handle \
  "Stub: $step5_debug_hub_stub"
puts $step5_debug_handle \
  {C_CLK_INPUT_FREQ_HZ=100000000}
puts $step5_debug_handle \
  {C_ENABLE_CLK_DIVIDER=0}
puts $step5_debug_handle {}
puts $step5_debug_handle {ILA clock pins}
puts $step5_debug_handle \
  {------------------------------------------------------------------------------}
foreach step5_ila_clk_pin $step5_ila_clk_pins {
  puts $step5_debug_handle \
    [get_property NAME $step5_ila_clk_pin]
}
puts $step5_debug_handle {}
puts $step5_debug_handle {ILA clock objects}
puts $step5_debug_handle \
  {------------------------------------------------------------------------------}
foreach step5_ila_clock $step5_ila_clocks {
  puts $step5_debug_handle [format \
    "%s PERIOD=%s" \
    [get_property NAME $step5_ila_clock] \
    [get_property PERIOD $step5_ila_clock]]
}
close $step5_debug_handle

# Export the checkpoint first, then the BIT and LTX consecutively from this
# same open routed design.  Do not reopen or modify the design between them.
write_checkpoint -force $step5_routed_dcp
write_bitstream -force $step5_bitstream
write_debug_probes -force $step5_ltx

step5_assert_file {Routed checkpoint} $step5_routed_dcp
step5_assert_file {Bitstream} $step5_bitstream
step5_assert_file {Debug probes LTX} $step5_ltx

set step5_ltx_handle [open $step5_ltx r]
set step5_ltx_text [read $step5_ltx_handle]
close $step5_ltx_handle
set step5_ltx_ila_count \
  [regexp -all {\"type\"[ \t]*:[ \t]*\"ILA_V3\"} $step5_ltx_text]
if {$step5_ltx_ila_count != 1} {
  step5_fail \
    "LTX must contain exactly one ILA_V3 debug core: $step5_ltx_ila_count"
}
set step5_ltx_probe_count \
  [regexp -all {\"name\"[ \t]*:[ \t]*\"probe0\"} $step5_ltx_text]
set step5_ltx_data_trigger_count \
  [regexp -all {\"type\"[ \t]*:[ \t]*\"DATA_TRIGGER\"} $step5_ltx_text]
if {$step5_ltx_probe_count != 1 ||
    $step5_ltx_data_trigger_count != 1} {
  step5_fail \
    "LTX probe metadata mismatch: probe0=$step5_ltx_probe_count DATA_TRIGGER=$step5_ltx_data_trigger_count"
}
foreach {step5_ltx_label step5_ltx_pattern} [list \
    {ILA hierarchy} \
      {\"name\"[ \t]*:[ \t]*\"base_soc_i/ila_reference_0\"} \
    {ILA UUID} \
      [format {\"uuid\"[ \t]*:[ \t]*\"%s\"} $step5_ila_uuid] \
    {Probe left index} \
      {\"leftIndex\"[ \t]*:[ \t]*0} \
    {Probe right index} \
      {\"rightIndex\"[ \t]*:[ \t]*7} \
    {Generator probe bus} \
      {\"name\"[ \t]*:[ \t]*\"base_soc_i/test_pattern_generator_gpio_adapter_0_probe_test_o\"}] {
  if {![regexp -nocase $step5_ltx_pattern $step5_ltx_text]} {
    step5_fail "LTX is missing or mismatches: $step5_ltx_label"
  }
}
foreach step5_probe_bit {0 1 2 3 4 5 6 7} {
  set step5_probe_bit_pattern \
    [format \
      {\"name\"[ \t]*:[ \t]*\"base_soc_i/test_pattern_generator_gpio_adapter_0_probe_test_o\[%d\]\"} \
      $step5_probe_bit]
  if {[regexp -all $step5_probe_bit_pattern $step5_ltx_text] != 1} {
    step5_fail \
      "LTX must contain generator probe bit $step5_probe_bit exactly once"
  }
}
puts \
  "ASSERT PASS: LTX ILA UUID, one 8-bit DATA_TRIGGER probe, and generator bus all match"

set step5_git_commit {UNKNOWN}
if {![catch {
    exec git -C $step5_script_dir rev-parse HEAD
  } step5_git_commit_result]} {
  set step5_git_commit [string trim $step5_git_commit_result]
}
set step5_git_dirty {UNKNOWN}
if {![catch {
    exec git -C $step5_script_dir status --porcelain
  } step5_git_status_result]} {
  if {[string trim $step5_git_status_result] eq {}} {
    set step5_git_dirty false
  } else {
    set step5_git_dirty true
  }
}

set step5_bootloop_find_result [string trim \
  [exec find [file join $step5_common_dir build base_soc] \
    -type f -name riscv_bootloop.elf]]
if {$step5_bootloop_find_result eq {}} {
  step5_fail "MicroBlaze V bootloop ELF was not found"
}
set step5_bootloop_files [split $step5_bootloop_find_result "\n"]
if {[llength $step5_bootloop_files] != 1} {
  step5_fail \
    "Expected exactly one MicroBlaze V bootloop ELF: $step5_bootloop_files"
}
set step5_bootloop_elf [lindex $step5_bootloop_files 0]

set step5_manifest_handle [open $step5_manifest w]
puts $step5_manifest_handle \
  {EdgeScope-Lite Vivado ILA Reference - Step 5 Build Manifest}
puts $step5_manifest_handle \
  {============================================================}
puts $step5_manifest_handle \
  "Build Time                 : [clock format \
    [clock seconds] -format {%Y-%m-%d %H:%M:%S %z}]"
puts $step5_manifest_handle \
  "Vivado                     : [version]"
puts $step5_manifest_handle \
  "FPGA Part                  : [get_property PART [current_project]]"
puts $step5_manifest_handle \
  "Board Part                 : [get_property BOARD_PART [current_project]]"
puts $step5_manifest_handle \
  "Top                        : [get_property TOP [get_filesets sources_1]]"
puts $step5_manifest_handle \
  "Synthesis Strategy         : [get_property STRATEGY $step5_synth_run]"
puts $step5_manifest_handle \
  "Implementation Strategy    : [get_property STRATEGY $step5_impl_run]"
puts $step5_manifest_handle \
  "Synthesis Status           : [get_property STATUS $step5_synth_run]"
puts $step5_manifest_handle \
  "Implementation Status      : [get_property STATUS $step5_impl_run]"
puts $step5_manifest_handle \
  "Git Commit                 : $step5_git_commit"
puts $step5_manifest_handle \
  "Git Worktree Dirty         : $step5_git_dirty"
puts $step5_manifest_handle \
  "WNS (ns)                   : $step5_wns"
puts $step5_manifest_handle \
  "TNS (ns)                   : $step5_tns"
puts $step5_manifest_handle \
  "WHS (ns)                   : $step5_whs"
puts $step5_manifest_handle \
  "THS (ns)                   : $step5_ths"
puts $step5_manifest_handle \
  "WPWS (ns)                  : $step5_wpws"
puts $step5_manifest_handle \
  "TPWS (ns)                  : $step5_tpws"
puts $step5_manifest_handle \
  "sys_clock Period (ns)      : 10.000"
puts $step5_manifest_handle \
  "ILA Clock Period (ns)      : 10.000"
puts $step5_manifest_handle \
  "Debug Hub Input Clock (Hz) : 100000000"
puts $step5_manifest_handle \
  "Bus Skew Constraints Met   : $step5_bus_skew_met_count"
puts $step5_manifest_handle \
  "Internal Unconstrained     : 0"
puts $step5_manifest_handle \
  "CDC Info / Non-Info        : $step5_cdc_info_count / $step5_cdc_blocking_count"
puts $step5_manifest_handle \
  "External I/O Delays        : NOT MODELED (reset/UART asynchronous interfaces)"
puts $step5_manifest_handle \
  "Fully Placed               : PASS"
puts $step5_manifest_handle \
  "Fully Routed               : PASS"
puts $step5_manifest_handle \
  "Route Errors               : 0"
puts $step5_manifest_handle \
  "DRC Errors                 : $step5_drc_error_count"
puts $step5_manifest_handle \
  "DRC Critical Warnings      : $step5_drc_critical_count"
puts $step5_manifest_handle \
  "DRC Warnings               : $step5_drc_warning_count"
puts $step5_manifest_handle \
  "BIT/LTX Same Routed Design : PASS"
puts $step5_manifest_handle \
  "Hardware Pair Readback     : PENDING STEP 6"
puts $step5_manifest_handle \
  "Runtime Control Firmware   : PENDING (current ELF is riscv_bootloop.elf)"
puts $step5_manifest_handle \
  "Source Provenance          : ALL BUILD INPUTS HASHED BELOW; GIT DIRTY STATE RECORDED"
puts $step5_manifest_handle \
  "Checksum Index             : comparison/ila_reference/generated/ila_reference_step5_SHA256SUMS"
puts $step5_manifest_handle {}

foreach {step5_source_label step5_source_path} [list \
    {Base SoC Tcl} \
      [file join $step5_common_dir base_soc.tcl] \
    {Generator Integration Tcl} \
      [file join $step5_common_dir add_test_pattern_generator.tcl] \
    {Base Build Tcl} \
      [file join $step5_common_dir build_base_with_generator.tcl] \
    {Generator Core RTL} \
      [file join $step5_common_dir rtl test_pattern_generator.sv] \
    {Generator Adapter RTL} \
      [file join $step5_common_dir rtl test_pattern_generator_gpio_adapter.v] \
    {Step 3 Build Tcl} \
      [file join $step5_script_dir build_step3_ila.tcl] \
    {Step 4 Build Tcl} \
      [file join $step5_script_dir build_step4_trigger_profiles.tcl] \
    {Step 4 Validation Tcl} \
      [file join $step5_script_dir validate_step4_trigger_config.tcl] \
    {ILA Structure Tcl} \
      [file join $step5_script_dir add_vivado_ila.tcl] \
    {ILA Trigger Tcl} \
      [file join $step5_script_dir hw ila_trigger_control.tcl] \
    {Debug Hub XDC} \
      $step5_debug_hub_xdc \
    {Step 5 Tcl} \
      [file normalize [info script]] \
    {Step 5 Runner} \
      [file join $step5_script_dir run_step5_build.sh] \
    {MicroBlaze Bootloop ELF} \
      $step5_bootloop_elf \
    {Generated Wrapper} \
      [lindex $step5_wrapper_files 0]] {
  puts $step5_manifest_handle \
    "$step5_source_label SHA-256: [step5_sha256 $step5_source_path]"
}
puts $step5_manifest_handle {}

foreach {step5_artifact_label step5_artifact_path step5_relative_path} [list \
    {Routed DCP} \
      $step5_routed_dcp \
      comparison/ila_reference/build/step5/edgescope_ila_reference_routed.dcp \
    {Bitstream} \
      $step5_bitstream \
      comparison/ila_reference/build/step5/edgescope_ila_reference.bit \
    {Debug Probes LTX} \
      $step5_ltx \
      comparison/ila_reference/build/step5/debug_nets.ltx] {
  puts $step5_manifest_handle \
    "$step5_artifact_label Path   : $step5_relative_path"
  puts $step5_manifest_handle \
    "$step5_artifact_label Size   : [file size $step5_artifact_path]"
  puts $step5_manifest_handle \
    "$step5_artifact_label SHA-256: [step5_sha256 $step5_artifact_path]"
}
close $step5_manifest_handle

step5_assert_file {Timing summary report} $step5_timing_report
step5_assert_file {Bus-skew report} $step5_bus_skew_report
step5_assert_file {Post-route DRC report} $step5_drc_report
step5_assert_file {Utilization report} $step5_utilization_report
step5_assert_file {Debug-core report} $step5_debug_report
step5_assert_file {CDC report} $step5_cdc_report
step5_assert_file {Step-5 build manifest} $step5_manifest

set step5_checksum_handle [open $step5_checksums w]
foreach {step5_checksum_path step5_checksum_relative_path} [list \
    $step5_routed_dcp \
      build/step5/edgescope_ila_reference_routed.dcp \
    $step5_bitstream \
      build/step5/edgescope_ila_reference.bit \
    $step5_ltx \
      build/step5/debug_nets.ltx \
    $step5_manifest \
      generated/ila_reference_step5_build_manifest.rpt \
    $step5_timing_report \
      generated/ila_reference_step5_timing_summary.rpt \
    $step5_check_timing_report \
      generated/ila_reference_step5_check_timing.rpt \
    $step5_bus_skew_report \
      generated/ila_reference_step5_bus_skew.rpt \
    $step5_drc_report \
      generated/ila_reference_step5_drc.rpt \
    $step5_cdc_report \
      generated/ila_reference_step5_cdc.rpt \
    $step5_utilization_report \
      generated/ila_reference_step5_utilization.rpt \
    $step5_hier_utilization_report \
      generated/ila_reference_step5_hierarchical_utilization.rpt \
    $step5_route_report \
      generated/ila_reference_step5_route_status.rpt \
    $step5_debug_report \
      generated/ila_reference_step5_debug_cores.rpt \
    $step5_io_report \
      generated/ila_reference_step5_io.rpt \
    $step5_clock_report \
      generated/ila_reference_step5_clocks.rpt \
    $step5_clock_utilization_report \
      generated/ila_reference_step5_clock_utilization.rpt \
    $step5_methodology_report \
      generated/ila_reference_step5_methodology.rpt] {
  step5_assert_file \
    "Checksum input $step5_checksum_relative_path" \
    $step5_checksum_path
  puts $step5_checksum_handle \
    "[step5_sha256 $step5_checksum_path]  $step5_checksum_relative_path"
}
close $step5_checksum_handle
step5_assert_file {SHA-256 checksum index} $step5_checksums

puts "VIVADO_ILA_STEP_5: PASS"
puts "Routed checkpoint: $step5_routed_dcp"
puts "Bitstream: $step5_bitstream"
puts "Debug probes: $step5_ltx"
puts "Build manifest: $step5_manifest"
puts "Checksum index: $step5_checksums"
puts "Pending Step 6: program the board and confirm BIT/LTX hardware readback"

close_project
