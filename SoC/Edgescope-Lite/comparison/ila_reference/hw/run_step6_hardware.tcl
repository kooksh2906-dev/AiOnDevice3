# EdgeScope-Lite Vivado ILA reference: Step 6 hardware execution.
#
# Vivado 2024.2 batch entry point.  This script deliberately never uses
# run_hw_ila -trigger_now.  The external UART/runtime helper owns Generator
# START; this script owns BIT/LTX pairing, ILA arming, and capture evidence.
#
# Actions:
#   dry_run
#   pair
#   arm    <rising|falling|pattern|no_trigger>
#   collect <rising|falling|pattern|no_trigger>
#   capture <rising|falling|pattern|no_trigger>

namespace eval ::edgescope_step6 {
  variable expected_part_prefix {xc7a35t}
  variable expected_ila_cell {base_soc_i/ila_reference_0}
  variable expected_probe_name {probe0}
  variable expected_probe_net \
    {base_soc_i/test_pattern_generator_gpio_adapter_0_probe_test_o}
  variable expected_depth 1024
  variable expected_probe_width 8
  variable expected_probe_port 0
  variable expected_comparators 1
  variable profiles {rising falling pattern no_trigger}
  variable generator_test_ids [dict create \
    rising 1 \
    falling 2 \
    pattern 3 \
    no_trigger 5]

  variable script_dir [file dirname [file normalize [info script]]]
  variable reference_dir [file dirname $script_dir]
  variable manifest_path \
    [file join $reference_dir build step6 runtime_pair_manifest.rpt]
  variable checksum_index_path \
    [file join $reference_dir build step6 SHA256SUMS]
  variable bit_path \
    [file join $reference_dir build step6 edgescope_ila_reference_runtime.bit]
  variable ltx_path \
    [file join $reference_dir build step6 debug_nets.ltx]
  variable trigger_script \
    [file join $script_dir ila_trigger_control.tcl]
  variable results_dir \
    [file join $reference_dir results step6]

  variable connected 0
  variable target_open 0
  variable selected_target {}
  variable selected_device {}
  variable input_metadata {}
  variable ltx_metadata {}
}

proc ::edgescope_step6::fail {message} {
  error "EDGESCOPE_STEP6_ERROR: $message"
}

proc ::edgescope_step6::checkpoint {fields} {
  set parts {EDGESCOPE_CHECKPOINT}
  dict for {key value} $fields {
    set clean [string map [list "|" "/" "\n" " " "\r" " "] $value]
    lappend parts "${key}=${clean}"
  }
  puts [join $parts {|}]
  flush stdout
}

proc ::edgescope_step6::assert_equal {label actual expected} {
  if {![string equal -nocase [string trim $actual] [string trim $expected]]} {
    fail "$label: actual='$actual', expected='$expected'"
  }
  puts "ASSERT PASS: $label = $actual"
}

proc ::edgescope_step6::assert_integer_equal {label actual expected} {
  if {![string is integer -strict $actual] || $actual != $expected} {
    fail "$label: actual='$actual', expected='$expected'"
  }
  puts "ASSERT PASS: $label = $actual"
}

proc ::edgescope_step6::require_file {label path} {
  if {![file exists $path] || ![file isfile $path]} {
    fail "$label does not exist: $path"
  }
  if {[file size $path] <= 0} {
    fail "$label is empty: $path"
  }
}

proc ::edgescope_step6::read_text {path} {
  set channel [open $path r]
  try {
    return [read $channel]
  } finally {
    close $channel
  }
}

proc ::edgescope_step6::sha256_file {path} {
  # GNU sha256sum is orders of magnitude faster than the pure-Tcl fallback
  # for a multi-megabyte bitstream.  Tcl list argument handling preserves
  # paths containing spaces and does not invoke a shell.
  if {![catch {exec sha256sum -- $path} output] &&
      [regexp {^([0-9A-Fa-f]{64})[[:space:]]} $output unused digest]} {
    return [string tolower $digest]
  }
  if {[catch {package require sha256} package_error]} {
    fail \
      "Neither sha256sum nor Vivado Tcl SHA-256 is available: $package_error"
  }
  return [string tolower [::sha2::sha256 -hex -filename $path]]
}

proc ::edgescope_step6::manifest_hash {label text} {
  set escaped [regsub -all {([][(){}.*+?^$\\|])} $label {\\\1}]
  set expression "(?m)^${escaped}\\s*:\\s*([0-9A-Fa-f]{64})\\s*$"
  if {![regexp -- $expression $text unused digest]} {
    fail "Missing unique SHA-256 field '$label' in Step-6 runtime manifest"
  }
  return [string tolower $digest]
}

proc ::edgescope_step6::manifest_value {label text} {
  set escaped [regsub -all {([][(){}.*+?^$\\|])} $label {\\\1}]
  set expression "(?m)^${escaped}\\s*:\\s*(.*?)\\s*$"
  if {![regexp -- $expression $text unused value]} {
    fail "Missing field '$label' in Step-6 runtime manifest"
  }
  return [string trim $value]
}

