# One-command clean reconstruction of completed comparison Steps 1 through 3.

set step3_build_script_dir [file dirname [file normalize [info script]]]
set step3_build_common_dir [file normalize [file join \
  $step3_build_script_dir .. common]]

source [file join \
  $step3_build_common_dir build_base_with_generator.tcl]
source [file join \
  $step3_build_script_dir add_vivado_ila.tcl]
