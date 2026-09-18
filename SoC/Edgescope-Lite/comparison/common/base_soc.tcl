# EdgeScope-Lite comparison base SoC
#
# Step 1 creates only the hardware shared by all comparison designs.
# The common test-pattern generator is connected in Step 2, and Vivado ILA
# is added in Step 3.  Do not add analyzer-specific hardware to this file.
#
# Run:
#   vivado -mode batch -source comparison/common/base_soc.tcl

set required_vivado_version {2024.2}
set required_part {xc7a35tcpg236-1}
set required_board_part {digilentinc.com:basys3:part0:1.2}

set script_dir [file dirname [file normalize [info script]]]
set build_dir [file join $script_dir build base_soc]
set generated_dir [file join $script_dir generated]
set project_name {edgescope_comparison_base}
set design_name {base_soc}

proc fail {message} {
  error "BASE_SOC_ASSERTION_FAILED: $message"
}

proc assert_equal {label actual expected} {
  if {![string equal -nocase $actual $expected]} {
    fail "$label: actual='$actual', expected='$expected'"
  }
  puts "ASSERT PASS: $label = $actual"
}

proc append_unique_path {list_name candidate} {
  upvar 1 $list_name paths
  if {$candidate eq ""} {
    return
  }
  if {[catch {set normalized [file normalize $candidate]}]} {
    return
  }
  if {[lsearch -exact $paths $normalized] < 0} {
    lappend paths $normalized
  }
}

proc count_ip {vlnv} {
  set count 0
  foreach cell [get_bd_cells -hier -quiet] {
    if {[get_property -quiet VLNV $cell] eq $vlnv} {
      incr count
    }
  }
  return $count
}

proc assert_ip_count {vlnv expected} {
  assert_equal "IP count $vlnv" [count_ip $vlnv] $expected
}

proc assert_same_net {reference_pin checked_pin} {
  set reference_net [get_bd_nets -quiet -of_objects \
    [get_bd_pins $reference_pin]]
  set checked_net [get_bd_nets -quiet -of_objects \
    [get_bd_pins $checked_pin]]
  if {$reference_net eq "" || $checked_net eq ""} {
    fail "Unconnected pin while comparing $reference_pin and $checked_pin"
  }
  assert_equal "net $checked_pin" $checked_net $reference_net
}

proc assert_address {segment_path expected_offset expected_range} {
  set segment [get_bd_addr_segs -quiet $segment_path]
  if {[llength $segment] != 1} {
    fail "Address segment '$segment_path' was not found exactly once"
  }
  assert_equal "$segment_path offset" \
    [get_property OFFSET $segment] $expected_offset
  assert_equal "$segment_path range" \
    [get_property RANGE $segment] $expected_range
}

set current_vivado_version [version -short]
if {[string first $required_vivado_version $current_vivado_version] != 0} {
  fail "Vivado $required_vivado_version is required; running $current_vivado_version"
}

# The submitted XSA used Basys 3 board metadata 1.1.  The installed 1.2 board
# definition targets the same xc7a35tcpg236-1 device and the same sys_clock,
# reset, and usb_uart interfaces.
set board_part_matches [get_board_parts -quiet $required_board_part]
if {[llength $board_part_matches] > 1} {
  fail "Required board part $required_board_part resolved more than once: $board_part_matches"
}