proc ::edgescope_step6::checksum_index_hash {relative_path text} {
  set matches {}
  foreach line [split $text "\n"] {
    if {[regexp {^([0-9A-Fa-f]{64})[[:space:]]+(.+?)[[:space:]]*$} \
          $line unused digest path] &&
        [string equal $path $relative_path]} {
      lappend matches [string tolower $digest]
    }
  }
  if {[llength $matches] != 1} {
    fail \
      "Expected exactly one checksum-index entry for '$relative_path', found [llength $matches]"
  }
  return [lindex $matches 0]
}

proc ::edgescope_step6::count_regex {expression text} {
  return [regexp -all -- $expression $text]
}

proc ::edgescope_step6::parse_ltx {path} {
  variable expected_ila_cell
  variable expected_probe_name
  variable expected_probe_net
  variable expected_probe_width
  variable expected_probe_port

  set text [read_text $path]

  set ila_count [count_regex {"type"[[:space:]]*:[[:space:]]*"ILA_V3"} $text]
  if {$ila_count != 1} {
    fail "LTX must contain exactly one ILA_V3 core, found $ila_count"
  }

  if {![regexp -- \
      {"type"[[:space:]]*:[[:space:]]*"ILA_V3"[[:space:]]*,[[:space:]]*"name"[[:space:]]*:[[:space:]]*"([^"]+)"[[:space:]]*,[[:space:]]*"spec"[[:space:]]*:[[:space:]]*"([^"]+)"[[:space:]]*,[[:space:]]*"ipName"[[:space:]]*:[[:space:]]*"([^"]+)"} \
      $text unused ila_name ila_spec ila_ip_name]} {
    fail "Could not parse ILA name/spec/ipName from LTX"
  }
  assert_equal {LTX ILA instance} $ila_name $expected_ila_cell
  assert_equal {LTX ILA spec} $ila_spec {labtools_ila_v6}
  assert_equal {LTX ILA IP name} $ila_ip_name {ila}

  set uuid_count [count_regex \
    {"uuid"[[:space:]]*:[[:space:]]*"[0-9A-Fa-f]{32}"} $text]
  if {$uuid_count != 1} {
    fail "LTX must contain exactly one 32-hex ILA UUID, found $uuid_count"
  }
  if {![regexp \
      {"uuid"[[:space:]]*:[[:space:]]*"([0-9A-Fa-f]{32})"} \
      $text unused uuid]} {
    fail "Could not parse ILA UUID from LTX"
  }
  set uuid [string toupper $uuid]

  set pin_count [count_regex \
    {"type"[[:space:]]*:[[:space:]]*"DATA_TRIGGER"} $text]
  if {$pin_count != 1} {
    fail "LTX must contain exactly one DATA_TRIGGER pin, found $pin_count"
  }
  if {![regexp -- \
      {"name"[[:space:]]*:[[:space:]]*"([^"]+)"[[:space:]]*,[[:space:]]*"id"[[:space:]]*:[[:space:]]*([0-9]+)[[:space:]]*,[[:space:]]*"type"[[:space:]]*:[[:space:]]*"DATA_TRIGGER"[[:space:]]*,[[:space:]]*"direction"[[:space:]]*:[[:space:]]*"([^"]+)"[[:space:]]*,[[:space:]]*"isVector"[[:space:]]*:[[:space:]]*(true|false)[[:space:]]*,[[:space:]]*"leftIndex"[[:space:]]*:[[:space:]]*([0-9]+)[[:space:]]*,[[:space:]]*"rightIndex"[[:space:]]*:[[:space:]]*([0-9]+)[[:space:]]*,[[:space:]]*"portIndex"[[:space:]]*:[[:space:]]*([0-9]+)} \
      $text unused pin_name pin_id direction is_vector left_index right_index \
      port_index]} {
    fail "Could not parse the single LTX DATA_TRIGGER pin metadata"
  }

  assert_equal {LTX probe name} $pin_name $expected_probe_name
  assert_integer_equal {LTX probe ID} $pin_id 0
  assert_equal {LTX probe direction} $direction {IN}
  assert_equal {LTX probe vector flag} $is_vector {true}
  assert_integer_equal {LTX probe port} $port_index $expected_probe_port
  set width [expr {abs($right_index - $left_index) + 1}]
  assert_integer_equal {LTX probe width} $width $expected_probe_width

  set expected_net_count [count_regex \
    "\"name\"\\s*:\\s*\"${expected_probe_net}\"" $text]
  if {$expected_net_count != 1} {
    fail \
      "LTX must contain the exact expected probe bus once, found $expected_net_count"
  }

  return [dict create \
    ila_instance $ila_name \
    ila_uuid $uuid \
    ila_spec $ila_spec \
    probe_name $pin_name \
    probe_id $pin_id \
    probe_direction $direction \
    probe_left_index $left_index \
    probe_right_index $right_index \
    probe_width $width \
    probe_port $port_index \
    probe_net $expected_probe_net]
}

