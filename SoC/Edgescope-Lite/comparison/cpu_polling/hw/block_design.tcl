# CPU Polling comparison overlay for the frozen common Base SoC.
#
# Vivado 2024.2 usage:
#   vivado -mode batch -source comparison/cpu_polling/hw/block_design.tcl
#
# Optional environment overrides:
#   CPU_POLL_BASE_TCL       common Base SoC Tcl
#   CPU_POLL_AXI_MASTER     MicroBlaze V AXI master interface path
#   CPU_POLL_PROBE_PIN      common generator probe_test_o pin path
#   CPU_POLL_ADDR_SPACE     MicroBlaze V data address-space path

set overlay_script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $overlay_script_dir ../../..]]

proc env_or_default {name default_value} {
    if {[info exists ::env($name)] && $::env($name) ne ""} {
        return $::env($name)
    }
    return $default_value
}

set base_tcl [env_or_default CPU_POLL_BASE_TCL \
    [file join $repo_root comparison common base_soc.tcl]]

if {![file exists $base_tcl]} {
    error "Frozen common Base SoC is missing: $base_tcl. Do not produce official resource results until it is distributed."
}

source $base_tcl

# The frozen Base script is also usable standalone and closes its project.
# Reopen the generated project/design when it was sourced as an overlay base.
if {[llength [get_projects -quiet]] == 0} {
    set base_project [file join [file dirname $base_tcl] build base_soc \
        edgescope_comparison_base.xpr]
    if {![file exists $base_project]} {
        error "The common Base did not generate the expected project: $base_project"
    }
    open_project $base_project
}

if {[llength [get_bd_designs -quiet]] == 0} {
    set base_bd_candidates [get_files -quiet */base_soc.bd]
    if {[llength $base_bd_candidates] != 1} {
        error "Expected exactly one generated base_soc.bd, found: $base_bd_candidates"
    }
    open_bd_design [lindex $base_bd_candidates 0]
}
if {[llength [get_bd_designs -quiet]] != 1} {
    error "Expected exactly one open block design after loading the common Base."
}
current_bd_design [lindex [get_bd_designs] 0]

if {[llength [get_bd_cells -quiet axi_gpio_test_ctrl]] != 1} {
    error "The common Base must contain axi_gpio_test_ctrl."
}
if {[llength [get_bd_cells -quiet axi_gpio_probe]] != 0} {
    error "axi_gpio_probe already exists; refusing to create a duplicate."
}
if {[llength [get_bd_cells -quiet test_pattern_generator_0]] != 0} {
    error "test_pattern_generator_0 already exists; refusing to create a duplicate."
}

set cpu_candidates [concat \
    [get_bd_cells -quiet -hier -filter {VLNV =~ "*:microblaze_riscv:*"}] \
    [get_bd_cells -quiet -hier -filter {VLNV =~ "*:microblaze_v:*"}]]
set cpu_candidates [lsort -unique $cpu_candidates]
if {[llength $cpu_candidates] != 1} {
    error "Expected exactly one MicroBlaze V instance, found: $cpu_candidates"
}
set cpu_cell [lindex $cpu_candidates 0]

set axi_interconnect [get_bd_cells -quiet microblaze_riscv_0_axi_periph]
if {[llength $axi_interconnect] != 1} {
    error "The frozen common AXI interconnect was not found."
}

set generator_source [file join $repo_root comparison common rtl \
    test_pattern_generator.sv]
if {![file exists $generator_source]} {
    error "Frozen common Generator is missing: $generator_source"
}
set previous_dir [pwd]
cd [file dirname $generator_source]
add_files -norecurse [file tail $generator_source]
cd $previous_dir
set_property FILE_TYPE {Verilog} \
    [get_files [file tail $generator_source]]
update_compile_order -fileset sources_1

set generator [create_bd_cell -type module \
    -reference test_pattern_generator test_pattern_generator_0]
connect_bd_net [get_bd_pins clk_wiz/clk_out1] \
    [get_bd_pins $generator/clk_i]
connect_bd_net [get_bd_pins rst_clk_wiz_100M/peripheral_aresetn] \
    [get_bd_pins $generator/reset_n_i]
connect_bd_net [get_bd_pins axi_gpio_test_ctrl/gpio_io_o] \
    [get_bd_pins $generator/control_i]
connect_bd_net [get_bd_pins $generator/status_o] \
    [get_bd_pins axi_gpio_test_ctrl/gpio2_io_i]

set probe_pin [get_bd_pins $generator/probe_test_o]

set gpio [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 \
    axi_gpio_probe]
set_property -dict [list \
    CONFIG.C_GPIO_WIDTH {8} \
    CONFIG.C_ALL_INPUTS {1} \
    CONFIG.C_IS_DUAL {0} \
    CONFIG.C_INTERRUPT_PRESENT {0}] $gpio

connect_bd_net [get_bd_pins $probe_pin] [get_bd_pins $gpio/gpio_io_i]

set_property CONFIG.NUM_MI {5} $axi_interconnect
connect_bd_intf_net \
    [get_bd_intf_pins $axi_interconnect/M04_AXI] \
    [get_bd_intf_pins $gpio/S_AXI]
connect_bd_net [get_bd_pins clk_wiz/clk_out1] \
    [get_bd_pins $axi_interconnect/M04_ACLK] \
    [get_bd_pins $gpio/s_axi_aclk]
connect_bd_net [get_bd_pins rst_clk_wiz_100M/peripheral_aresetn] \
    [get_bd_pins $axi_interconnect/M04_ARESETN] \
    [get_bd_pins $gpio/s_axi_aresetn]

set address_space [env_or_default CPU_POLL_ADDR_SPACE "$cpu_cell/Data"]
if {[llength [get_bd_addr_spaces -quiet $address_space]] != 1} {
    error "Invalid CPU_POLL_ADDR_SPACE: $address_space"
}

assign_bd_address -offset 0x40010000 -range 0x00010000 \
    -target_address_space [get_bd_addr_spaces $address_space] \
    [get_bd_addr_segs $gpio/S_AXI/Reg] -force

validate_bd_design
save_bd_design

set constraints_file [file join $overlay_script_dir constraints.xdc]
if {[llength [get_files -quiet $constraints_file]] == 0} {
    set previous_dir [pwd]
    cd [file dirname $constraints_file]
    add_files -fileset constrs_1 -norecurse [file tail $constraints_file]
    cd $previous_dir
}

set base_bd_file [get_files -quiet */base_soc.bd]
generate_target all $base_bd_file
set wrapper_file [make_wrapper -files $base_bd_file -top]
if {[llength [get_files -quiet [file tail $wrapper_file]]] == 0} {
    set previous_dir [pwd]
    cd [file dirname $wrapper_file]
    add_files -norecurse [file tail $wrapper_file]
    cd $previous_dir
}
update_compile_order -fileset sources_1

set gpio_width [get_property CONFIG.C_GPIO_WIDTH $gpio]
set gpio_inputs [get_property CONFIG.C_ALL_INPUTS $gpio]
if {$gpio_width ne "8" || $gpio_inputs ne "1"} {
    error "Frozen AXI GPIO settings were not preserved."
}

puts "CPU polling overlay complete: axi_gpio_probe @ 0x40010000, 64 KiB"
puts "Generator: $generator_source"
puts "Project: [get_property DIRECTORY [current_project]]"
