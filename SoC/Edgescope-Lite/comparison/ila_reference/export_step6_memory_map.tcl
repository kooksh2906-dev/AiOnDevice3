# EdgeScope-Lite Vivado ILA reference - Step 6 BRAM memory map export.
#
# This reuses the routed Step-5 checkpoint.  It does not synthesize,
# implement, route, or alter the frozen ILA hardware.

set step6_script_dir [file dirname [file normalize [info script]]]
set step6_routed_dcp [file join \
  $step6_script_dir build step5 edgescope_ila_reference_routed.dcp]
set step6_output_dir [file join $step6_script_dir build step6]
set step6_mmi [file join \
  $step6_output_dir edgescope_ila_reference_runtime.mmi]

proc step6_export_fail {message} {
  error "VIVADO_ILA_STEP_6_MEMORY_MAP_FAILED: $message"
}

if {[version -short] ne {2024.2}} {
  step6_export_fail \
    "Vivado 2024.2 is required; running [version -short]"
}
if {![file isfile $step6_routed_dcp]} {
  step6_export_fail "Step-5 routed checkpoint is missing: $step6_routed_dcp"
}

file mkdir $step6_output_dir
open_checkpoint $step6_routed_dcp

write_mem_info -force $step6_mmi
if {![file isfile $step6_mmi] || [file size $step6_mmi] == 0} {
  step6_export_fail "Vivado did not create a non-empty MMI file"
}

set step6_mmi_handle [open $step6_mmi r]
set step6_mmi_text [read $step6_mmi_handle]
close $step6_mmi_handle

foreach step6_required_text {
  {base_soc_i/microblaze_riscv_0}
  {Begin="0"}
  {End="131071"}
} {
  if {[string first $step6_required_text $step6_mmi_text] < 0} {
    step6_export_fail \
      "MMI is missing required mapping text '$step6_required_text'"
  }
}

puts "VIVADO_ILA_STEP_6_MEMORY_MAP: PASS"
puts "Routed checkpoint: $step6_routed_dcp"
puts "Runtime MMI: $step6_mmi"
close_design