proc ::edgescope_step6::validate_inputs {} {
  variable manifest_path
  variable checksum_index_path
  variable bit_path
  variable ltx_path
  variable trigger_script
  variable input_metadata
  variable ltx_metadata

  require_file {Step-6 runtime-pair manifest} $manifest_path
  require_file {Step-6 runtime checksum index} $checksum_index_path
  require_file {Step-6 runtime bitstream} $bit_path
  require_file {Step-6 runtime LTX} $ltx_path
  require_file {Step-4 hardware trigger script} $trigger_script

  set manifest [read_text $manifest_path]
  set checksum_index [read_text $checksum_index_path]
  set expected_bit_hash [manifest_hash {Runtime BIT SHA-256} $manifest]
  set expected_ltx_hash [manifest_hash {Runtime LTX SHA-256} $manifest]
  set base_bit_hash [manifest_hash {Base BIT SHA-256} $manifest]
  if {[string equal -nocase $base_bit_hash $expected_bit_hash]} {
    fail \
      "Runtime BIT hash equals the Step-5 bootloop BIT hash; functional capture requires the UART runtime BIT"
  }
  assert_equal {Runtime command path} \
    [manifest_value {Runtime command path} $manifest] {UART RUN}
  assert_equal {Runtime BIT differs from bootloop} \
    [manifest_value {Runtime BIT differs} $manifest] {PASS}
  assert_equal {Runtime LTX unchanged from routed design} \
    [manifest_value {LTX unchanged from Step 5} $manifest] {PASS}
  set indexed_bit_hash \
    [checksum_index_hash {edgescope_ila_reference_runtime.bit} \
      $checksum_index]
  set indexed_ltx_hash \
    [checksum_index_hash {debug_nets.ltx} $checksum_index]
  set actual_bit_hash [sha256_file $bit_path]
  set actual_ltx_hash [sha256_file $ltx_path]

  assert_equal {BIT hash manifest/index} $expected_bit_hash $indexed_bit_hash
  assert_equal {LTX hash manifest/index} $expected_ltx_hash $indexed_ltx_hash
  assert_equal {BIT hash on disk} $actual_bit_hash $expected_bit_hash
  assert_equal {LTX hash on disk} $actual_ltx_hash $expected_ltx_hash

  set ltx_metadata [parse_ltx $ltx_path]
  set input_metadata [dict create \
    pair_kind STEP6_UART_RUNTIME \
    bit_path [file normalize $bit_path] \
    bit_sha256 $actual_bit_hash \
    ltx_path [file normalize $ltx_path] \
    ltx_sha256 $actual_ltx_hash]
  return [dict merge $input_metadata $ltx_metadata]
}

