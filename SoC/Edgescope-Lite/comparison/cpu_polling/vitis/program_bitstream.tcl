set bitstream [file normalize [file join [file dirname [info script]] \
    ".." "vitis_artifacts" "cpu_polling_app.bit"]]

if {![file exists $bitstream]} {
    error "Missing bitstream: $bitstream"
}

open_hw_manager
connect_hw_server -allow_non_jtag
set targets [get_hw_targets *Digilent/210183BEA282A]
if {[llength $targets] != 1} {
    error "Expected exactly one hardware target, found [llength $targets]"
}

current_hw_target [lindex $targets 0]
open_hw_target
set devices [get_hw_devices xc7a35t_0]
if {[llength $devices] != 1} {
    error "Expected xc7a35t_0, found: [get_hw_devices]"
}

set device [lindex $devices 0]
set_property PROGRAM.FILE $bitstream $device
program_hw_devices $device
refresh_hw_device $device
puts "CPU_POLL_PROGRAM_BIT_PASS target=[current_hw_target]"
puts "CPU_POLL_PROGRAM_BIT_PASS device=$device"
puts "CPU_POLL_PROGRAM_BIT_PASS bitstream=$bitstream"

close_hw_target
disconnect_hw_server
close_hw_manager
exit
