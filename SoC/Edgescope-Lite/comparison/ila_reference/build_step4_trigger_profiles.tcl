# One-command clean reconstruction and offline validation of Steps 1 through 4.

set step4_build_script_dir [file dirname [file normalize [info script]]]

source [file join \
  $step4_build_script_dir build_step3_ila.tcl]
source [file join \
  $step4_build_script_dir validate_step4_trigger_config.tcl]
