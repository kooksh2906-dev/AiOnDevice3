# Offline mock-Hardware-Manager regression for ila_trigger_control.tcl.

set step4_test_dir [file dirname [file normalize [info script]]]
source [file join \
  $step4_test_dir .. hw ila_trigger_control.tcl]

set ::mock_device {hw_device_0}
set ::mock_ilas {hw_ila_0}
set ::mock_probes {hw_probe_0}

array set ::mock_ila_properties {
  STATIC.MAX_DATA_DEPTH 1024
  STATUS.CORE_STATUS IDLE
  CONTROL.TRIG_OUT_MODE DISABLED
}
array set ::mock_probe_properties {
  TYPE ila
  PROBE_PORT 0
  PROBE_PORT_BIT_COUNT 8
  COMPARATOR_COUNT 1
  CAPTURE_COMPARE_VALUE {eq8'bXXXXXXXX}
  TRIGGER_COMPARE_VALUE {eq8'hXX}
}
set ::mock_operation_log {}

proc current_hw_device {args} {
  return $::mock_device
}

proc get_hw_ilas {args} {
  return $::mock_ilas
}

proc get_hw_probes {args} {
  return $::mock_probes
}

proc set_property {property value object} {
  lappend ::mock_operation_log [list set $object $property $value]
  if {$object eq "hw_ila_0"} {
    set ::mock_ila_properties($property) $value
    return
  }
  if {$object eq "hw_probe_0"} {
    set ::mock_probe_properties($property) $value
    return
  }
  error "MOCK: unknown object '$object'"
}

proc get_property {property object} {
  if {$object eq "hw_ila_0"} {
    if {![info exists ::mock_ila_properties($property)]} {
      error "MOCK: missing ILA property '$property'"
    }
    return $::mock_ila_properties($property)
  }
  if {$object eq "hw_probe_0"} {
    if {![info exists ::mock_probe_properties($property)]} {
      error "MOCK: missing probe property '$property'"
    }
    return $::mock_probe_properties($property)
  }
  if {$object eq "hw_probe_1" && $property eq "TYPE"} {
    return ila
  }
  error "MOCK: unknown object '$object'"
}

proc reset_hw_ila {args} {
  set object [lindex $args end]
  if {$object ne "hw_ila_0"} {
    error "MOCK: unknown reset object '$object'"
  }
  lappend ::mock_operation_log [list reset $object]
  set ::mock_ila_properties(CONTROL.DATA_DEPTH) \
    $::mock_ila_properties(STATIC.MAX_DATA_DEPTH)
  set ::mock_ila_properties(CONTROL.WINDOW_COUNT) 1
  set ::mock_ila_properties(CONTROL.TRIGGER_POSITION) 0
  set ::mock_ila_properties(CONTROL.CAPTURE_MODE) ALWAYS
  set ::mock_ila_properties(CONTROL.CAPTURE_CONDITION) AND
  set ::mock_ila_properties(CONTROL.TRIGGER_MODE) BASIC_ONLY
  set ::mock_ila_properties(CONTROL.TRIGGER_CONDITION) AND
  set ::mock_ila_properties(CONTROL.TRIG_OUT_MODE) DISABLED
  set ::mock_probe_properties(CAPTURE_COMPARE_VALUE) {eq8'bXXXXXXXX}
  set ::mock_probe_properties(TRIGGER_COMPARE_VALUE) {eq8'bXXXXXXXX}
}

proc step4_test_assert_equal {label actual expected} {
  if {$actual ne $expected} {
    error "STEP4_MOCK_FAIL: $label actual='$actual' expected='$expected'"
  }
}

proc step4_check_common_geometry {} {
  step4_test_assert_equal {data depth} \
    $::mock_ila_properties(CONTROL.DATA_DEPTH) 1024
  step4_test_assert_equal {window count} \
    $::mock_ila_properties(CONTROL.WINDOW_COUNT) 1
  step4_test_assert_equal {trigger position} \
    $::mock_ila_properties(CONTROL.TRIGGER_POSITION) 512
  step4_test_assert_equal {capture mode} \
    $::mock_ila_properties(CONTROL.CAPTURE_MODE) ALWAYS
  step4_test_assert_equal {capture condition} \
    $::mock_ila_properties(CONTROL.CAPTURE_CONDITION) AND
  step4_test_assert_equal {trigger mode} \
    $::mock_ila_properties(CONTROL.TRIGGER_MODE) BASIC_ONLY
  step4_test_assert_equal {trigger condition} \
    $::mock_ila_properties(CONTROL.TRIGGER_CONDITION) AND
  step4_test_assert_equal {trigger output mode} \
    $::mock_ila_properties(CONTROL.TRIG_OUT_MODE) DISABLED
  step4_test_assert_equal {capture compare value} \
    $::mock_probe_properties(CAPTURE_COMPARE_VALUE) \
    {eq8'bXXXXXXXX}
}

foreach {step4_mode step4_expected} {
  rising     {eq8'bXXXXXXXR}
  falling    {eq8'bXXXXXXXF}
  pattern    {eq8'b1010XXXX}
  no_trigger {eq8'hFF}
} {
  # Deliberately contaminate mutable state before every profile change.
  set ::mock_ila_properties(CONTROL.DATA_DEPTH) 512
  set ::mock_ila_properties(CONTROL.WINDOW_COUNT) 2
  set ::mock_ila_properties(CONTROL.TRIGGER_POSITION) 511
  set ::mock_ila_properties(CONTROL.CAPTURE_MODE) BASIC
  set ::mock_ila_properties(CONTROL.CAPTURE_CONDITION) NOR
  set ::mock_ila_properties(CONTROL.TRIGGER_MODE) ADVANCED_ONLY
  set ::mock_ila_properties(CONTROL.TRIGGER_CONDITION) NOR
  set ::mock_probe_properties(CAPTURE_COMPARE_VALUE) {eq8'hA5}
  set ::mock_probe_properties(TRIGGER_COMPARE_VALUE) {eq8'h5A}

  set step4_log_start [llength $::mock_operation_log]
  set step4_result [::edgescope_ila::configure $step4_mode]
  set step4_first_mutation \
    [lindex $::mock_operation_log $step4_log_start]
  step4_test_assert_equal {reset precedes property writes} \
    [lindex $step4_first_mutation 0] reset
  step4_test_assert_equal {normalized mode} \
    [dict get $step4_result mode] $step4_mode
  step4_test_assert_equal {returned compare value} \
    [dict get $step4_result compare_value] $step4_expected
  step4_test_assert_equal {probe compare value} \
    $::mock_probe_properties(TRIGGER_COMPARE_VALUE) $step4_expected
  step4_check_common_geometry
}

# Mode matching is case-insensitive and every call replaces the old comparator.
::edgescope_ila::configure {  RISING  }
step4_test_assert_equal {case normalization} \
  $::mock_probe_properties(TRIGGER_COMPARE_VALUE) {eq8'bXXXXXXXR}

# Invalid profiles must fail before they modify the previous valid setting.
set step4_before_invalid $::mock_probe_properties(TRIGGER_COMPARE_VALUE)
if {![catch {::edgescope_ila::configure ch7_rising} step4_invalid_error]} {
  error "STEP4_MOCK_FAIL: invalid mode was accepted"
}
step4_test_assert_equal {invalid mode preserved comparator} \
  $::mock_probe_properties(TRIGGER_COMPARE_VALUE) $step4_before_invalid

# A wrong probe width must be rejected.
set ::mock_probe_properties(PROBE_PORT_BIT_COUNT) 7
if {![catch {::edgescope_ila::configure rising} step4_width_error]} {
  error "STEP4_MOCK_FAIL: 7-bit probe was accepted"
}
set ::mock_probe_properties(PROBE_PORT_BIT_COUNT) 8

# A wrong compiled maximum depth and a non-idle core must be rejected.
set ::mock_ila_properties(STATIC.MAX_DATA_DEPTH) 512
if {![catch {::edgescope_ila::configure rising} step4_depth_error]} {
  error "STEP4_MOCK_FAIL: wrong maximum depth was accepted"
}
set ::mock_ila_properties(STATIC.MAX_DATA_DEPTH) 1024

set ::mock_ila_properties(STATUS.CORE_STATUS) PRE_TRIGGER
if {![catch {::edgescope_ila::configure rising} step4_status_error]} {
  error "STEP4_MOCK_FAIL: active ILA was reconfigured"
}
set ::mock_ila_properties(STATUS.CORE_STATUS) IDLE

# Multiple probes must be rejected to prevent an unfair ILA configuration.
set ::mock_probes {hw_probe_0 hw_probe_1}
if {![catch {::edgescope_ila::configure rising} step4_probe_error]} {
  error "STEP4_MOCK_FAIL: multiple probes were accepted"
}
set ::mock_probes {hw_probe_0}

# Missing and multiple ILA objects must both be rejected.
set ::mock_ilas {}
if {![catch {::edgescope_ila::configure rising} step4_no_ila_error]} {
  error "STEP4_MOCK_FAIL: missing ILA was accepted"
}
set ::mock_ilas {hw_ila_0 hw_ila_1}
if {![catch {::edgescope_ila::configure rising} step4_many_ila_error]} {
  error "STEP4_MOCK_FAIL: multiple ILAs were accepted"
}
set ::mock_ilas {hw_ila_0}

# The verifier must detect manual corruption after a valid configuration.
::edgescope_ila::configure pattern
set ::mock_ila_properties(CONTROL.TRIGGER_POSITION) 511
if {![catch {
    ::edgescope_ila::verify_readback \
      hw_ila_0 hw_probe_0 pattern
  } step4_readback_error]} {
  error "STEP4_MOCK_FAIL: corrupted trigger position passed readback"
}

puts "ILA_TRIGGER_CONTROL_MOCK: PASS"
