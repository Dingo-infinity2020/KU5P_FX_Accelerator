# Sourcing defines procedures only. No clock-chip configuration writes exist.
source -notrace [file join [file dirname [info script]] lesson05d_hardware.tcl]
proc lesson05f_status {} {
    set vio [get_hw_vios]
    if {[llength $vio]!=1} {error "Expected one VIO"}
    set probes [get_hw_probes -of_objects $vio -filter {TYPE==vio_input}]
    set_property INPUT_VALUE_RADIX HEX $probes
    set t0 [clock clicks -microseconds];refresh_hw_vio $vio;set t1 [clock clicks -microseconds]
    set values {0 0 0};set masks {0 0 0}
    foreach p $probes {
        set port [get_property PROBE_PORT $p];set first [get_property PROBE_PORT_BITS $p];set width [get_property PROBE_PORT_BIT_COUNT $p]
        if {$port ni {0 1 2} || ![string is integer -strict $first]} {error "Unexpected probe fragments"}
        set mask [expr {((1<<$width)-1)<<$first}]
        if {[lindex $masks $port]&$mask} {error "Overlapping fragments"}
        set raw [get_property INPUT_VALUE $p]
        if {![regexp {^[0-9a-fA-F]+$} $raw]} {error "Unknown VIO input"}
        lset masks $port [expr {[lindex $masks $port]|$mask}]
        lset values $port [expr {[lindex $values $port]|([expr 0x$raw]<<$first)}]
    }
    foreach port {0 1 2} width {32 64 32} {if {[lindex $masks $port]!=((1<<$width)-1)} {error "Incomplete probe"}}
    if {[format %08x [lindex $values 0]] ne "465805f1"} {error "Wrong Si5338 reader firmware"}
    set value [lindex $values 1]
    return [dict create raw [lesson05d_hex_vector $value 64] data [expr {$value&255}] \
        reg [expr {($value>>8)&255}] busy [expr {($value>>16)&1}] err [expr {($value>>24)&15}] \
        seq [expr {($value>>32)&65535}] phase [expr {($value>>48)&31}] \
        straps [expr {($value>>56)&7}] heartbeat [format %08x [lindex $values 2]] t0 $t0 t1 $t1]
}
proc lesson05f_program {out} {
    foreach name {verification.json lesson05f_si5338_top.bit lesson05f_si5338_top.ltx} {
        if {![file exists [file join $out $name]]} {error "Missing accepted artifact $name"}
    }
    set d [lesson05d_attach];set_property PARAM.FREQUENCY 6000000 [current_hw_target]
    set_property PROGRAM.FILE [file join $out lesson05f_si5338_top.bit] $d
    set_property PROBES.FILE [file join $out lesson05f_si5338_top.ltx] $d
    program_hw_devices $d;refresh_hw_device $d
    if {![get_property {REGISTER.CONFIG_STATUS.BIT[14]_DONE_PIN} $d]} {error "DONE low"}
    file mkdir [file join $out hardware]
    set h [open [file join $out hardware programmed.txt] w]
    puts $h "configuration=JTAG_SRAM\nbuild=465805f1\nprogrammed_unix=[clock seconds]\njtag_hz=[get_property PARAM.FREQUENCY [current_hw_target]]";close $h
    set status [lesson05f_status]
    set h [open [file join $out hardware initial_status.tcldict] w];puts $h $status;close $h
    puts "SI5338_READER_READY $status"
}
proc lesson05f_read_register {out label address} {
    if {![regexp {^[a-zA-Z0-9_-]+$} $label] || $address<0 || $address>255} {error "Invalid read request"}
    set before [lesson05f_status]
    if {[dict get $before busy]} {error "Previous transaction still busy"}
    set vio [get_hw_vios]
    set reset_probe [get_hw_probes -of_objects $vio -filter {TYPE==vio_output && WIDTH==1}]
    set command_probe [get_hw_probes -of_objects $vio -filter {TYPE==vio_output && WIDTH==9}]
    if {[llength $reset_probe]!=1 || [llength $command_probe]!=1} {error "Unexpected command interface"}
    refresh_hw_vio -update_output_values $vio
    scan [get_property OUTPUT_VALUE $reset_probe] %x reset
    if {$reset!=0} {error "Reader reset is asserted"}
    scan [get_property OUTPUT_VALUE $command_probe] %x previous
    set command [expr {($address<<1)|(($previous&1)^1)}]
    set_property OUTPUT_VALUE [format %03x $command] $command_probe
    commit_hw_vio $vio
    set expected [expr {([dict get $before seq]+1)&65535}]
    set completed 0
    for {set i 0} {$i<80} {incr i} {
        set status [lesson05f_status]
        if {[dict get $status seq]==$expected && ![dict get $status busy]} {set completed 1;break}
        if {[dict get $status seq]!=[dict get $before seq]} {error "Unexpected completion counter"}
        after 2
    }
    if {!$completed || [dict get $status reg]!=$address} {error "Read completion did not match request"}
    set file [file join $out hardware ${label}.tsv]
    if {![info exists ::lesson05f_rows($file)]} {
        if {[file exists $file]} {error "Do not overwrite an existing capture"}
        set ::lesson05f_rows($file) 0
        set h [open $file w];puts $h "index\taddress\tdata_hex\terror\tsequence\tresult_hex\theartbeat_hex\tcommand_hex\trefresh_start_us\trefresh_end_us";close $h
    }
    set h [open $file a]
    puts $h "$::lesson05f_rows($file)\t$address\t[format %02x [dict get $status data]]\t[dict get $status err]\t[dict get $status seq]\t[dict get $status raw]\t[dict get $status heartbeat]\t[format %03x $command]\t[dict get $status t0]\t[dict get $status t1]";close $h
    incr ::lesson05f_rows($file)
    if {[dict get $status err]!=0} {error "I2C read failed: register=$address error=[dict get $status err]"}
    return $status
}
proc lesson05f_dump {out label} {
    set first [lesson05f_read_register $out $label 255]
    for {set reg 0} {$reg<255} {incr reg} {
        lesson05f_read_register $out $label $reg
        if {$reg%32==31} {puts "SI5338_DUMP=$label registers=[expr {$reg+1}]"}
    }
    set last [lesson05f_read_register $out $label 255]
    if {[dict get $first data]!=[dict get $last data]} {error "Page selector changed during read-only dump"}
    puts "SI5338_DUMP_COMPLETE=$label page=[expr {[dict get $first data]&1}]"
}
proc lesson05f_arm_i2c_trace {} {
    set ila [get_hw_ilas];if {[llength $ila]!=1} {error "Expected one ILA"}
    set data [get_hw_probes -of_objects $ila -filter {PROBE_PORT==0}]
    set trigger [get_hw_probes -of_objects $ila -filter {PROBE_PORT==1}]
    if {![llength $data] || [llength $trigger]!=1 || [get_property WIDTH $trigger]!=1} {error "Unexpected ILA layout"}
    foreach p $data {set_property TRIGGER_COMPARE_VALUE [format {eq%d'b%s} [get_property WIDTH $p] [string repeat X [get_property WIDTH $p]]] $p}
    set_property TRIGGER_COMPARE_VALUE {eq1'b1} $trigger
    set_property CONTROL.DATA_DEPTH 8192 $ila
    set_property CONTROL.TRIGGER_POSITION 0 $ila
    set_property DISPLAY_RADIX HEX $data
    run_hw_ila $ila
}
proc lesson05f_save_trace {out label} {
    set ila [get_hw_ilas];wait_on_hw_ila -timeout 15 $ila
    set data [upload_hw_ila_data $ila]
    set h [open [file join $out hardware ${label}_layout.tsv] w]
    puts $h "object\tname\tport\tfirst_bit\twidth"
    foreach p [get_hw_probes -of_objects $ila] {
        puts $h "$p\t[get_property NAME $p]\t[get_property PROBE_PORT $p]\t[get_property PROBE_PORT_BITS $p]\t[get_property PROBE_PORT_BIT_COUNT $p]"
    };close $h
    write_hw_ila_data -force -csv_file [file join $out hardware ${label}.csv] $data
    write_hw_ila_data -force [file join $out hardware ${label}.ila] $data
    puts "SI5338_TRACE=$label"
}
