# Program the bootable comparison-C bitstream and associate its ILA probes.

set bitstream [file normalize [file join [file dirname [info script]] \
  ".." "vitis_artifacts" "vivado_ila_app.bit"]]
set probes_file [file normalize [file join [file dirname [info script]] \
  ".." "hw" "vivado_ila_reference.ltx"]]

proc env_or_default {name default_value} {
  if {[info exists ::env($name)] && $::env($name) ne ""} {
    return $::env($name)
  }
  return $default_value
}

if {![file exists $bitstream]} {
  error "Missing bitstream: $bitstream"
}
if {![file exists $probes_file]} {
  error "Missing ILA probes file: $probes_file"
}

open_hw_manager
connect_hw_server -allow_non_jtag
set target_pattern [env_or_default EDGESCOPE_HW_TARGET \
  {*/xilinx_tcf/Digilent/*}]
set targets [get_hw_targets -quiet $target_pattern]
if {[llength $targets] != 1} {
  error "Expected exactly one hardware target matching '$target_pattern', found [llength $targets]: $targets"
}
current_hw_target [lindex $targets 0]
open_hw_target

set devices [get_hw_devices -quiet xc7a35t_0]
if {[llength $devices] != 1} {
  error "Expected one Basys3 xc7a35t_0, found: [get_hw_devices]"
}
set device [lindex $devices 0]
set_property PROGRAM.FILE $bitstream $device
set_property PROBES.FILE $probes_file $device
set_property FULL_PROBES.FILE $probes_file $device
program_hw_devices $device
refresh_hw_device $device

puts "VIVADO_ILA_PROGRAM: PASS"
puts "VIVADO_ILA_PROGRAM: target=[current_hw_target]"
puts "VIVADO_ILA_PROGRAM: bitstream=$bitstream"
puts "VIVADO_ILA_PROGRAM: probes=$probes_file"

close_hw_target
disconnect_hw_server
close_hw_manager
exit
