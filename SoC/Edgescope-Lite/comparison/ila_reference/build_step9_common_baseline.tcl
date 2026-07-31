# Step 9: isolated common Base SoC + Test Pattern Generator implementation.
#
# The mutable comparison/common/build project is also used by the ILA flow and
# therefore cannot serve as a no-analyzer baseline.  This script copies the
# frozen common sources byte-for-byte into a private build directory, rebuilds
# Steps 1 and 2, then performs a clean routed implementation with the same
# Vivado version, FPGA part, clock, and default strategies as the ILA build.

namespace eval ::edgescope_step9_baseline {
  variable required_vivado_version {2024.2}
  variable required_part {xc7a35tcpg236-1}
  variable required_board_part {digilentinc.com:basys3:part0:1.2}

  variable baseline_tcl_file [file normalize [info script]]
  variable script_dir [file dirname $baseline_tcl_file]
  variable baseline_runner_file [file join \
    $script_dir run_step9_common_baseline.sh]
  variable repository_root [file normalize [file join $script_dir .. ..]]
  variable common_dir [file normalize [file join $script_dir .. common]]
  variable build_dir [file join $script_dir build step9_common_baseline]
  variable staged_common_dir [file join $build_dir staged_common]
  variable project_file [file join \
    $staged_common_dir build base_soc edgescope_comparison_base.xpr]
  variable result_dir [file join $script_dir results step9 baseline_raw]
  variable constraint_file [file join \
    $script_dir constraints step9_baseline_common.xdc]
  variable routed_dcp [file join \
    $build_dir common_base_plus_generator_routed.dcp]

  variable utilization_report [file join \
    $result_dir baseline_utilization.rpt]
  variable hierarchical_report [file join \
    $result_dir baseline_hierarchical_utilization.rpt]
  variable timing_report [file join \
    $result_dir baseline_timing_summary.rpt]
  variable check_timing_report [file join \
    $result_dir baseline_check_timing.rpt]
  variable route_report [file join \
    $result_dir baseline_route_status.rpt]
  variable drc_report [file join \
    $result_dir baseline_drc.rpt]
  variable build_manifest [file join \
    $result_dir baseline_build_manifest.rpt]
}

proc ::edgescope_step9_baseline::fail {message} {
  error "STEP9_BASELINE_ASSERTION_FAILED: $message"
}

proc ::edgescope_step9_baseline::assert_equal {label actual expected} {
  if {![string equal -nocase $actual $expected]} {
    fail "$label: actual='$actual', expected='$expected'"
  }
  puts "ASSERT PASS: $label = $actual"
}

proc ::edgescope_step9_baseline::assert_true {label value} {
  if {![expr {bool($value)}]} {
    fail "$label: expected true, actual='$value'"
  }
  puts "ASSERT PASS: $label"
}

proc ::edgescope_step9_baseline::require_file {label path} {
  if {![file isfile $path] || [file size $path] <= 0} {
    fail "$label is missing or empty: $path"
  }
  puts "ARTIFACT PASS: $label size=[file size $path] path=$path"
}

proc ::edgescope_step9_baseline::sha256 {path} {
  require_file {SHA-256 input} $path
  set result [exec sha256sum -- $path]
  set digest [string tolower [lindex $result 0]]
  if {![regexp {^[0-9a-f]{64}$} $digest]} {
    fail "invalid SHA-256 for $path: $digest"
  }
  return $digest
}

