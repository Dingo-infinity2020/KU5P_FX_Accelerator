# Defines explicit SRAM/VIO actions only. Never writes external clock devices.
source -notrace [file join [file dirname [info script]] lesson05d_hardware.tcl]
if {![info exists ::lesson05g_expected_build]} {set ::lesson05g_expected_build 465805e2}
proc lesson05g_snapshot {} {
    set vio [get_hw_vios];if {[llength $vio]!=1} {error "Expected one CPLL VIO"}
    set probes [get_hw_probes -of_objects $vio -filter {TYPE==vio_input}]
    set_property INPUT_VALUE_RADIX HEX $probes
    set t0 [clock clicks -microseconds];refresh_hw_vio $vio;set t1 [clock clicks -microseconds]
    set values {0 0 0 0 0};set masks {0 0 0 0 0}
    foreach p $probes {
        set port [get_property PROBE_PORT $p];set first [get_property PROBE_PORT_BITS $p];set width [get_property PROBE_PORT_BIT_COUNT $p]
        if {$port ni {0 1 2 3 4} || ![string is integer -strict $first]} {error "Unknown fragment layout"}
        set mask [expr {((1<<$width)-1)<<$first}]
        if {[lindex $masks $port]&$mask} {error "Overlapping fragments"}
        set raw [get_property INPUT_VALUE $p];if {![regexp {^[0-9a-fA-F]+$} $raw]} {error "Unknown VIO value"}
        lset masks $port [expr {[lindex $masks $port]|$mask}]
        lset values $port [expr {[lindex $values $port]|([expr 0x$raw]<<$first)}]
    }
    foreach port {0 1 2 3 4} width {32 96 32 32 128} {if {[lindex $masks $port]!=((1<<$width)-1)} {error "Incomplete VIO port $port"}}
    if {[format %08x [lindex $values 0]] ne $::lesson05g_expected_build} {error "Wrong CPLL firmware identity"}
    set outputs [get_hw_probes -of_objects $vio -filter {TYPE==vio_output}]
    if {[llength $outputs]!=1 || [get_property WIDTH $outputs]!=1} {error "Unexpected reset interface"}
    refresh_hw_vio -update_output_values $vio
    scan [get_property OUTPUT_VALUE $outputs] %x manual
    return [dict create build $::lesson05g_expected_build observation [lesson05d_hex_vector [lindex $values 1] 96] \
        heartbeat [format %08x [lindex $values 2]] refcounter [format %08x [lindex $values 3]] \
        events [lesson05d_hex_vector [lindex $values 4] 128] manual $manual t0 $t0 t1 $t1]
}
proc lesson05g_reset {out value} {
    if {$value ni {0 1}} {error "Reset must be 0/1"}
    set before [lesson05g_snapshot]
    set vio [get_hw_vios];set p [get_hw_probes -of_objects $vio -filter {TYPE==vio_output}]
    set_property OUTPUT_VALUE $value $p;commit_hw_vio $vio
    refresh_hw_vio -update_output_values $vio
    scan [get_property OUTPUT_VALUE $p] %x actual
    if {$actual!=$value} {error "Reset readback differs"}
    file mkdir [file join $out hardware]
    set path [file join $out hardware reset_actions.tsv];set exists [file exists $path]
    set h [open $path a]
    if {!$exists} {puts $h "unix\trequested\treadback\tbefore_observation_hex\tbefore_events_hex"}
    puts $h "[clock seconds]\t$value\t$actual\t[dict get $before observation]\t[dict get $before events]";close $h
    puts "CPLL_MANUAL_RESET=$actual"
}
proc lesson05g_program {out {build_id 465805e2}} {
    set out [file normalize $out]
    set prefixes [dict create 465805e2 lesson05g_cpll_top 465805e3 lesson05h_cpll_source_top]
    if {![dict exists $prefixes $build_id]} {error "Unknown CPLL test identity"}
    set prefix [dict get $prefixes $build_id]
    foreach n [list verification.json ${prefix}.bit ${prefix}.ltx] {
        if {![file exists [file join $out $n]]} {error "Missing accepted CPLL artifact: $n"}
    }
    set device [lesson05d_attach]
    set_property PARAM.FREQUENCY 6000000 [current_hw_target]
    if {[get_property PARAM.FREQUENCY [current_hw_target]]!=6000000} {error "JTAG must be6MHz"}
    set_property PROGRAM.FILE [file join $out ${prefix}.bit] $device
    set_property PROBES.FILE [file join $out ${prefix}.ltx] $device
    program_hw_devices $device;refresh_hw_device $device
    if {![get_property {REGISTER.CONFIG_STATUS.BIT[14]_DONE_PIN} $device]} {error "DONE low"}
    if {[llength [get_hw_ilas]]!=1 || [llength [get_hw_vios]]!=1} {error "Unexpected debug cores"}
    set ::lesson05g_expected_build $build_id
    set state [lesson05g_snapshot]
    if {[dict get $state manual]!=1} {error "Manual reset must initialize high"}
    file mkdir [file join $out hardware]
    set h [open [file join $out hardware programmed.txt] w]
    puts $h "configuration=JTAG_SRAM\nbuild=$build_id\nprogrammed_unix=[clock seconds]\njtag_hz=6000000";close $h
    lesson05g_reset $out 1
    puts CPLL_BOARD_SRAM_PROGRAMMED
}
proc lesson05g_read {out label {samples 12} {interval_ms 150}} {
    if {![regexp {^[A-Za-z0-9_-]+$} $label] || $samples<2 || $samples>100 || $interval_ms<10 || $interval_ms>500} {error "Invalid capture parameters"}
    set path [file join $out hardware ${label}.tsv]
    if {[file exists $path]} {error "Preserve previous capture $label"}
    file mkdir [file dirname $path];set h [open $path w]
    puts $h "index\tbuild_hex\tobservation_hex\theartbeat_hex\trefcounter_hex\tevents_hex\tmanual_reset\trefresh_start_us\trefresh_end_us"
    for {set i 0} {$i<$samples} {incr i} {
        set s [lesson05g_snapshot]
        puts $h "$i\t[dict get $s build]\t[dict get $s observation]\t[dict get $s heartbeat]\t[dict get $s refcounter]\t[dict get $s events]\t[dict get $s manual]\t[dict get $s t0]\t[dict get $s t1]";flush $h
        puts "CPLL_SAMPLE index=$i flags=[string range [dict get $s observation] 16 23] ref=[dict get $s refcounter] events=[dict get $s events]"
        after $interval_ms
    };close $h
}
proc lesson05g_arm_release_trace {} {
    set ila [get_hw_ilas];if {[llength $ila]!=1} {error "Expected one CPLL ILA"}
    set found 0
    foreach p [get_hw_probes -of_objects $ila] {
        set width [get_property WIDTH $p];set pattern [string repeat X $width]
        set first [get_property PROBE_PORT_BITS $p]
        if {![string is integer -strict $first]} {error "Unknown ILA layout"}
        if {[get_property PROBE_PORT $p]==0 && $first<=11 && $first+$width>11} {
            set offset [expr {$width-1-(11-$first)}];set pattern [string replace $pattern $offset $offset 0];incr found
        }
        set_property TRIGGER_COMPARE_VALUE [format {eq%d'b%s} $width $pattern] $p
    }
    if {$found!=1} {error "Cannot identify reset_all trigger bit"}
    set_property CONTROL.DATA_DEPTH 8192 $ila;set_property CONTROL.TRIGGER_POSITION 0 $ila
    run_hw_ila $ila
}
proc lesson05g_save_trace {out label {immediate 0}} {
    if {![regexp {^[A-Za-z0-9_-]+$} $label]} {error "Invalid trace label"}
    foreach ext {csv ila} {if {[file exists [file join $out hardware ${label}.$ext]]} {error "Preserve prior trace"}}
    set ila [get_hw_ilas]
    if {$immediate} {run_hw_ila -trigger_now $ila}
    wait_on_hw_ila -timeout 10 $ila
    set data [upload_hw_ila_data $ila]
    set h [open [file join $out hardware ${label}_layout.tsv] w];puts $h "object\tname\tport\tfirst_bit\twidth"
    foreach p [get_hw_probes -of_objects $ila] {
        puts $h "$p\t[get_property NAME $p]\t[get_property PROBE_PORT $p]\t[get_property PROBE_PORT_BITS $p]\t[get_property PROBE_PORT_BIT_COUNT $p]"
        set_property DISPLAY_RADIX HEX $p
    };close $h
    write_hw_ila_data -csv_file [file join $out hardware ${label}.csv] $data
    write_hw_ila_data [file join $out hardware ${label}.ila] $data
    puts "CPLL_TRACE_SAVED=$label"
}
