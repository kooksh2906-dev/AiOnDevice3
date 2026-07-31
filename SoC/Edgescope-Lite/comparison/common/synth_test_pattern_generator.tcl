# Standalone mixed-language synthesis check for the common generator.

set script_dir [file dirname [file normalize [info script]]]
set core_rtl_file [file join \
  $script_dir rtl test_pattern_generator.sv]
set adapter_rtl_file [file join \
  $script_dir rtl test_pattern_generator_gpio_adapter.v]
set build_dir [file join $script_dir build generator_synth]
set generated_dir [file join $script_dir generated]

file mkdir $build_dir
file mkdir $generated_dir

create_project -in_memory -part xc7a35tcpg236-1
read_verilog [list $adapter_rtl_file]
read_verilog -sv [list $core_rtl_file]

synth_design \
  -top test_pattern_generator_gpio_adapter \
  -part xc7a35tcpg236-1

if {[llength [get_cells -hier -quiet generator_i]] != 1} {
  error "Generator core was not preserved in the synthesized hierarchy"
}

report_utilization -file [file join \
  $generated_dir test_pattern_generator_utilization.rpt]
write_checkpoint -force [file join \
  $build_dir test_pattern_generator_synth.dcp]

puts "TEST_PATTERN_GENERATOR_SYNTHESIS: PASS"
close_project
