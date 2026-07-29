# EdgeScope-Lite Vivado ILA reference: Step 8 Pulse Stress capture.
#
# Programs the fixed Step-6 runtime BIT/LTX once, then performs the frozen
# 6-width x 10-trial matrix in one Hardware Manager session.  Every Generator
# START occurs only after the ILA reports WAITING_FOR_TRIGGER.

set step8_script_dir [file dirname [file normalize [info script]]]
set ::edgescope_step6_library_only 1
source [file join $step8_script_dir run_step6_hardware.tcl]
unset ::edgescope_step6_library_only

namespace eval ::edgescope_step8 {
  variable reference_dir [file dirname $::step8_script_dir]
  variable results_dir [file join $reference_dir results step8]
  variable raw_dir [file join $results_dir raw]
  variable ila_dir [file join $results_dir ila]
  variable trial_dir [file join $results_dir trials]
  variable uart_script \
    [file join $reference_dir host uart_runtime_control.py]
  variable widths {1 10 100 1000 10000 100000}
  variable repetitions 10
  variable capture_timeout_minutes 0.10
}

proc ::edgescope_step8::fail {message} {
  error "EDGESCOPE_STEP8_ERROR: $message"
}

proc ::edgescope_step8::write_report {path fields} {
  file mkdir [file dirname $path]
  set temporary "${path}.[pid].tmp"
  set channel [open $temporary w]
  try {
    puts $channel {# EdgeScope-Lite Step 8 machine-readable evidence}
    dict for {key value} $fields {
      set clean [string map [list "\n" "\\n" "\r" ""] $value]
      puts $channel "${key}=${clean}"
    }
  } finally {
    close $channel
  }
  file rename -force $temporary $path
  puts "EVIDENCE: [file normalize $path]"
}

proc ::edgescope_step8::runtime_run {width} {
  variable uart_script

  if {![info exists ::env(EDGESCOPE_UART_PORT)] ||
      [string trim $::env(EDGESCOPE_UART_PORT)] eq {}} {
    fail {EDGESCOPE_UART_PORT must name the Basys 3 UART port}
  }
  set uart_port [string trim $::env(EDGESCOPE_UART_PORT)]
  if {![file exists $uart_script] || ![file isfile $uart_script]} {
    fail "UART runtime helper is missing: $uart_script"
  }

  set command [list \
    /usr/bin/python3 -I -B $uart_script command \
    --port $uart_port --timeout 3 \
    RUN 6 $width]
  if {[catch {exec {*}$command} output options]} {
    set detail [string trim $output]
    if {[dict exists $options -errorinfo]} {
      append detail " | " [dict get $options -errorinfo]
    }
    fail "UART command 'RUN 6 $width' failed: $detail"
  }

  set lines {}
  foreach line [split [string trim $output] "\n"] {
    if {[string trim $line] ne {}} {
      lappend lines [string trim $line]
    }
  }
  if {[llength $lines] != 1} {
    fail "UART command returned unexpected output: $output"
  }
  set reply [lindex $lines 0]
  if {![regexp \
      {^OK RUN id=6 pulse=0x([0-9A-Fa-f]{8}) saw_busy=1 status=0x00000002$} \
      $reply unused pulse_hex]} {
    fail "UART command returned an invalid success reply: $reply"
  }
  scan $pulse_hex %x returned_width
  if {$returned_width != $width} {
    fail \
      "UART reply width mismatch: requested=$width, returned=$returned_width"
  }
  puts "STEP8_UART: width=$width reply=$reply"
  flush stdout
  return [dict create \
    port $uart_port \
    command "RUN 6 $width" \
    reply $reply]
}

proc ::edgescope_step8::capture_trial {pair width trial} {
  variable results_dir
  variable raw_dir
  variable ila_dir
  variable trial_dir
  variable capture_timeout_minutes

  ::edgescope_step6::source_trigger_control
  set previous_ila [::edgescope_ila::get_single_ila]
  reset_hw_ila -reset_compare_values true $previous_ila
  set reset_status [::edgescope_step6::normalized_core_status $previous_ila]
  if {$reset_status ne {IDLE}} {
    fail \
      "ILA did not return to IDLE before width=$width trial=$trial (status=$reset_status)"
  }
  set configured [::edgescope_ila::configure rising]
  set ila [dict get $configured ila]
  set probe [dict get $configured probe]

  run_hw_ila $ila
  set arm_status [::edgescope_step6::wait_for_waiting $ila 5000]
  set session_token [format "w%06d-r%02d" $width $trial]
  ::edgescope_step6::checkpoint [dict create \
    step 8 \
    state PULSE_WAITING_FOR_TRIGGER \
    width_cycles $width \
    width_ns [expr {$width * 10}] \
    trial $trial \
    eligible 1 \
    session $session_token \
    uart_command "RUN 6 $width" \
    core_status $arm_status]

  set uart_start_ms [clock milliseconds]
  set uart [runtime_run $width]
  set uart_end_ms [clock milliseconds]

  if {[catch \
      {wait_on_hw_ila -timeout $capture_timeout_minutes $ila} wait_error]} {
    set failure_path \
      [file join $trial_dir "${session_token}_failed.rpt"]
    write_report $failure_path [dict create \
      STEP 8 \
      ACTION pulse_stress \
      WIDTH_CYCLES $width \
      WIDTH_NS [expr {$width * 10}] \
      TRIAL $trial \
      ELIGIBLE 1 \
      SESSION_TOKEN $session_token \
      RESULT CAPTURE_TIMEOUT_OR_ERROR \
      PARTIAL_CAPTURE_SAVED 0 \
      UART_COMMAND [dict get $uart command] \
      UART_REPLY [dict get $uart reply] \
      ERROR $wait_error \
      CORE_STATUS [::edgescope_step6::normalized_core_status $ila]]
    ::edgescope_step6::checkpoint [dict create \
      step 8 \
      state PULSE_NOT_DETECTED \
      width_cycles $width \
      trial $trial \
      eligible 1 \
      session $session_token \
      partial_capture_saved 0]
    return 0
  }

  set data [upload_hw_ila_data $ila]
  if {[llength $data] != 1} {
    fail \
      "Expected one ILA data object for width=$width trial=$trial, found [llength $data]"
  }

  file mkdir $raw_dir
  file mkdir $ila_dir
  file mkdir $trial_dir
  set stem [format "pulse_w%06d_trial_%02d" $width $trial]
  set ila_path [file join $ila_dir "${stem}.ila"]
  set csv_path [file join $raw_dir "${stem}_raw.csv"]
  write_hw_ila_data -force $ila_path $data
  write_hw_ila_data -force -csv_file $csv_path $data
  ::edgescope_step6::require_file {Step-8 ILA capture} $ila_path
  ::edgescope_step6::require_file {Step-8 raw CSV capture} $csv_path

  set report [dict merge $::edgescope_step6::input_metadata [dict create \
    STEP 8 \
    ACTION pulse_stress \
    RESULT CAPTURE_COMPLETE \
    WIDTH_CYCLES $width \
    WIDTH_NS [expr {$width * 10}] \
    TRIAL $trial \
    ELIGIBLE 1 \
    SESSION_TOKEN $session_token \
    ILA_PROFILE rising \
    TRIGGER_COMPARE_VALUE [get_property TRIGGER_COMPARE_VALUE $probe] \
    DATA_DEPTH [get_property CONTROL.DATA_DEPTH $ila] \
    TRIGGER_POSITION [get_property CONTROL.TRIGGER_POSITION $ila] \
    ARM_STATUS $arm_status \
    UART_PORT [dict get $uart port] \
    UART_COMMAND [dict get $uart command] \
    UART_REPLY [dict get $uart reply] \
    UART_START_EPOCH_MS $uart_start_ms \
    UART_RESPONSE_EPOCH_MS $uart_end_ms \
    PARTIAL_CAPTURE 0 \
    ILA_FILE [file normalize $ila_path] \
    ILA_FILE_SHA256 [::edgescope_step6::sha256_file $ila_path] \
    RAW_CSV_FILE [file normalize $csv_path] \
    RAW_CSV_SHA256 [::edgescope_step6::sha256_file $csv_path] \
    TARGET [dict get $pair target] \
    DEVICE [dict get $pair device] \
    ILA_CELL [dict get $pair ila_cell]]]
  set report_path [file join $trial_dir "${stem}.rpt"]
  write_report $report_path $report

  ::edgescope_step6::checkpoint [dict create \
    step 8 \
    state PULSE_CAPTURE_COMPLETE \
    width_cycles $width \
    trial $trial \
    eligible 1 \
    session $session_token \
    csv_file [file normalize $csv_path] \
    ila_file [file normalize $ila_path]]
  return 1
}

proc ::edgescope_step8::run {} {
  variable results_dir
  variable raw_dir
  variable ila_dir
  variable trial_dir
  variable widths
  variable repetitions

  ::edgescope_step6::validate_inputs
  set pair [::edgescope_step6::program_and_pair]
  file mkdir $results_dir
  file mkdir $raw_dir
  file mkdir $ila_dir
  file mkdir $trial_dir

  set total 0
  set total_detected 0
  set summary [dict merge $::edgescope_step6::input_metadata [dict create \
    STEP 8 \
    ACTION pulse_stress \
    RESULT CAPTURE_MATRIX_COMPLETE \
    WIDTHS_CYCLES [join $widths ,] \
    REPETITIONS_PER_WIDTH $repetitions \
    EXPECTED_ELIGIBLE_TRIALS [expr {[llength $widths] * $repetitions}] \
    ILA_PROFILE rising \
    TRIGGER_COMPARE_VALUE {eq8'bXXXXXXXR} \
    DATA_DEPTH 1024 \
    TRIGGER_POSITION 512 \
    FPGA_PROGRAM_COUNT 1 \
    TARGET [dict get $pair target] \
    DEVICE [dict get $pair device] \
    ILA_CELL [dict get $pair ila_cell]]]

  foreach width $widths {
    set width_eligible 0
    set width_detected 0
    for {set trial 1} {$trial <= $repetitions} {incr trial} {
      set detected [capture_trial $pair $width $trial]
      incr total
      incr width_eligible
      if {$detected} {
        incr total_detected
        incr width_detected
      }
    }
    dict set summary "WIDTH.${width}.ELIGIBLE_TRIAL_COUNT" $width_eligible
    dict set summary "WIDTH.${width}.DETECTED_CAPTURE_COUNT" $width_detected
  }
  dict set summary TOTAL_ELIGIBLE_CAPTURE_COUNT $total
  dict set summary TOTAL_DETECTED_CAPTURE_COUNT $total_detected
  dict set summary HOST_WAVEFORM_VALIDATION PENDING
  write_report [file join $results_dir pulse_capture_manifest.rpt] $summary
  ::edgescope_step6::checkpoint [dict create \
    step 8 \
    state PULSE_CAPTURE_MATRIX_COMPLETE \
    widths [join $widths ,] \
    repetitions $repetitions \
    total_eligible $total \
    total_detected $total_detected]
}

if {![info exists ::edgescope_step8_library_only] ||
    !$::edgescope_step8_library_only} {
  set step8_exit_code 0
  if {[catch {::edgescope_step8::run} step8_error step8_options]} {
    set step8_exit_code 1
    puts stderr $step8_error
    if {[dict exists $step8_options -errorinfo]} {
      puts stderr [dict get $step8_options -errorinfo]
    }
  } else {
    puts {EDGESCOPE_STEP8_CAPTURE: COMPLETE}
  }
  ::edgescope_step6::cleanup_hardware
  exit $step8_exit_code
}
