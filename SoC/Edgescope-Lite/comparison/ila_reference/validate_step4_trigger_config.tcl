# Vivado-side offline validation of the Step-4 trigger profiles.
#
# This checks the profile strings and confirms that the Step-3 Block Design
# remains unchanged.  Actual HW_PROBE property acceptance/readback is Step 6.

set step4_script_dir [file dirname [file normalize [info script]]]
set step4_common_dir [file normalize [file join \
  $step4_script_dir .. common]]
set step4_hw_script [file join \
  $step4_script_dir hw ila_trigger_control.tcl]
set step4_project_file [file join \
  $step4_common_dir build base_soc edgescope_comparison_base.xpr]
set step4_generated_dir [file join $step4_script_dir generated]

proc step4_fail {message} {
  error "ILA_STEP_4_ASSERTION_FAILED: $message"
}

proc step4_assert_equal {label actual expected} {
  if {![string equal -nocase $actual $expected]} {
    step4_fail "$label: actual='$actual', expected='$expected'"
  }
  puts "ASSERT PASS: $label = $actual"
}

if {![file exists $step4_hw_script]} {
  step4_fail "Trigger control script was not found: $step4_hw_script"
}
if {![file exists $step4_project_file]} {
  step4_fail "Run build_step3_ila.tcl first: $step4_project_file"
}

source $step4_hw_script

foreach {step4_mode step4_expected} {
  rising     {eq8'bXXXXXXXR}
  falling    {eq8'bXXXXXXXF}
  pattern    {eq8'b1010XXXX}
  no_trigger {eq8'hFF}
} {
  step4_assert_equal \
    "Trigger profile $step4_mode" \
    [::edgescope_ila::compare_value $step4_mode] \
    $step4_expected
}

if {![catch {::edgescope_ila::compare_value invalid}]} {
  step4_fail "Invalid trigger profile was accepted"
}

file mkdir $step4_generated_dir
open_project $step4_project_file
open_bd_design [get_files base_soc.bd]

set step4_ila [get_bd_cells -quiet ila_reference_0]
if {[llength $step4_ila] != 1} {
  step4_fail "Step-3 ILA was not found exactly once"
}

step4_assert_equal {ILA VLNV unchanged} \
  [get_property VLNV $step4_ila] {xilinx.com:ip:ila:6.2}
step4_assert_equal {ILA Native mode unchanged} \
  [get_property CONFIG.C_MONITOR_TYPE $step4_ila] Native
step4_assert_equal {ILA depth unchanged} \
  [get_property CONFIG.C_DATA_DEPTH $step4_ila] 1024
step4_assert_equal {ILA probe count unchanged} \
  [get_property CONFIG.C_NUM_OF_PROBES $step4_ila] 1
step4_assert_equal {ILA probe width unchanged} \
  [get_property CONFIG.C_PROBE0_WIDTH $step4_ila] 8
step4_assert_equal {ILA probe type unchanged} \
  [get_property CONFIG.C_PROBE0_TYPE $step4_ila] 0
step4_assert_equal {ILA match unit count unchanged} \
  [get_property CONFIG.C_PROBE0_MU_CNT $step4_ila] 1
step4_assert_equal {ILA advanced trigger unchanged} \
  [get_property CONFIG.C_ADV_TRIGGER $step4_ila] FALSE

set step4_ila_count 0
foreach step4_cell [get_bd_cells -hier -quiet] {
  if {[get_property -quiet VLNV $step4_cell] eq \
      {xilinx.com:ip:ila:6.2}} {
    incr step4_ila_count
  }
}
step4_assert_equal {ILA count unchanged} $step4_ila_count 1

set step4_report [file join \
  $step4_generated_dir ila_reference_step4_trigger_contract.rpt]
set step4_report_handle [open $step4_report w]
puts $step4_report_handle \
  {EdgeScope-Lite Vivado ILA Reference - Step 4 Trigger Contract}
puts $step4_report_handle \
  {===============================================================}
puts $step4_report_handle {Common Runtime Geometry}
puts $step4_report_handle {  CONTROL.DATA_DEPTH       : 1024}
puts $step4_report_handle {  CONTROL.WINDOW_COUNT     : 1}
puts $step4_report_handle {  CONTROL.TRIGGER_POSITION : 512}
puts $step4_report_handle {  CONTROL.CAPTURE_MODE     : ALWAYS}
puts $step4_report_handle {  CONTROL.CAPTURE_CONDITION: AND}
puts $step4_report_handle {  CONTROL.TRIGGER_MODE     : BASIC_ONLY}
puts $step4_report_handle {  CONTROL.TRIGGER_CONDITION: AND}
puts $step4_report_handle {  CAPTURE_COMPARE_VALUE    : eq8'bXXXXXXXX}
puts $step4_report_handle {}
puts $step4_report_handle {Trigger Profiles}
puts $step4_report_handle {  rising     : eq8'bXXXXXXXR}
puts $step4_report_handle {  falling    : eq8'bXXXXXXXF}
puts $step4_report_handle {  pattern    : eq8'b1010XXXX}
puts $step4_report_handle {  no_trigger : eq8'hFF}
puts $step4_report_handle {}
puts $step4_report_handle \
  {Normalized indices: pre=0..511, trigger=512, post-extra=513..1023}
puts $step4_report_handle \
  {Block Design / ILA structure: UNCHANGED AND OFFLINE-VALIDATED}
puts $step4_report_handle \
  {Hardware Manager apply/readback: PENDING STEP 6}
puts $step4_report_handle \
  {Bitstream / LTX: PENDING STEP 5}
close $step4_report_handle

puts "VIVADO_ILA_TRIGGER_STEP_4_OFFLINE: PASS"
puts "Trigger contract: $step4_report"

close_project