proc ::edgescope_step6::write_report {path fields} {
  file mkdir [file dirname $path]
  set temporary "${path}.[pid].tmp"
  set channel [open $temporary w]
  try {
    puts $channel {# EdgeScope-Lite Step 6 machine-readable evidence}
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

proc ::edgescope_step6::read_report {path} {
  require_file {Step-6 state/report} $path
  set values {}
  foreach line [split [read_text $path] "\n"] {
    set trimmed [string trim $line]
    if {$trimmed eq {} || [string index $trimmed 0] eq {#}} {
      continue
    }
    if {![regexp {^([^=]+)=(.*)$} $trimmed unused key value]} {
      fail "Malformed machine-readable report line in '$path': $line"
    }
    dict set values [string trim $key] [string trim $value]
  }
  return $values
}

proc ::edgescope_step6::property_exists {object property_name} {
  return [expr {
    [lsearch -exact [list_property $object] $property_name] >= 0
  }]
}

proc ::edgescope_step6::required_property {object property_name label} {
  if {![property_exists $object $property_name]} {
    fail "$label property '$property_name' is not exposed by '$object'"
  }
  return [get_property $property_name $object]
}

proc ::edgescope_step6::object_name {object} {
  if {[property_exists $object NAME]} {
    return [get_property NAME $object]
  }
  return $object
}

proc ::edgescope_step6::cleanup_hardware {} {
  variable connected
  variable target_open
  if {$target_open} {
    catch {close_hw_target}
    set target_open 0
  }
  if {$connected} {
    catch {disconnect_hw_server}
    set connected 0
  }
  catch {close_hw_manager}
}

proc ::edgescope_step6::connect_single_device {} {
  variable expected_part_prefix
  variable connected
  variable target_open
  variable selected_target
  variable selected_device

  set server_url {localhost:3121}
  if {[info exists ::env(EDGESCOPE_HW_SERVER_URL)] &&
      [string trim $::env(EDGESCOPE_HW_SERVER_URL)] ne {}} {
    set server_url [string trim $::env(EDGESCOPE_HW_SERVER_URL)]
  }

  open_hw_manager
  if {[catch {connect_hw_server -url $server_url} connect_error]} {
    fail "Cannot connect to hw_server '$server_url': $connect_error"
  }
  set connected 1

  set targets [get_hw_targets -quiet]
  if {[info exists ::env(EDGESCOPE_HW_TARGET_PATTERN)] &&
      [string trim $::env(EDGESCOPE_HW_TARGET_PATTERN)] ne {}} {
    set target_pattern [string trim $::env(EDGESCOPE_HW_TARGET_PATTERN)]
    set matched_targets {}
    foreach target $targets {
      if {[string match $target_pattern [object_name $target]]} {
        lappend matched_targets $target
      }
    }

    if {[llength $matched_targets] != 1} {
      set target_names {}
      foreach target $targets {
        lappend target_names [object_name $target]
      }
      fail "Target selector '$target_pattern' matched [llength $matched_targets] target(s); inventory=$target_names"
    }

    set targets $matched_targets
    puts "ASSERT PASS: explicit hardware target selector = [object_name [lindex $targets 0]]"
  }

  if {[llength $targets] != 1} {
    set names {}
    foreach target $targets {
      lappend names [object_name $target]
    }
    fail \
      "Expected exactly one hardware target, found [llength $targets]: $names"
  }
  set selected_target [lindex $targets 0]
  current_hw_target $selected_target
  if {[catch {open_hw_target $selected_target} target_error]} {
    fail "Cannot open hardware target '$selected_target': $target_error"
  }
  set target_open 1

  set candidates {}
  set inventory {}
  foreach device [get_hw_devices -quiet] {
    set name [object_name $device]
    set part {}
    if {[property_exists $device PART]} {
      set part [get_property PART $device]
    }
    lappend inventory "${name}(PART=${part})"
    set identity [string tolower "${name} ${part}"]
    if {[string first [string tolower $expected_part_prefix] $identity] >= 0 &&
        [property_exists $device PROGRAM.FILE]} {
      lappend candidates $device
    }
  }
  if {[llength $candidates] != 1} {
    fail \
      "Expected exactly one programmable ${expected_part_prefix} device, found [llength $candidates]; inventory=$inventory"
  }
  set selected_device [lindex $candidates 0]
  current_hw_device $selected_device

  return [dict create \
    server_url $server_url \
    target [object_name $selected_target] \
    device [object_name $selected_device] \
    part [expr {
      [property_exists $selected_device PART] ?
        [get_property PART $selected_device] : {NOT_EXPOSED}
    }]]
}

proc ::edgescope_step6::set_pair_files {device} {
  variable bit_path
  variable ltx_path

  set_property PROGRAM.FILE [file normalize $bit_path] $device
  set_property PROBES.FILE [file normalize $ltx_path] $device
  if {[property_exists $device FULL_PROBES.FILE]} {
    set_property FULL_PROBES.FILE [file normalize $ltx_path] $device
  }

  set program_readback [required_property $device PROGRAM.FILE {PROGRAM.FILE}]
  set probes_readback [required_property $device PROBES.FILE {PROBES.FILE}]
  assert_equal {PROGRAM.FILE readback} \
    [file normalize $program_readback] [file normalize $bit_path]
  assert_equal {PROBES.FILE readback} \
    [file normalize $probes_readback] [file normalize $ltx_path]

  set readback [dict create \
    program_file [file normalize $program_readback] \
    probes_file [file normalize $probes_readback]]
  if {[property_exists $device FULL_PROBES.FILE]} {
    set full_probes [get_property FULL_PROBES.FILE $device]
    assert_equal {FULL_PROBES.FILE readback} \
      [file normalize $full_probes] [file normalize $ltx_path]
    dict set readback full_probes_file [file normalize $full_probes]
  } else {
    dict set readback full_probes_file {NOT_EXPOSED}
  }
  return $readback
}

proc ::edgescope_step6::configuration_status {device} {
  set fields {}
  set saw_done_or_eos 0
  foreach property_name [lsort [list_property $device]] {
    set upper [string toupper $property_name]
    set is_config_status [string match {*CONFIG_STATUS*} $upper]
    set is_done_status [expr {
      ([string match {REGISTER.CONFIG_STATUS.*DONE*} $upper] ||
       [string match {STATUS.*DONE*} $upper]) &&
      ![string match {*DISABLE*} $upper]
    }]
    set is_eos_status [expr {
      ([string match {REGISTER.CONFIG_STATUS.*EOS*} $upper] ||
       [string match {STATUS.*EOS*} $upper]) &&
      ![string match {*DISABLE*} $upper]
    }]
    if {$is_config_status || $is_done_status || $is_eos_status} {
      if {[catch {get_property $property_name $device} value]} {
        continue
      }
      dict set fields "device_property.${property_name}" $value
      if {$is_done_status || $is_eos_status} {
        set saw_done_or_eos 1
        set normalized [string tolower [string trim $value]]
        if {$normalized in {0 false no low}} {
          fail "Configuration status '$property_name' is not asserted: $value"
        }
      }
    }
  }
  if {!$saw_done_or_eos} {
    dict set fields device_property.DONE_EOS {NOT_EXPOSED}
  }
  return $fields
}

proc ::edgescope_step6::normalize_uuid {uuid} {
  set normalized [string map \
    [list "-" "" "_" "" ":" "" " " "" "{" "" "}" ""] \
    [string trim $uuid]]
  regsub -nocase {^0x} $normalized {} normalized
  return [string toupper $normalized]
}

proc ::edgescope_step6::single_ila_and_probe {device} {
  variable expected_ila_cell
  variable expected_depth
  variable expected_probe_width
  variable expected_probe_port
  variable expected_comparators
  variable ltx_metadata

  set ilas [get_hw_ilas -of_objects $device]
  if {[llength $ilas] != 1} {
    fail \
      "Expected exactly one hardware ILA after BIT/LTX refresh, found [llength $ilas]"
  }
  set ila [lindex $ilas 0]
  current_hw_ila $ila

  set cell_name [required_property $ila CELL_NAME {ILA instance}]
  assert_equal {Hardware ILA instance} \
    [string trimleft $cell_name /] $expected_ila_cell
  assert_integer_equal {Hardware ILA maximum depth} \
    [required_property $ila STATIC.MAX_DATA_DEPTH {ILA depth}] $expected_depth

  set uuid_property {}
  foreach candidate {CORE_UUID UUID HW_CORE_UUID} {
    if {[property_exists $ila $candidate]} {
      set uuid_property $candidate
      break
    }
  }
  set uuid_readback {NOT_EXPOSED}
  if {$uuid_property ne {}} {
    set uuid_readback [normalize_uuid [get_property $uuid_property $ila]]
    assert_equal {Hardware/LTX ILA UUID} \
      $uuid_readback [dict get $ltx_metadata ila_uuid]
  }

  set ila_probes {}
  foreach probe [get_hw_probes -of_objects $ila] {
    if {[string equal -nocase [get_property TYPE $probe] ila]} {
      lappend ila_probes $probe
    }
  }
  if {[llength $ila_probes] != 1} {
    fail \
      "Expected exactly one ILA data/trigger probe, found [llength $ila_probes]"
  }
  set probe [lindex $ila_probes 0]
  assert_integer_equal {Hardware probe port} \
    [required_property $probe PROBE_PORT {Probe port}] $expected_probe_port
  assert_integer_equal {Hardware probe width} \
    [required_property $probe PROBE_PORT_BIT_COUNT {Probe width}] \
    $expected_probe_width
  assert_integer_equal {Hardware probe comparator count} \
    [required_property $probe COMPARATOR_COUNT {Probe comparator count}] \
    $expected_comparators

  return [dict create \
    ila $ila \
    probe $probe \
    ila_cell $cell_name \
    ila_uuid $uuid_readback \
    ila_uuid_property [expr {
      $uuid_property eq {} ? {NOT_EXPOSED} : $uuid_property
    }] \
    probe_object [object_name $probe]]
}

proc ::edgescope_step6::program_and_pair {} {
  variable selected_device

  set connection [connect_single_device]
  set file_readback [set_pair_files $selected_device]
  puts \
    "Programming [object_name $selected_device] with fixed Step-6 runtime BIT/LTX..."
  program_hw_devices $selected_device
  refresh_hw_device -update_hw_probes true $selected_device
  set file_readback [set_pair_files $selected_device]
  set status [configuration_status $selected_device]
  set core [single_ila_and_probe $selected_device]

  return [dict merge $connection $file_readback $status $core]
}

proc ::edgescope_step6::connect_existing_pair {} {
  variable selected_device

  set connection [connect_single_device]
  set file_readback [set_pair_files $selected_device]
  refresh_hw_device -update_hw_probes true $selected_device
  set file_readback [set_pair_files $selected_device]
  set status [configuration_status $selected_device]
  set core [single_ila_and_probe $selected_device]
  return [dict merge $connection $file_readback $status $core]
}

proc ::edgescope_step6::source_trigger_control {} {
  variable trigger_script
  source $trigger_script
  if {[llength [info commands ::edgescope_ila::configure]] != 1} {
    fail "Step-4 trigger control did not define edgescope_ila::configure"
  }
}

proc ::edgescope_step6::normalize_profile {profile} {
  variable profiles
  set normalized [string tolower [string trim $profile]]
  if {$normalized ni $profiles} {
    fail \
      "Unsupported profile '$profile'; use rising, falling, pattern, or no_trigger"
  }
  return $normalized
}

proc ::edgescope_step6::generator_test_id {profile} {
  variable generator_test_ids
  set normalized [normalize_profile $profile]
  return [dict get $generator_test_ids $normalized]
}

proc ::edgescope_step6::normalized_core_status {ila} {
  set status [required_property $ila STATUS.CORE_STATUS {ILA core status}]
  return [string toupper [string map [list " " "_" "-" "_"] \
    [string trim $status]]]
}

proc ::edgescope_step6::wait_for_waiting {ila timeout_ms} {
  set deadline [expr {[clock milliseconds] + $timeout_ms}]
  set last {}
  while {[clock milliseconds] <= $deadline} {
    set last [normalized_core_status $ila]
    if {[string match {*WAITING*TRIGGER*} $last]} {
      return $last
    }
    if {$last ni {PRE_TRIGGER PRETRIGGER ARMED}} {
      if {$last in {FULL CAPTURED DONE POST_TRIGGER POSTTRIGGER}} {
        fail \
          "ILA left the arm sequence before WAITING_FOR_TRIGGER (status=$last); do not start Generator before checkpoint"
      }
    }
    after 25
    update
  }
  fail \
    "ILA did not reach WAITING_FOR_TRIGGER within ${timeout_ms} ms; last status=$last"
}

proc ::edgescope_step6::arm_state_path {} {
  variable results_dir
  return [file join $results_dir armed_session.rpt]
}

proc ::edgescope_step6::no_trigger_ack_path {} {
  variable results_dir
  return [file join $results_dir no_trigger_runtime_ack.rpt]
}

proc ::edgescope_step6::create_arm_state {profile pair ila} {
  variable input_metadata

  set session_token "[clock milliseconds]-[pid]"
  set state [dict merge $input_metadata [dict create \
    STEP 6 \
    ACTION arm \
    PROFILE $profile \
    SESSION_TOKEN $session_token \
    ARM_EPOCH_MS [clock milliseconds] \
    ILA_CELL [dict get $pair ila_cell] \
    ILA_UUID [dict get $pair ila_uuid] \
    CORE_STATUS [normalized_core_status $ila] \
    RESULT ARMED_WAITING_FOR_TRIGGER]]
  write_report [arm_state_path] $state
  return $state
}

proc ::edgescope_step6::arm_profile {profile pair} {
  set normalized [normalize_profile $profile]
  source_trigger_control
  set configured [::edgescope_ila::configure $normalized]
  set ila [dict get $configured ila]

  if {$normalized eq {no_trigger}} {
    set ack_path [no_trigger_ack_path]
    if {[file exists $ack_path]} {
      file delete -force $ack_path
    }
  }

  # Functional captures must come only from the configured comparator event.
  run_hw_ila $ila
  set status [wait_for_waiting $ila 5000]
  set state [create_arm_state $normalized $pair $ila]
  set fields [dict create \
    state WAITING_FOR_TRIGGER \
    profile $normalized \
    uart_command "RUN [generator_test_id $normalized]" \
    generator_test_id [generator_test_id $normalized] \
    session [dict get $state SESSION_TOKEN] \
    core_status $status]
  if {$normalized eq {no_trigger}} {
    dict set fields ack_file [file normalize [no_trigger_ack_path]]
    dict set fields ack_protocol \
      {SESSION_TOKEN,PROFILE,STATE=GENERATOR_STARTED,START_EPOCH_MS}
  }
  checkpoint $fields
  return [dict create configured $configured state $state]
}

proc ::edgescope_step6::profile_readbacks {pair} {
  variable profiles
  variable results_dir
  variable input_metadata
  variable ltx_metadata

  source_trigger_control
  set fields [dict merge $input_metadata $ltx_metadata [dict create \
    STEP 6 \
    ACTION pair \
    RESULT PASS \
    TARGET [dict get $pair target] \
    DEVICE [dict get $pair device] \
    PART [dict get $pair part] \
    PROGRAM_FILE [dict get $pair program_file] \
    PROBES_FILE [dict get $pair probes_file] \
    FULL_PROBES_FILE [dict get $pair full_probes_file] \
    ILA_CELL [dict get $pair ila_cell] \
    ILA_UUID [dict get $pair ila_uuid] \
    ILA_UUID_PROPERTY [dict get $pair ila_uuid_property]]]

  dict for {key value} $pair {
    if {[string match {device_property.*} $key]} {
      dict set fields $key $value
    }
  }

  foreach profile $profiles {
    set configured [::edgescope_ila::configure $profile]
    set ila [dict get $configured ila]
    set probe [dict get $configured probe]
    dict set fields "PROFILE.${profile}.RESULT" PASS
    dict set fields "PROFILE.${profile}.DATA_DEPTH" \
      [get_property CONTROL.DATA_DEPTH $ila]
    dict set fields "PROFILE.${profile}.TRIGGER_POSITION" \
      [get_property CONTROL.TRIGGER_POSITION $ila]
    dict set fields "PROFILE.${profile}.TRIGGER_COMPARE_VALUE" \
      [get_property TRIGGER_COMPARE_VALUE $probe]
  }

  write_report [file join $results_dir pair_readback.rpt] $fields
  checkpoint [dict create state PAIR_READBACK_PASS profiles [join $profiles ,]]
}

proc ::edgescope_step6::load_matching_arm_state {profile} {
  variable input_metadata

  set state [read_report [arm_state_path]]
  foreach key {PROFILE SESSION_TOKEN ARM_EPOCH_MS bit_sha256 ltx_sha256} {
    if {![dict exists $state $key]} {
      fail "Armed-session report is missing '$key'"
    }
  }
  assert_equal {Armed profile} [dict get $state PROFILE] $profile
  assert_equal {Armed BIT hash} \
    [dict get $state bit_sha256] [dict get $input_metadata bit_sha256]
  assert_equal {Armed LTX hash} \
    [dict get $state ltx_sha256] [dict get $input_metadata ltx_sha256]
  if {![string is wideinteger -strict [dict get $state ARM_EPOCH_MS]]} {
    fail "Armed-session ARM_EPOCH_MS is not an integer"
  }
  return $state
}

proc ::edgescope_step6::write_capture_data {
    profile pair ila state {wait_for_completion 1}} {
  variable results_dir
  variable input_metadata

  if {$wait_for_completion} {
    if {[catch {wait_on_hw_ila -timeout 0.01 $ila} wait_error]} {
      set status [normalized_core_status $ila]
      fail \
        "ILA data is not complete for '$profile' (status=$status): $wait_error; partial data was not uploaded"
    }
  }

  set data [upload_hw_ila_data $ila]
  if {[llength $data] != 1} {
    fail "Expected exactly one uploaded ILA data object, found [llength $data]"
  }
  set base [file join $results_dir $profile]
  set ila_file "${base}.ila"
  set csv_file "${base}_raw.csv"
  write_hw_ila_data -force $ila_file $data
  write_hw_ila_data -force -csv_file $csv_file $data
  require_file {Captured ILA file} $ila_file
  require_file {Captured raw CSV file} $csv_file

  set fields [dict merge $input_metadata [dict create \
    STEP 6 \
    ACTION collect \
    PROFILE $profile \
    SESSION_TOKEN [dict get $state SESSION_TOKEN] \
    RESULT CAPTURE_COMPLETE \
    PARTIAL_CAPTURE 0 \
    ILA_FILE [file normalize $ila_file] \
    ILA_FILE_SHA256 [sha256_file $ila_file] \
    RAW_CSV_FILE [file normalize $csv_file] \
    RAW_CSV_SHA256 [sha256_file $csv_file] \
    TARGET [dict get $pair target] \
    DEVICE [dict get $pair device] \
    ILA_CELL [dict get $pair ila_cell]]]
  write_report [file join $results_dir "capture_${profile}.rpt"] $fields
  checkpoint [dict create \
    state CAPTURE_COMPLETE \
    profile $profile \
    ila_file [file normalize $ila_file] \
    csv_file [file normalize $csv_file]]
}

proc ::edgescope_step6::read_valid_no_trigger_ack {state} {
  set ack_path [no_trigger_ack_path]
  set ack [read_report $ack_path]
  foreach key {SESSION_TOKEN PROFILE STATE START_EPOCH_MS} {
    if {![dict exists $ack $key]} {
      fail "No-trigger runtime acknowledgment is missing '$key': $ack_path"
    }
  }
  assert_equal {No-trigger acknowledgment session} \
    [dict get $ack SESSION_TOKEN] [dict get $state SESSION_TOKEN]
  assert_equal {No-trigger acknowledgment profile} \
    [dict get $ack PROFILE] {no_trigger}
  assert_equal {No-trigger acknowledgment state} \
    [dict get $ack STATE] {GENERATOR_STARTED}
  set start_ms [dict get $ack START_EPOCH_MS]
  if {![string is wideinteger -strict $start_ms]} {
    fail "No-trigger acknowledgment START_EPOCH_MS is not an integer"
  }
  if {$start_ms < [dict get $state ARM_EPOCH_MS]} {
    fail \
      "No-trigger runtime acknowledgment predates the current arm session"
  }
  if {$start_ms > [expr {[clock milliseconds] + 1000}]} {
    fail "No-trigger runtime acknowledgment start time is in the future"
  }
  return $ack
}

proc ::edgescope_step6::wait_for_no_trigger_ack {state timeout_ms} {
  set deadline [expr {[clock milliseconds] + $timeout_ms}]
  set last_error {acknowledgment file not created}
  while {[clock milliseconds] <= $deadline} {
    if {[file exists [no_trigger_ack_path]]} {
      if {![catch {read_valid_no_trigger_ack $state} ack options]} {
        return $ack
      }
      set last_error $ack
    }
    after 25
    update
  }
  fail \
    "Timed out after ${timeout_ms} ms waiting for external UART runtime acknowledgment: $last_error"
}

proc ::edgescope_step6::verify_no_trigger_window {pair ila state ack} {
  variable results_dir
  variable input_metadata

  set start_ms [dict get $ack START_EPOCH_MS]
  set required_end [expr {$start_ms + 100}]
  while {[clock milliseconds] < $required_end} {
    set status [normalized_core_status $ila]
    if {![string match {*WAITING*TRIGGER*} $status]} {
      fail \
        "Forbidden trigger occurred during the 100-ms no-trigger window (status=$status)"
    }
    after 10
    update
  }
  set status [normalized_core_status $ila]
  if {![string match {*WAITING*TRIGGER*} $status]} {
    fail \
      "ILA was not waiting after the 100-ms no-trigger window (status=$status)"
  }

  set observed_ms [expr {[clock milliseconds] - $start_ms}]
  set fields [dict merge $input_metadata [dict create \
    STEP 6 \
    ACTION no_trigger_check \
    PROFILE no_trigger \
    SESSION_TOKEN [dict get $state SESSION_TOKEN] \
    RESULT PASS_NO_TRIGGER_100MS \
    REQUIRED_DURATION_MS 100 \
    OBSERVED_DURATION_MS $observed_ms \
    CORE_STATUS $status \
    PARTIAL_CAPTURE_SAVED 0 \
    PARTIAL_UPLOAD_ATTEMPTED 0 \
    CAPTURE_ARTIFACT NONE_BY_DESIGN \
    RUNTIME_ACK_FILE [file normalize [no_trigger_ack_path]] \
    TARGET [dict get $pair target] \
    DEVICE [dict get $pair device] \
    ILA_CELL [dict get $pair ila_cell]]]
  write_report [file join $results_dir no_trigger_100ms.rpt] $fields
  checkpoint [dict create \
    state NO_TRIGGER_100MS_PASS \
    profile no_trigger \
    duration_ms $observed_ms \
    partial_capture_saved 0]
}

proc ::edgescope_step6::capture_wait_timeout_minutes {} {
  set timeout 2.0
  if {[info exists ::env(EDGESCOPE_CAPTURE_TIMEOUT_MIN)] &&
      [string trim $::env(EDGESCOPE_CAPTURE_TIMEOUT_MIN)] ne {}} {
    set timeout [string trim $::env(EDGESCOPE_CAPTURE_TIMEOUT_MIN)]
  }
  if {![string is double -strict $timeout] || $timeout <= 0} {
    fail "EDGESCOPE_CAPTURE_TIMEOUT_MIN must be a positive number"
  }
  return $timeout
}

proc ::edgescope_step6::ack_wait_timeout_ms {} {
  set timeout 120000
  if {[info exists ::env(EDGESCOPE_NO_TRIGGER_ACK_TIMEOUT_MS)] &&
      [string trim $::env(EDGESCOPE_NO_TRIGGER_ACK_TIMEOUT_MS)] ne {}} {
    set timeout [string trim $::env(EDGESCOPE_NO_TRIGGER_ACK_TIMEOUT_MS)]
  }
  if {![string is integer -strict $timeout] || $timeout < 100} {
    fail \
      "EDGESCOPE_NO_TRIGGER_ACK_TIMEOUT_MS must be an integer of at least 100"
  }
  return $timeout
}

proc ::edgescope_step6::action_dry_run {} {
  variable results_dir
  variable input_metadata
  variable ltx_metadata

  set metadata [validate_inputs]
  write_report [file join $results_dir dry_run.rpt] \
    [dict merge $metadata [dict create \
      STEP 6 \
      ACTION dry_run \
      RESULT PASS \
      HARDWARE_TOUCHED 0]]
  checkpoint [dict create state DRY_RUN_PASS hardware_touched 0]
}

proc ::edgescope_step6::action_pair {} {
  variable results_dir
  variable input_metadata
  variable ltx_metadata

  validate_inputs
  set pair [program_and_pair]
  profile_readbacks $pair
}

proc ::edgescope_step6::action_arm {profile} {
  validate_inputs
  set normalized [normalize_profile $profile]
  set pair [program_and_pair]
  arm_profile $normalized $pair
}

proc ::edgescope_step6::action_collect {profile} {
  validate_inputs
  set normalized [normalize_profile $profile]
  set state [load_matching_arm_state $normalized]
  set pair [connect_existing_pair]
  set ila [dict get $pair ila]

  if {$normalized eq {no_trigger}} {
    set ack [read_valid_no_trigger_ack $state]
    set elapsed [expr {[clock milliseconds] - [dict get $ack START_EPOCH_MS]}]
    if {$elapsed < 100} {
      fail \
        "Only ${elapsed} ms elapsed after Generator START; wait until at least 100 ms"
    }
    verify_no_trigger_window $pair $ila $state $ack
  } else {
    write_capture_data $normalized $pair $ila $state
  }
}

proc ::edgescope_step6::action_capture {profile} {
  validate_inputs
  set normalized [normalize_profile $profile]
  set pair [program_and_pair]
  set armed [arm_profile $normalized $pair]
  set configured [dict get $armed configured]
  set state [dict get $armed state]
  set ila [dict get $configured ila]

  if {$normalized eq {no_trigger}} {
    set ack [wait_for_no_trigger_ack $state [ack_wait_timeout_ms]]
    verify_no_trigger_window $pair $ila $state $ack
    return
  }

  set timeout [capture_wait_timeout_minutes]
  if {[catch {wait_on_hw_ila -timeout $timeout $ila} wait_error]} {
    variable results_dir
    write_report [file join $results_dir "capture_${normalized}_failed.rpt"] \
      [dict create \
        STEP 6 \
        ACTION capture \
        PROFILE $normalized \
        SESSION_TOKEN [dict get $state SESSION_TOKEN] \
        RESULT TIMEOUT_OR_CAPTURE_ERROR \
        PARTIAL_CAPTURE_SAVED 0 \
        ERROR $wait_error \
        CORE_STATUS [normalized_core_status $ila]]
    fail \
      "Capture '$normalized' did not complete within $timeout minutes: $wait_error; partial data was not uploaded"
  }
  write_capture_data $normalized $pair $ila $state 0
}

proc ::edgescope_step6::usage {} {
  return [join {
    {Usage: run_step6_hardware.tcl <action> [profile]}
    {  dry_run}
    {  pair}
    {  arm     rising|falling|pattern|no_trigger}
    {  collect rising|falling|pattern|no_trigger}
    {  capture rising|falling|pattern|no_trigger}
    {}
    {Never uses trigger_now.  For arm/capture, wait for the machine-readable}
    {WAITING_FOR_TRIGGER checkpoint before starting the Generator via UART.}
  } "\n"]
}

proc ::edgescope_step6::main {arguments} {
  if {[llength $arguments] < 1} {
    fail [usage]
  }
  set action [string tolower [lindex $arguments 0]]
  switch -- $action {
    dry_run {
      if {[llength $arguments] != 1} {
        fail [usage]
      }
      action_dry_run
    }
    pair {
      if {[llength $arguments] != 1} {
        fail [usage]
      }
      action_pair
    }
    arm {
      if {[llength $arguments] != 2} {
        fail [usage]
      }
      action_arm [lindex $arguments 1]
    }
    collect {
      if {[llength $arguments] != 2} {
        fail [usage]
      }
      action_collect [lindex $arguments 1]
    }
    capture {
      if {[llength $arguments] != 2} {
        fail [usage]
      }
      action_capture [lindex $arguments 1]
    }
    default {
      fail "Unknown action '$action'\n[usage]"
    }
  }
}

if {![info exists ::edgescope_step6_library_only] ||
    !$::edgescope_step6_library_only} {
  set step6_exit_code 0
  if {[catch {::edgescope_step6::main $argv} step6_error step6_options]} {
    set step6_exit_code 1
    puts stderr $step6_error
    if {[dict exists $step6_options -errorinfo]} {
      puts stderr [dict get $step6_options -errorinfo]
    }
  } else {
    puts {EDGESCOPE_STEP6: PASS}
  }
  ::edgescope_step6::cleanup_hardware
  exit $step6_exit_code
}
