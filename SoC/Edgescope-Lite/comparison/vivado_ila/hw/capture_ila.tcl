# Arm comparison C, wait for the common Generator event, then export CSV.
#
# GUI-facing environment contract:
#   EDGESCOPE_ILA_MODE     RISING, FALLING, or PATTERN (default RISING)
#   EDGESCOPE_ILA_CSV      output CSV path
#   EDGESCOPE_ILA_PROGRAM  set to 1 to program before capture (default 0)
#   EDGESCOPE_ILA_BIT      optional BIT override
#   EDGESCOPE_ILA_LTX      optional LTX override
#   EDGESCOPE_HW_TARGET    optional exact target name or glob pattern
#
# After run_hw_ila this script prints and flushes exactly:
#   VIVADO_ILA_ARMED
# The GUI may then send the matching UART command.  A successful export ends:
#   VIVADO_ILA_CAPTURE_PASS,CSV=<absolute path>

set script_dir [file dirname [file normalize [info script]]]

proc env_or_default {name default_value} {
  if {[info exists ::env($name)] && $::env($name) ne ""} {
    return $::env($name)
  }
  return $default_value
}

proc set_and_verify_hw_property {object property expected} {
  set supported_properties [list_property $object]
  if {[lsearch -exact $supported_properties $property] < 0} {
    puts "VIVADO_ILA_PROPERTY_UNAVAILABLE,$property"
    return
  }
  set_property $property $expected $object
  set actual [get_property $property $object]
  if {![string equal -nocase $actual $expected]} {
    error "ILA run-control assertion failed: $property=$actual, expected=$expected"
  }
}

set capture_mode [string toupper \
  [env_or_default EDGESCOPE_ILA_MODE RISING]]
set csv_file [file normalize [env_or_default EDGESCOPE_ILA_CSV \
  [file join $script_dir .. results vivado_ila_capture.csv]]]
set program_device [env_or_default EDGESCOPE_ILA_PROGRAM 0]
set bit_file [file normalize [env_or_default EDGESCOPE_ILA_BIT \
  [file join $script_dir vivado_ila_reference.bit]]]
set ltx_file [file normalize [env_or_default EDGESCOPE_ILA_LTX \
  [file join $script_dir vivado_ila_reference.ltx]]]

switch -- $capture_mode {
  RISING {
    set trigger_compare {eq8'bxxxxxxxR}
  }
  FALLING {
    set trigger_compare {eq8'bxxxxxxxF}
  }
  PATTERN {
    # Match A0/F0, the same masked-pattern condition as comparisons A/B.
    set trigger_compare {eq8'b1010xxxx}
  }
  default {
    error "EDGESCOPE_ILA_MODE must be RISING, FALLING, or PATTERN"
  }
}

if {$program_device ni {0 1}} {
  error "EDGESCOPE_ILA_PROGRAM must be 0 or 1"
}
if {![file exists $ltx_file]} {
  error "ILA probes file does not exist: $ltx_file"
}
if {$program_device && ![file exists $bit_file]} {
  error "ILA bitstream does not exist: $bit_file"
}
file mkdir [file dirname $csv_file]

open_hw_manager
connect_hw_server
set target_pattern [env_or_default EDGESCOPE_HW_TARGET \
  {*/xilinx_tcf/Digilent/*}]
set targets [get_hw_targets -quiet $target_pattern]
if {[llength $targets] != 1} {
  error "Expected exactly one hardware target matching '$target_pattern', found [llength $targets]: $targets"
}
current_hw_target [lindex $targets 0]
open_hw_target

set devices [get_hw_devices -quiet]
if {[llength $devices] != 1} {
  error "Expected exactly one JTAG device, found: $devices"
}
set device [lindex $devices 0]
current_hw_device $device

set_property PROBES.FILE $ltx_file $device
set_property FULL_PROBES.FILE $ltx_file $device
if {$program_device} {
  set_property PROGRAM.FILE $bit_file $device
  program_hw_devices $device
}
refresh_hw_device $device

set ilas [get_hw_ilas -quiet -of_objects $device]
if {[llength $ilas] != 1} {
  error "Expected exactly one ILA core, found: $ilas"
}
set ila [lindex $ilas 0]
set probes [get_hw_probes -quiet -of_objects $ila]
if {[llength $probes] != 1} {
  error "Expected exactly one 8-bit ILA probe, found: $probes"
}
set probe [lindex $probes 0]

set_and_verify_hw_property $ila CONTROL.DATA_DEPTH 1024
set_and_verify_hw_property $ila CONTROL.WINDOW_COUNT 1
set_and_verify_hw_property $ila CONTROL.TRIGGER_POSITION 512
set_and_verify_hw_property $ila CONTROL.TRIGGER_MODE BASIC_ONLY
set_and_verify_hw_property $ila CONTROL.TRIGGER_CONDITION AND
set_and_verify_hw_property $ila CONTROL.CAPTURE_MODE ALWAYS
set_property TRIGGER_COMPARE_VALUE $trigger_compare $probe
run_hw_ila $ila
puts "VIVADO_ILA_ARMED"
flush stdout

wait_on_hw_ila $ila
set capture_data [upload_hw_ila_data $ila]
write_hw_ila_data -force -csv_file $csv_file $capture_data

if {![file exists $csv_file]} {
  error "ILA capture completed but CSV was not created: $csv_file"
}
puts "VIVADO_ILA_CAPTURE_PASS,CSV=$csv_file"
flush stdout

close_hw_target
disconnect_hw_server
close_hw_manager
