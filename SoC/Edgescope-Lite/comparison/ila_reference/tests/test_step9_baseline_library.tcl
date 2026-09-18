# Host-side smoke test for the Step 9 baseline Tcl helpers.
#
# Run with:
#   tclsh comparison/ila_reference/tests/test_step9_baseline_library.tcl

set test_dir [file dirname [file normalize [info script]]]
set ila_dir [file normalize [file join $test_dir ..]]
set ::edgescope_step9_baseline_library_only 1
source [file join $ila_dir build_step9_common_baseline.tcl]

set known_good_route_report [file join \
  $ila_dir generated ila_reference_step5_route_status.rpt]
::edgescope_step9_baseline::assert_route_complete \
  $known_good_route_report

set xdc_path [file join \
  $ila_dir constraints step9_baseline_common.xdc]
set xdc_channel [open $xdc_path r]
try {
  set xdc_text [read $xdc_channel]
} finally {
  close $xdc_channel
}
if {[regexp -line {^[[:space:]]*if[[:space:]]} $xdc_text]} {
  error "STEP9_BASELINE_TEST: unsupported Tcl 'if' command remains in XDC"
}

puts "STEP9_BASELINE_LIBRARY_TEST: PASS"
