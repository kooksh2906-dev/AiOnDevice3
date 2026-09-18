set script_dir [file dirname [file normalize [info script]]]
set reference_dir [file dirname $script_dir]
set ::edgescope_step8_library_only 1
source [file join $reference_dir hw run_step8_pulse_stress.tcl]
unset ::edgescope_step8_library_only

foreach command {
  ::edgescope_step6::validate_inputs
  ::edgescope_step6::program_and_pair
  ::edgescope_step8::runtime_run
  ::edgescope_step8::capture_trial
  ::edgescope_step8::run
} {
  if {[llength [info commands $command]] != 1} {
    error "STEP8_TCL_LOAD: missing command $command"
  }
}
if {$::edgescope_step8::widths ne {1 10 100 1000 10000 100000}} {
  error "STEP8_TCL_LOAD: frozen width list changed"
}
if {$::edgescope_step8::repetitions != 10} {
  error "STEP8_TCL_LOAD: frozen repetition count changed"
}
puts {STEP8_TCL_LOAD: PASS}