if {[llength $board_part_matches] == 1} {
  puts "BASE_SOC_BOARD: using already registered board part $required_board_part"
} else {
  set original_board_repos [get_param board.repoPaths]
  set board_repo_candidates {}

  if {[info exists ::env(EDGESCOPE_BOARD_REPO)] &&
      $::env(EDGESCOPE_BOARD_REPO) ne ""} {
    set override_repo [file normalize $::env(EDGESCOPE_BOARD_REPO)]
    if {![file isdirectory $override_repo]} {
      fail "EDGESCOPE_BOARD_REPO is not a directory: $override_repo"
    }
    append_unique_path board_repo_candidates $override_repo
  } else {
    set user_home_dir [file normalize ~]
    append_unique_path board_repo_candidates [file join \
      $user_home_dir .Xilinx Vivado $required_vivado_version xhub \
      board_store xilinx_board_store XilinxBoardStore Vivado \
      $required_vivado_version boards]
    append_unique_path board_repo_candidates [file join \
      $user_home_dir .Xilinx xhub board_store xilinx_board_store \
      XilinxBoardStore Vivado $required_vivado_version boards]

    set vivado_install_roots {}
    if {[info exists ::env(XILINX_VIVADO)] &&
        $::env(XILINX_VIVADO) ne ""} {
      append_unique_path vivado_install_roots $::env(XILINX_VIVADO)
    }
    append_unique_path vivado_install_roots \
      [file join / tools Xilinx Vivado $required_vivado_version]
    append_unique_path vivado_install_roots \
      [file join / opt Xilinx Vivado $required_vivado_version]
    append_unique_path vivado_install_roots \
      [file join C:/ Xilinx Vivado $required_vivado_version]

    if {![catch {set executable_dir \
        [file dirname [file normalize [info nameofexecutable]]]}]} {
      for {set level 0} {$level < 6} {incr level} {
        append_unique_path vivado_install_roots $executable_dir
        set parent_dir [file dirname $executable_dir]
        if {$parent_dir eq $executable_dir} {
          break
        }
        set executable_dir $parent_dir
      }
    }

    foreach install_root $vivado_install_roots {
      append_unique_path board_repo_candidates [file join \
        $install_root data xhub boards XilinxBoardStore boards]
      append_unique_path board_repo_candidates [file join \
        $install_root data boards board_files]
    }
  }

  set selected_board_repo {}
  set searched_board_repos {}
  foreach board_repo $board_repo_candidates {
    lappend searched_board_repos $board_repo
    if {![file isdirectory $board_repo]} {
      continue
    }

    set configured_board_repos [list $board_repo]
    foreach existing_repo $original_board_repos {
      append_unique_path configured_board_repos $existing_repo
    }
    set_param board.repoPaths $configured_board_repos

    set board_part_matches [get_board_parts -quiet $required_board_part]
    if {[llength $board_part_matches] > 1} {
      fail "Required board part $required_board_part resolved more than once: $board_part_matches"
    }
    if {[llength $board_part_matches] == 1} {
      set selected_board_repo $board_repo
      break
    }
  }

  if {$selected_board_repo eq ""} {
    set_param board.repoPaths $original_board_repos
    fail "Required board part $required_board_part was not found; searched: [join $searched_board_repos {, }]. Set EDGESCOPE_BOARD_REPO to its board-files directory"
  }
  puts "BASE_SOC_BOARD_REPO: $selected_board_repo"
}

if {[llength [get_board_parts -quiet $required_board_part]] != 1} {
  fail "Required board part $required_board_part is not installed"
}

file mkdir $build_dir
file mkdir $generated_dir

create_project -force $project_name $build_dir -part $required_part
set_property BOARD_PART $required_board_part [current_project]
set_property TARGET_LANGUAGE {Verilog} [current_project]
set_property SIMULATOR_LANGUAGE {Mixed} [current_project]

create_bd_design $design_name

set sys_clock [create_bd_port -dir I -type clk \
  -freq_hz 100000000 sys_clock]
set reset [create_bd_port -dir I -type rst reset]
set_property CONFIG.POLARITY {ACTIVE_HIGH} $reset

set clk_wiz [create_bd_cell -type ip \
  -vlnv xilinx.com:ip:clk_wiz:6.0 clk_wiz]
set_property -dict [list \
  CONFIG.PRIMITIVE {MMCM} \
  CONFIG.PRIM_SOURCE {Single_ended_clock_capable_pin} \
  CONFIG.PRIM_IN_FREQ {100.000} \
  CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {100.000} \
  CONFIG.USE_RESET {true} \
  CONFIG.RESET_TYPE {ACTIVE_HIGH} \
  CONFIG.CLK_IN1_BOARD_INTERFACE {sys_clock} \
  CONFIG.RESET_BOARD_INTERFACE {reset} \
  CONFIG.USE_BOARD_FLOW {true} \
] $clk_wiz

connect_bd_net $sys_clock [get_bd_pins clk_wiz/clk_in1]
connect_bd_net $reset [get_bd_pins clk_wiz/reset]

set microblaze [create_bd_cell -type ip \
  -vlnv xilinx.com:ip:microblaze_riscv:1.0 microblaze_riscv_0]

apply_bd_automation \
  -rule xilinx.com:bd_rule:microblaze_riscv \
  -config {
    axi_intc {1}
    axi_periph {Enabled}
    cache {None}
    clk {/clk_wiz/clk_out1 (100 MHz)}
    debug_module {Debug Enabled}
    ecc {None}
    local_mem {128KB}
    preset {None}
  } \
  $microblaze

