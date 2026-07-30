# Package the Probe Sampler and Basic Trigger Engine AXI4-Lite peripherals.

set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ..]]
set build_root  [file join $project_dir build frontend_ip_package]
set ip_repo     [file join $project_dir ip_repo]

proc package_frontend_ip {project_dir build_root ip_repo name display top files} {
  set build_dir [file join $build_root $name]
  set package_dir [file join $ip_repo ${name}_1_0]
  file delete -force $build_dir
  file delete -force $package_dir

  create_project -force ${name}_package $build_dir -part xc7a35tcpg236-1
  set_property target_language Verilog [current_project]
  add_files -norecurse $files
  foreach source [get_files -quiet *.sv] {
    set_property file_type SystemVerilog $source
  }
  set_property top $top [current_fileset]
  update_compile_order -fileset sources_1

  ipx::package_project \
    -root_dir $package_dir \
    -vendor user.org \
    -library user \
    -taxonomy /UserIP \
    -import_files \
    -set_current true

  set core [ipx::current_core]
  set_property name $name $core
  set_property display_name $display $core
  set_property vendor_display_name {EdgeScope-Lite Team} $core
  set_property version {1.0} $core
  set_property supported_families {artix7 Production} $core

  ipx::infer_bus_interfaces xilinx.com:interface:aximm_rtl:1.0 $core
  ipx::infer_bus_interfaces xilinx.com:signal:clock_rtl:1.0 $core
  ipx::infer_bus_interfaces xilinx.com:signal:reset_rtl:1.0 $core

  set axi_if [ipx::get_bus_interfaces -of_objects $core s_axi]
  if {[llength $axi_if] != 1} {
    error "$name: S_AXI interface inference failed"
  }
  set_property interface_mode slave $axi_if
  set clk_if [ipx::get_bus_interfaces -of_objects $core s_axi_aclk]
  if {[llength $clk_if] != 1} {
    error "$name: clock interface inference failed"
  }
  set freq [ipx::add_bus_parameter FREQ_HZ $clk_if]
  set_property value {100000000} $freq

  ipx::create_xgui_files $core
  file delete -force [file join $package_dir xgui ${top}_v1_0.tcl]
  ipx::update_checksums $core
  if {![ipx::check_integrity -quiet $core]} {
    error "$name: packaged IP integrity check failed"
  }
  ipx::save_core $core
  puts "Packaged: user.org:user:${name}:1.0"
  close_project
}

set package_file [file join $project_dir rtl include logic_analyzer_pkg.sv]

package_frontend_ip \
  $project_dir $build_root $ip_repo \
  probe_sampler {EdgeScope Probe Sampler} probe_sampler_axi \
  [list \
    $package_file \
    [file join $project_dir rtl core probe_sampler.sv] \
    [file join $project_dir rtl bus probe_sampler_axi.sv]]

package_frontend_ip \
  $project_dir $build_root $ip_repo \
  basic_trigger_engine {EdgeScope Basic Trigger Engine} \
  basic_trigger_engine_axi \
  [list \
    $package_file \
    [file join $project_dir rtl core basic_trigger_engine.v] \
    [file join $project_dir rtl bus basic_trigger_engine_axi.sv]]

puts "Frontend AXI IP packaging: PASS"
