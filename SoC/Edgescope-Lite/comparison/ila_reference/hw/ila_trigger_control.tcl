# EdgeScope-Lite Vivado ILA runtime trigger configuration.
#
# Load this file after opening Hardware Manager, opening the target, and
# programming the Step-5 bitstream/LTX:
#
#   source comparison/ila_reference/hw/ila_trigger_control.tcl
#   edgescope_ila::configure rising
#
# Supported profiles:
#   rising     CH0 low-to-high transition
#   falling    CH0 high-to-low transition
#   pattern    (probe & 8'hF0) == 8'hA0
#   no_trigger P-05 safety condition, probe == 8'hFF while Generator is 0
#
# This file configures and reads back the Hardware Manager properties.  It
# deliberately does not call run_hw_ila, trigger_now, or auto re-trigger.

namespace eval ::edgescope_ila {
  variable data_depth 1024
  variable window_count 1
  variable trigger_position 512

  variable compare_values [dict create \
    rising     {eq8'bXXXXXXXR} \
    falling    {eq8'bXXXXXXXF} \
    pattern    {eq8'b1010XXXX} \
    no_trigger {eq8'hFF}]

  variable descriptions [dict create \
    rising     {CH0 Rising Edge} \
    falling    {CH0 Falling Edge} \
    pattern    {Masked Pattern: pattern=0xA0, mask=0xF0} \
    no_trigger {P-05 impossible condition: probe=0xFF}]

  proc fail {message} {
    error "EDGESCOPE_ILA_TRIGGER_ERROR: $message"
  }

  proc assert_equal {label actual expected} {
    if {![string equal -nocase $actual $expected]} {
      fail "$label: actual='$actual', expected='$expected'"
    }
    puts "READBACK PASS: $label = $actual"
  }

  proc supported_modes {} {
    return {rising falling pattern no_trigger}
  }

  proc normalize_mode {mode} {
    set normalized [string tolower [string trim $mode]]
    if {$normalized ni [supported_modes]} {
      fail \
        "Unsupported mode '$mode'; use rising, falling, pattern, or no_trigger"
    }
    return $normalized
  }

  proc compare_value {mode} {
    variable compare_values
    set normalized [normalize_mode $mode]
    return [dict get $compare_values $normalized]
  }

  proc description {mode} {
    variable descriptions
    set normalized [normalize_mode $mode]
    return [dict get $descriptions $normalized]
  }

  proc get_single_ila {} {
    set device [current_hw_device]
    if {[llength $device] != 1} {
      fail \
        "Exactly one current Hardware Device is required; open a target first"
    }

    set ilas [get_hw_ilas -of_objects $device]
    if {[llength $ilas] != 1} {
      fail \
        "Expected exactly one ILA on the current device, found [llength $ilas]"
    }
    return [lindex $ilas 0]
  }

  proc get_single_probe {ila} {
    set ila_probes {}
    foreach probe [get_hw_probes -of_objects $ila] {
      if {[string equal -nocase [get_property TYPE $probe] ila]} {
        lappend ila_probes $probe
      }
    }
    if {[llength $ila_probes] != 1} {
      fail \
        "Expected exactly one ILA probe, found [llength $ila_probes]"
    }
    return [lindex $ila_probes 0]
  }

  proc validate_static_hardware {ila probe} {
    variable data_depth

    assert_equal {Maximum data depth} \
      [get_property STATIC.MAX_DATA_DEPTH $ila] $data_depth
    assert_equal {Core status before configuration} \
      [get_property STATUS.CORE_STATUS $ila] IDLE
    assert_equal {Probe type} \
      [get_property TYPE $probe] ila
    assert_equal {Probe port} \
      [get_property PROBE_PORT $probe] 0
    assert_equal {Probe bit count} \
      [get_property PROBE_PORT_BIT_COUNT $probe] 8
    assert_equal {Probe comparator count} \
      [get_property COMPARATOR_COUNT $probe] 1
  }

  proc apply_common_geometry {ila} {
    variable data_depth
    variable window_count
    variable trigger_position

    # Some ILA configurations expose default-only controls as read-only.
    # Avoid writing them when reset_hw_ila already restored the required value,
    # while still verifying every value in verify_readback.
    foreach {property value} [list \
      CONTROL.DATA_DEPTH $data_depth \
      CONTROL.WINDOW_COUNT $window_count \
      CONTROL.TRIGGER_POSITION $trigger_position \
      CONTROL.CAPTURE_MODE ALWAYS \
      CONTROL.CAPTURE_CONDITION AND \
      CONTROL.TRIGGER_MODE BASIC_ONLY \
      CONTROL.TRIGGER_CONDITION AND] {
      if {[get_property $property $ila] ne $value} {
        set_property $property $value $ila
      }
    }
  }

  proc verify_readback {ila probe mode} {
    variable data_depth
    variable window_count
    variable trigger_position

    assert_equal {Data depth} \
      [get_property CONTROL.DATA_DEPTH $ila] $data_depth
    assert_equal {Window count} \
      [get_property CONTROL.WINDOW_COUNT $ila] $window_count
    assert_equal {Trigger position} \
      [get_property CONTROL.TRIGGER_POSITION $ila] $trigger_position
    assert_equal {Capture mode} \
      [get_property CONTROL.CAPTURE_MODE $ila] ALWAYS
    assert_equal {Capture condition} \
      [get_property CONTROL.CAPTURE_CONDITION $ila] AND
    assert_equal {Trigger mode} \
      [get_property CONTROL.TRIGGER_MODE $ila] BASIC_ONLY
    assert_equal {Trigger condition} \
      [get_property CONTROL.TRIGGER_CONDITION $ila] AND
    assert_equal {Trigger output mode} \
      [get_property CONTROL.TRIG_OUT_MODE $ila] DISABLED
    assert_equal {Capture compare value} \
      [get_property CAPTURE_COMPARE_VALUE $probe] \
      {eq8'bXXXXXXXX}
    assert_equal {Trigger compare value} \
      [get_property TRIGGER_COMPARE_VALUE $probe] \
      [compare_value $mode]
  }

  proc configure {mode} {
    set normalized [normalize_mode $mode]
    set ila [get_single_ila]
    set probe [get_single_probe $ila]

    validate_static_hardware $ila $probe

    # Reset every mutable ILA/probe value so a previous GUI session or mode
    # cannot leak a stale comparator or capture condition into this run.
    reset_hw_ila -reset_compare_values true $ila
    apply_common_geometry $ila
    set_property CAPTURE_COMPARE_VALUE {eq8'bXXXXXXXX} $probe
    set_property TRIGGER_COMPARE_VALUE [compare_value $normalized] $probe
    verify_readback $ila $probe $normalized

    puts "EDGESCOPE_ILA_TRIGGER_CONFIG: PASS"
    puts "Mode: $normalized"
    puts "Description: [description $normalized]"
    puts "Compare: [compare_value $normalized]"
    puts "Next: run_hw_ila, wait for Waiting for Trigger, then START Generator"

    return [dict create \
      mode $normalized \
      compare_value [compare_value $normalized] \
      ila $ila \
      probe $probe]
  }
}