set reset_controller [get_bd_cells rst_clk_wiz_100M]
set_property -dict [list \
  CONFIG.RESET_BOARD_INTERFACE {reset} \
  CONFIG.USE_BOARD_FLOW {true} \
] $reset_controller

set axi_interconnect [get_bd_cells microblaze_riscv_0_axi_periph]
set_property CONFIG.NUM_MI {4} $axi_interconnect

set uart [create_bd_cell -type ip \
  -vlnv xilinx.com:ip:axi_uartlite:2.0 axi_uartlite_0]
set_property -dict [list \
  CONFIG.C_BAUDRATE {9600} \
  CONFIG.C_DATA_BITS {8} \
  CONFIG.C_USE_PARITY {0} \
] $uart

set timer [create_bd_cell -type ip \
  -vlnv xilinx.com:ip:axi_timer:2.0 axi_timer_0]
set_property -dict [list \
  CONFIG.COUNT_WIDTH {32} \
  CONFIG.enable_timer2 {1} \
] $timer

set test_gpio [create_bd_cell -type ip \
  -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_test_ctrl]
set_property -dict [list \
  CONFIG.C_IS_DUAL {1} \
  CONFIG.C_GPIO_WIDTH {26} \
  CONFIG.C_ALL_OUTPUTS {1} \
  CONFIG.C_GPIO2_WIDTH {2} \
  CONFIG.C_ALL_INPUTS_2 {1} \
  CONFIG.C_INTERRUPT_PRESENT {0} \
] $test_gpio

connect_bd_intf_net \
  [get_bd_intf_pins microblaze_riscv_0_axi_periph/M01_AXI] \
  [get_bd_intf_pins axi_uartlite_0/S_AXI]
connect_bd_intf_net \
  [get_bd_intf_pins microblaze_riscv_0_axi_periph/M02_AXI] \
  [get_bd_intf_pins axi_timer_0/S_AXI]
connect_bd_intf_net \
  [get_bd_intf_pins microblaze_riscv_0_axi_periph/M03_AXI] \
  [get_bd_intf_pins axi_gpio_test_ctrl/S_AXI]

set common_clock_pin [get_bd_pins clk_wiz/clk_out1]
connect_bd_net $common_clock_pin \
  [get_bd_pins microblaze_riscv_0_axi_periph/M01_ACLK] \
  [get_bd_pins microblaze_riscv_0_axi_periph/M02_ACLK] \
  [get_bd_pins microblaze_riscv_0_axi_periph/M03_ACLK] \
  [get_bd_pins axi_uartlite_0/s_axi_aclk] \
  [get_bd_pins axi_timer_0/s_axi_aclk] \
  [get_bd_pins axi_gpio_test_ctrl/s_axi_aclk]

set common_resetn_pin \
  [get_bd_pins rst_clk_wiz_100M/peripheral_aresetn]
connect_bd_net $common_resetn_pin \
  [get_bd_pins microblaze_riscv_0_axi_periph/M01_ARESETN] \
  [get_bd_pins microblaze_riscv_0_axi_periph/M02_ARESETN] \
  [get_bd_pins microblaze_riscv_0_axi_periph/M03_ARESETN] \
  [get_bd_pins axi_uartlite_0/s_axi_aresetn] \
  [get_bd_pins axi_timer_0/s_axi_aresetn] \
  [get_bd_pins axi_gpio_test_ctrl/s_axi_aresetn]

make_bd_intf_pins_external [get_bd_intf_pins axi_uartlite_0/UART]
set uart_port [get_bd_intf_ports UART_0]
set_property name {usb_uart} $uart_port
set_property -dict [list \
  CONFIG.UARTLITE_BOARD_INTERFACE {usb_uart} \
  CONFIG.USE_BOARD_FLOW {true} \
] $uart

set interrupt_concat [get_bd_cells microblaze_riscv_0_xlconcat]
set_property CONFIG.NUM_PORTS {2} $interrupt_concat
connect_bd_net \
  [get_bd_pins axi_uartlite_0/interrupt] \
  [get_bd_pins microblaze_riscv_0_xlconcat/In0]
connect_bd_net \
  [get_bd_pins axi_timer_0/interrupt] \
  [get_bd_pins microblaze_riscv_0_xlconcat/In1]

set data_space [get_bd_addr_spaces microblaze_riscv_0/Data]
set instruction_space \
  [get_bd_addr_spaces microblaze_riscv_0/Instruction]