proc ::edgescope_step9_baseline::assert_route_complete {path} {
  require_file {route status report} $path
  set route_channel [open $path r]
  try {
    set route_text [read $route_channel]
  } finally {
    close $route_channel
  }
  if {![regexp \
      {# of nets with routing errors[. ]*:[ ]*0[ ]*:} \
      $route_text] ||
      ![regexp \
      {# of routable nets[. ]*:[ ]*([0-9]+)[ ]*:} \
      $route_text -> routable_net_count] ||
      ![regexp \
      {# of fully routed nets[. ]*:[ ]*([0-9]+)[ ]*:} \
      $route_text -> fully_routed_net_count]} {
    fail "route report does not prove a fully routed zero-error design"
  }
  if {$routable_net_count != $fully_routed_net_count} {
    fail \
      "route report is incomplete: routable=$routable_net_count fully_routed=$fully_routed_net_count"
  }
  puts \
    "ASSERT PASS: route complete routable=$routable_net_count fully_routed=$fully_routed_net_count errors=0"
}

proc ::edgescope_step9_baseline::assert_drc_clean {report_name} {
  set counts [dict create errors 0 critical_warnings 0 warnings 0 other 0]
  foreach violation [get_drc_violations -quiet -name $report_name] {
    set severity [string tolower [get_property SEVERITY $violation]]
    switch -exact -- $severity {
      error {
        dict incr counts errors
      }
      {critical warning} {
        dict incr counts critical_warnings
      }
      warning {
        dict incr counts warnings
      }
      default {
        dict incr counts other
      }
    }
  }
  if {[dict get $counts errors] != 0 ||
      [dict get $counts critical_warnings] != 0} {
    fail \
      "DRC has fatal violations: errors=[dict get $counts errors] critical_warnings=[dict get $counts critical_warnings]"
  }
  puts \
    "ASSERT PASS: DRC fatal-free errors=[dict get $counts errors] critical_warnings=[dict get $counts critical_warnings] warnings=[dict get $counts warnings] other=[dict get $counts other]"
  return $counts
}

proc ::edgescope_step9_baseline::assert_run_complete {
    run_name expected_step} {
  set run_object [get_runs -quiet $run_name]
  if {[llength $run_object] != 1} {
    fail "run '$run_name' was not found exactly once"
  }
  set progress [get_property PROGRESS $run_object]
  set status [get_property STATUS $run_object]
  set needs_refresh [get_property NEEDS_REFRESH $run_object]
  if {$progress ne {100%} ||
      ![string match -nocase "${expected_step} Complete*" $status] ||
      [regexp -nocase {error|fail|cancel} $status] ||
      [expr {bool($needs_refresh)}]} {
    fail \
      "$run_name incomplete: progress=$progress status='$status' needs_refresh=$needs_refresh"
  }
  puts "RUN PASS: $run_name progress=$progress status='$status'"
}

proc ::edgescope_step9_baseline::write_manifest {fields} {
  variable build_manifest
  file mkdir [file dirname $build_manifest]
  set temporary "${build_manifest}.[pid].tmp"
  set channel [open $temporary w]
  try {
    puts $channel \
      {# EdgeScope-Lite Step 9 common Base+Generator build manifest}
    dict for {key value} $fields {
      set clean [string map [list "\n" "\\n" "\r" ""] $value]
      puts $channel "${key}=${clean}"
    }
  } finally {
    close $channel
  }
  file rename -force $temporary $build_manifest
}

proc ::edgescope_step9_baseline::run {} {
  variable required_vivado_version
  variable required_part
  variable required_board_part
  variable script_dir
  variable baseline_tcl_file
  variable baseline_runner_file
  variable repository_root
  variable common_dir
  variable build_dir
  variable staged_common_dir
  variable project_file
  variable result_dir
  variable constraint_file
  variable routed_dcp
  variable utilization_report
  variable hierarchical_report
  variable timing_report
  variable check_timing_report
  variable route_report
  variable drc_report
  variable build_manifest

  set current_version [version -short]
  if {[string first $required_vivado_version $current_version] != 0} {
    fail \
      "Vivado $required_vivado_version is required; running $current_version"
  }

  set common_sources [list \
    base_soc.tcl \
    add_test_pattern_generator.tcl \
    build_base_with_generator.tcl]
  set rtl_sources [list \
    test_pattern_generator.sv \
    test_pattern_generator_gpio_adapter.v]
  foreach source_name $common_sources {
    require_file \
      "common source $source_name" \
      [file join $common_dir $source_name]
  }
  foreach source_name $rtl_sources {
    require_file \
      "common RTL $source_name" \
      [file join $common_dir rtl $source_name]
  }
  require_file {baseline constraint} $constraint_file

  # Remove only the known private staging tree.  The canonical CPU input and
  # prior Step 8 evidence directories are outside this target.
  if {[file exists $staged_common_dir]} {
    file delete -force $staged_common_dir
  }
  file mkdir $staged_common_dir
  file mkdir [file join $staged_common_dir rtl]
  file mkdir $result_dir

  foreach source_name $common_sources {
    set original [file join $common_dir $source_name]
    set staged [file join $staged_common_dir $source_name]
    file copy -force $original $staged
    assert_equal \
      "staged hash $source_name" \
      [sha256 $staged] \
      [sha256 $original]
  }
  foreach source_name $rtl_sources {
    set original [file join $common_dir rtl $source_name]
    set staged [file join $staged_common_dir rtl $source_name]
    file copy -force $original $staged
    assert_equal \
      "staged RTL hash $source_name" \
      [sha256 $staged] \
      [sha256 $original]
  }

  foreach stale_file [list \
      $utilization_report \
      $hierarchical_report \
      $timing_report \
      $check_timing_report \
      $route_report \
      $drc_report \
      $build_manifest \
      $routed_dcp] {
    if {[file exists $stale_file]} {
      file delete -force $stale_file
    }
  }

  # The copied scripts preserve the frozen design source hashes while their
  # relative build path keeps this baseline isolated from the ILA project.
  source [file join $staged_common_dir build_base_with_generator.tcl]
  require_file {isolated Step-2 project} $project_file

  set_param general.maxThreads 2
  open_project $project_file
  assert_equal \
    {FPGA part} \
    [get_property PART [current_project]] \
    $required_part
  assert_equal \
    {Board part} \
    [get_property BOARD_PART [current_project]] \
    $required_board_part

  set bd_file [get_files -quiet base_soc.bd]
  if {[llength $bd_file] != 1} {
    fail "base_soc.bd was not found exactly once"
  }
  open_bd_design $bd_file
  if {[catch {validate_bd_design} validation_error]} {
    fail "isolated baseline Validate Design failed: $validation_error"
  }

  set generator_cells \
    [get_bd_cells -quiet test_pattern_generator_gpio_adapter_0]
  if {[llength $generator_cells] != 1} {
    fail "common Generator was not found exactly once"
  }
  if {[llength [get_bd_cells -hier -quiet \
      -filter {VLNV =~ "xilinx.com:ip:ila:*"}]] != 0} {
    fail "Vivado ILA is forbidden in the common baseline"
  }
  if {[llength [get_bd_cells -hier -quiet \
      -filter {VLNV =~ "xilinx.com:ip:vio:*"}]] != 0} {
    fail "VIO is forbidden in the common baseline"
  }
  foreach cell [get_bd_cells -hier -quiet] {
    set vlnv [get_property -quiet VLNV $cell]
    if {[regexp -nocase \
        {(circular_trace_buffer|probe_sampler|basic_trigger_engine)} \
        $vlnv]} {
      fail "Custom analyzer IP is forbidden in the common baseline: $cell"
    }
  }
  save_bd_design
  generate_target all $bd_file
  make_wrapper -files $bd_file -top -import -force
  set_property top base_soc_wrapper [get_filesets sources_1]

  if {[llength [get_files -quiet [list $constraint_file]]] == 0} {
    add_files -fileset constrs_1 -norecurse [list $constraint_file]
  }
  set constraint_object [get_files -quiet [list $constraint_file]]
  if {[llength $constraint_object] != 1} {
    fail "baseline constraint was not registered exactly once"
  }
  set_property USED_IN_SYNTHESIS true $constraint_object
  set_property USED_IN_IMPLEMENTATION true $constraint_object
  set_property PROCESSING_ORDER EARLY $constraint_object
  update_compile_order -fileset sources_1
  close_bd_design [get_bd_designs base_soc]

  set synth_run [get_runs synth_1]
  set impl_run [get_runs impl_1]
  assert_equal \
    {Synthesis strategy} \
    [get_property STRATEGY $synth_run] \
    {Vivado Synthesis Defaults}
  assert_equal \
    {Implementation strategy} \
    [get_property STRATEGY $impl_run] \
    {Vivado Implementation Defaults}

  reset_run synth_1
  launch_runs synth_1 -jobs 1
  wait_on_run synth_1
  assert_run_complete synth_1 synth_design

  open_run synth_1
  set synthesized_generators \
    [get_cells -hier -quiet *test_pattern_generator_gpio_adapter_0]
  if {[llength $synthesized_generators] != 1} {
    fail \
      "synthesized Generator hierarchy count is [llength $synthesized_generators], expected 1"
  }
  assert_true \
    {Generator DONT_TOUCH readback} \
    [get_property DONT_TOUCH $synthesized_generators]
  if {[llength [get_cells -hier -quiet -filter \
      {REF_NAME =~ "*ila*"}]] != 0} {
    fail "ILA-like synthesized hierarchy is forbidden in the common baseline"
  }
  close_design

  launch_runs impl_1 -to_step route_design -jobs 1
  wait_on_run impl_1
  assert_run_complete impl_1 route_design
  open_run impl_1

  set implemented_top [get_property TOP [get_filesets sources_1]]
  assert_equal {Implemented top} $implemented_top base_soc_wrapper
  if {[llength [get_debug_cores -quiet]] != 0} {
    fail "Debug cores are forbidden in the common baseline"
  }
  set implemented_generators \
    [get_cells -hier -quiet *test_pattern_generator_gpio_adapter_0]
  if {[llength $implemented_generators] != 1} {
    fail \
      "implemented Generator hierarchy count is [llength $implemented_generators], expected 1"
  }

  report_utilization -file $utilization_report
  report_utilization \
    -hierarchical \
    -hierarchical_depth 4 \
    -file $hierarchical_report
  report_timing_summary \
    -delay_type min_max \
    -report_unconstrained \
    -check_timing_verbose \
    -max_paths 10 \
    -input_pins \
    -file $timing_report
  check_timing -verbose -file $check_timing_report
  report_route_status -file $route_report
  set drc_report_name step9_common_baseline_post_route_drc
  report_drc \
    -name $drc_report_name \
    -ruledecks {default bitstream_checks} \
    -no_waivers \
    -file $drc_report
  set drc_counts [assert_drc_clean $drc_report_name]
  write_checkpoint -force $routed_dcp

  foreach artifact [list \
      $utilization_report \
      $hierarchical_report \
      $timing_report \
      $check_timing_report \
      $route_report \
      $drc_report \
      $routed_dcp] {
    require_file {baseline output} $artifact
  }

  set setup_failures [get_timing_paths \
    -quiet -delay_type max -max_paths 1 -slack_lesser_than 0]
  set hold_failures [get_timing_paths \
    -quiet -delay_type min -max_paths 1 -slack_lesser_than 0]
  if {[llength $setup_failures] != 0 ||
      [llength $hold_failures] != 0} {
    fail \
      "timing violations remain: setup=[llength $setup_failures], hold=[llength $hold_failures]"
  }

  assert_route_complete $route_report

  set git_commit [string trim \
    [exec git -C $repository_root rev-parse HEAD]]
  set git_dirty [expr {
    [string trim \
      [exec git -C $repository_root status --porcelain]] ne {}
  }]
  set fields [dict create \
    STEP 9 \
    BUILD_SCOPE COMMON_BASE_PLUS_GENERATOR \
    OVERALL PASS \
    VIVADO_VERSION $current_version \
    FPGA_PART [get_property PART [current_project]] \
    BOARD_PART [get_property BOARD_PART [current_project]] \
    TOP $implemented_top \
    DESIGN_STATE ROUTED \
    CLOCK_HZ 100000000 \
    CLOCK_PERIOD_NS 10.000 \
    SYNTHESIS_STRATEGY [get_property STRATEGY $synth_run] \
    IMPLEMENTATION_STRATEGY [get_property STRATEGY $impl_run] \
    VIVADO_ILA_COUNT 0 \
    VIO_COUNT 0 \
    CUSTOM_ANALYZER_COUNT 0 \
    DEBUG_CORE_COUNT [llength [get_debug_cores -quiet]] \
    GENERATOR_HIERARCHY_COUNT [llength $implemented_generators] \
    GENERATOR_DONT_TOUCH \
      [get_property DONT_TOUCH $implemented_generators] \
    DRC_ERROR_COUNT [dict get $drc_counts errors] \
    DRC_CRITICAL_WARNING_COUNT \
      [dict get $drc_counts critical_warnings] \
    DRC_WARNING_COUNT [dict get $drc_counts warnings] \
    DRC_OTHER_COUNT [dict get $drc_counts other] \
    GIT_COMMIT $git_commit \
    GIT_WORKTREE_DIRTY $git_dirty \
    BASE_SOC_TCL_SHA256 [sha256 [file join $common_dir base_soc.tcl]] \
    GENERATOR_INTEGRATION_TCL_SHA256 \
      [sha256 [file join $common_dir add_test_pattern_generator.tcl]] \
    GENERATOR_RTL_SHA256 \
      [sha256 [file join $common_dir rtl test_pattern_generator.sv]] \
    GENERATOR_ADAPTER_SHA256 \
      [sha256 [file join \
        $common_dir rtl test_pattern_generator_gpio_adapter.v]] \
    BASE_BUILD_TCL_SHA256 \
      [sha256 [file join $common_dir build_base_with_generator.tcl]] \
    BASELINE_CONSTRAINT_SHA256 [sha256 $constraint_file] \
    BASELINE_TCL_SHA256 \
      [sha256 $baseline_tcl_file] \
    BASELINE_RUNNER_SHA256 \
      [sha256 $baseline_runner_file] \
    ROUTED_DCP_SHA256 [sha256 $routed_dcp] \
    UTILIZATION_REPORT_SHA256 [sha256 $utilization_report] \
    HIERARCHICAL_REPORT_SHA256 [sha256 $hierarchical_report] \
    TIMING_REPORT_SHA256 [sha256 $timing_report] \
    CHECK_TIMING_REPORT_SHA256 [sha256 $check_timing_report] \
    ROUTE_REPORT_SHA256 [sha256 $route_report] \
    DRC_REPORT_SHA256 [sha256 $drc_report] \
    NEXT_ACTION HOST_STEP9_EXTRACTION]
  write_manifest $fields
  require_file {baseline build manifest} $build_manifest

  puts "STEP9_COMMON_BASELINE: PASS"
  puts "RESULTS: [file normalize $result_dir]"
  close_design
  close_project
}

if {![info exists ::edgescope_step9_baseline_library_only] ||
    !$::edgescope_step9_baseline_library_only} {
  ::edgescope_step9_baseline::run
}
