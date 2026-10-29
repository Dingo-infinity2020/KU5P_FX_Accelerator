# Sourcing defines procedures only. All configuration is volatile JTAG SRAM.
source -notrace [file join [file dirname [info script]] lesson05d_hardware.tcl]
proc lesson05e_gt_reset {out value} {
    if {$value ni {0 1}} {error "Reset must be 0 or 1"}
    set vio [get_hw_vios]
    set probe [get_hw_probes -of_objects $vio -filter {TYPE==vio_output}]
    if {[llength $vio]!=1 || [llength $probe]!=1 || [get_property WIDTH $probe]!=1} {error "Unexpected reset interface"}
    set_property OUTPUT_VALUE $value $probe;commit_hw_vio $vio
    refresh_hw_vio -update_output_values $vio
    scan [get_property OUTPUT_VALUE $probe] %x actual
    if {$actual!=$value} {error "Reset readback mismatch"}
    set file [file join $out hardware reset_actions.tsv]
    set exists [file exists $file];set h [open $file a]
    if {!$exists} {puts $h "unix\trequested\treadback"}
    puts $h "[clock seconds]\t$value\t$actual";close $h
    puts "GT_MANUAL_RESET=$actual"
}
proc lesson05e_gt_program {out} {
    set out [file normalize $out]
    foreach name {verification.json lesson05e_gt_top.bit lesson05e_gt_top.ltx} {
        if {![file exists [file join $out $name]]} {error "Missing accepted artifact $name"}
    }
    set device [lesson05d_attach]
    set_property PARAM.FREQUENCY 6000000 [current_hw_target]
    set_property PROGRAM.FILE [file join $out lesson05e_gt_top.bit] $device
    set_property PROBES.FILE [file join $out lesson05e_gt_top.ltx] $device
    program_hw_devices $device;refresh_hw_device $device
    if {![get_property {REGISTER.CONFIG_STATUS.BIT[14]_DONE_PIN} $device]} {error "DONE low"}
    if {[llength [get_hw_vios]]!=1 || [llength [get_hw_ilas]]!=1} {error "Unexpected diagnostic cores"}
    file mkdir [file join $out hardware]
    set h [open [file join $out hardware programmed.txt] w]
    puts $h "configuration=JTAG_SRAM\nbuild=465805e1\nprogrammed_unix=[clock seconds]\njtag_hz=[get_property PARAM.FREQUENCY [current_hw_target]]"
    close $h
    lesson05e_gt_reset $out 1
    puts GT_ISOLATION_SRAM_PROGRAMMED
}
proc lesson05e_gt_read {out label} {
    if {![regexp {^[a-zA-Z0-9_-]+$} $label]} {error "Invalid label"}
    set out [file normalize $out];file mkdir [file join $out hardware]
    set file [file join $out hardware ${label}.tsv]
    if {[file exists $file]} {error "Do not overwrite a previous capture"}
    set vio [get_hw_vios];if {[llength $vio]!=1} {error "Expected one VIO"}
    set probes [get_hw_probes -of_objects $vio -filter {TYPE==vio_input}]
    set_property INPUT_VALUE_RADIX HEX $probes
    set rows {}
    for {set i 0} {$i<12} {incr i} {
        set t0 [clock clicks -microseconds]
        refresh_hw_vio $vio
        set t1 [clock clicks -microseconds]
        set values {0 0 0};set masks {0 0 0}
        foreach probe $probes {
            set port [get_property PROBE_PORT $probe]
            set first [get_property PROBE_PORT_BITS $probe]
            set width [get_property PROBE_PORT_BIT_COUNT $probe]
            if {$port ni {0 1 2} || ![string is integer -strict $first]} {error "Unexpected input interface"}
            set mask [expr {((1<<$width)-1)<<$first}]
            if {[lindex $masks $port]&$mask} {error "Overlapping fragments"}
            set raw [get_property INPUT_VALUE $probe]
            if {![regexp {^[0-9a-fA-F]+$} $raw]} {error "Unknown diagnostic value"}
            lset masks $port [expr {[lindex $masks $port]|$mask}]
            lset values $port [expr {[lindex $values $port]|([expr 0x$raw]<<$first)}]
        }
        foreach port {0 1 2} width {32 96 32} {
            if {[lindex $masks $port]!=((1<<$width)-1)} {error "Incomplete diagnostic port"}
        }
        set build [format %08x [lindex $values 0]]
        if {$build ne "465805e1"} {error "Wrong firmware identity: $build"}
        set observed [lesson05d_hex_vector [lindex $values 1] 96]
        set heartbeat [format %08x [lindex $values 2]]
        lappend rows "$i\t$build\t$observed\t$heartbeat\t$t0\t$t1"
        puts "GT_SAMPLE index=$i flags=[string range $observed 16 23] heartbeat=$heartbeat"
        after 150
    }
    set h [open $file w]
    puts $h "index\tbuild_hex\tobservation_hex\theartbeat_hex\trefresh_start_us\trefresh_end_us"
    puts $h [join $rows \n];close $h
}