assign_bd_address -offset 0x00000000 -range 0x00020000 \
  -target_address_space $data_space \
  [get_bd_addr_segs \
    microblaze_riscv_0_local_memory/dlmb_bram_if_cntlr/SLMB/Mem] \
  -force
assign_bd_address -offset 0x40000000 -range 0x00010000 \
  -target_address_space $data_space \
  [get_bd_addr_segs axi_gpio_test_ctrl/S_AXI/Reg] \
  -force
assign_bd_address -offset 0x40600000 -range 0x00010000 \
  -target_address_space $data_space \
  [get_bd_addr_segs axi_uartlite_0/S_AXI/Reg] \
  -force
assign_bd_address -offset 0x41200000 -range 0x00010000 \
  -target_address_space $data_space \
  [get_bd_addr_segs microblaze_riscv_0_axi_intc/S_AXI/Reg] \
  -force
assign_bd_address -offset 0x41C00000 -range 0x00010000 \
  -target_address_space $data_space \
  [get_bd_addr_segs axi_timer_0/S_AXI/Reg] \
  -force
assign_bd_address -offset 0x00000000 -range 0x00020000 \
  -target_address_space $instruction_space \
  [get_bd_addr_segs \
    microblaze_riscv_0_local_memory/ilmb_bram_if_cntlr/SLMB/Mem] \
  -force

if {[catch {validate_bd_design} validation_error]} {
  fail "validate_bd_design failed: $validation_error"
}
puts "VALIDATE DESIGN: PASS"

# Configuration assertions
assert_equal {Vivado version} $current_vivado_version \
  $required_vivado_version
assert_equal {FPGA part} [get_property PART [current_project]] \
  $required_part
assert_equal {Board part} [get_property BOARD_PART [current_project]] \
  $required_board_part
assert_equal {sys_clock frequency} \
  [get_property CONFIG.FREQ_HZ [get_bd_ports sys_clock]] 100000000
assert_equal {reset polarity} \
  [get_property CONFIG.POLARITY [get_bd_ports reset]] ACTIVE_HIGH

assert_ip_count xilinx.com:ip:microblaze_riscv:1.0 1
assert_ip_count xilinx.com:ip:axi_interconnect:2.1 1
assert_ip_count xilinx.com:ip:axi_intc:4.1 1
assert_ip_count xilinx.com:ip:axi_uartlite:2.0 1
assert_ip_count xilinx.com:ip:axi_timer:2.0 1
assert_ip_count xilinx.com:ip:axi_gpio:2.0 1
assert_ip_count xilinx.com:ip:blk_mem_gen:8.4 1
assert_ip_count xilinx.com:ip:ila:6.2 0
assert_ip_count xilinx.com:ip:axi_bram_ctrl:4.1 0

foreach cell [get_bd_cells -hier -quiet] {
  set cell_vlnv [get_property -quiet VLNV $cell]
  if {[regexp -nocase \
      {(circular_trace_buffer|probe_sampler|basic_trigger_engine)} \
      $cell_vlnv]} {
    fail "Analyzer-specific IP is forbidden in the common Base: $cell"
  }
}

assert_equal {MicroBlaze D AXI} \
  [get_property CONFIG.C_D_AXI $microblaze] 1
assert_equal {MicroBlaze D LMB} \
  [get_property CONFIG.C_D_LMB $microblaze] 1
assert_equal {MicroBlaze I LMB} \
  [get_property CONFIG.C_I_LMB $microblaze] 1
assert_equal {MicroBlaze interrupt mode} \
  [get_property CONFIG.C_USE_INTERRUPT $microblaze] 2
assert_equal {MicroBlaze debug} \
  [get_property CONFIG.C_DEBUG_ENABLED $microblaze] 1
assert_equal {MicroBlaze I-cache disabled} \
  [get_property CONFIG.C_USE_ICACHE $microblaze] 0
assert_equal {MicroBlaze D-cache disabled} \
  [get_property CONFIG.C_USE_DCACHE $microblaze] 0

set local_bram \
  [get_bd_cells microblaze_riscv_0_local_memory/lmb_bram]
assert_equal {Local memory type} \
  [get_property CONFIG.Memory_Type $local_bram] True_Dual_Port_RAM
assert_equal {Local memory width} \
  [get_property CONFIG.Write_Width_A $local_bram] 32
assert_equal {Local memory depth} \
  [get_property CONFIG.Write_Depth_A $local_bram] 32768

assert_equal {UART baud rate} \
  [get_property CONFIG.C_BAUDRATE $uart] 9600
assert_equal {UART data bits} \
  [get_property CONFIG.C_DATA_BITS $uart] 8
assert_equal {UART parity disabled} \
  [get_property CONFIG.C_USE_PARITY $uart] 0
assert_equal {Timer width} \
  [get_property CONFIG.COUNT_WIDTH $timer] 32
assert_equal {Timer 2 enabled} \
  [get_property CONFIG.enable_timer2 $timer] 1
assert_equal {GPIO dual channel} \
  [get_property CONFIG.C_IS_DUAL $test_gpio] 1
assert_equal {GPIO channel 1 width} \
  [get_property CONFIG.C_GPIO_WIDTH $test_gpio] 26
assert_equal {GPIO channel 1 output} \
  [get_property CONFIG.C_ALL_OUTPUTS $test_gpio] 1
assert_equal {GPIO channel 2 width} \
  [get_property CONFIG.C_GPIO2_WIDTH $test_gpio] 2
assert_equal {GPIO channel 2 input} \
  [get_property CONFIG.C_ALL_INPUTS_2 $test_gpio] 1
assert_equal {GPIO interrupt disabled} \
  [get_property CONFIG.C_INTERRUPT_PRESENT $test_gpio] 0

assert_equal {AXI Interconnect master interfaces} \
  [get_property CONFIG.NUM_MI $axi_interconnect] 4
assert_equal {Interrupt concat inputs} \
  [get_property CONFIG.NUM_PORTS $interrupt_concat] 2
assert_equal {AXI INTC inputs} \
  [get_property CONFIG.C_NUM_INTR_INPUTS \
    [get_bd_cells microblaze_riscv_0_axi_intc]] 2

assert_address \
  microblaze_riscv_0/Data/SEG_dlmb_bram_if_cntlr_Mem \
  0x00000000 0x00020000
assert_address \
  microblaze_riscv_0/Data/SEG_axi_gpio_test_ctrl_Reg \
  0x40000000 0x00010000
assert_address \
  microblaze_riscv_0/Data/SEG_axi_uartlite_0_Reg \
  0x40600000 0x00010000
assert_address \
  microblaze_riscv_0/Data/SEG_microblaze_riscv_0_axi_intc_Reg \
  0x41200000 0x00010000
assert_address \
  microblaze_riscv_0/Data/SEG_axi_timer_0_Reg \
  0x41C00000 0x00010000
assert_address \
  microblaze_riscv_0/Instruction/SEG_ilmb_bram_if_cntlr_Mem \
  0x00000000 0x00020000
assert_equal {Data address segment count} \
  [llength [get_bd_addr_segs -of_objects $data_space]] 5
assert_equal {Instruction address segment count} \
  [llength [get_bd_addr_segs -of_objects $instruction_space]] 1

foreach clock_pin {
  microblaze_riscv_0/Clk
  microblaze_riscv_0_local_memory/LMB_Clk
  microblaze_riscv_0_axi_periph/ACLK
  microblaze_riscv_0_axi_intc/s_axi_aclk
  axi_uartlite_0/s_axi_aclk
  axi_timer_0/s_axi_aclk
  axi_gpio_test_ctrl/s_axi_aclk
} {
  assert_same_net clk_wiz/clk_out1 $clock_pin
}

foreach reset_pin {
  microblaze_riscv_0_axi_periph/ARESETN
  microblaze_riscv_0_axi_intc/s_axi_aresetn
  axi_uartlite_0/s_axi_aresetn
  axi_timer_0/s_axi_aresetn
  axi_gpio_test_ctrl/s_axi_aresetn
} {
  assert_same_net rst_clk_wiz_100M/peripheral_aresetn $reset_pin
}

assert_equal {External interface ports} \
  [lsort [get_property NAME [get_bd_intf_ports]]] {usb_uart}
assert_equal {External scalar ports} \
  [lsort [get_property NAME [get_bd_ports]]] \
  {reset sys_clock usb_uart_rxd usb_uart_txd}

save_bd_design
write_bd_tcl -force \
  [file join $generated_dir base_soc_generated.tcl]

puts "BASE_SOC_STEP_1: PASS"
puts "Project: [file join $build_dir ${project_name}.xpr]"
puts "Generated Tcl: [file join $generated_dir base_soc_generated.tcl]"
puts "Verified address map: [file join $generated_dir base_soc_address_map.rpt]"
puts "Pending Step 2: connect axi_gpio_test_ctrl to test_pattern_generator"
puts "Pending Step 3: add Vivado ILA only in the ILA reference branch"

close_project
