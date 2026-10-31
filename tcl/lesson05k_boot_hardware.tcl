# e6/lesson05k read-only and explicit hardware entry. Sourcing defines
# procedures only. e6 has no manual PHY reset: VIO output0 is reserved and
# must remain 0; output1 is the event read address; output2 is capture arm.
source -notrace [file join [file dirname [info script]] lesson05d_hardware.tcl]
set ::lesson05k_build 465805e6

proc lesson05k_attach_readonly {out label} {
    if {![regexp {^[a-zA-Z0-9_-]+$} $label]} {error "Invalid label"}
    file mkdir [file join $out hardware]
    set h [open [file join $out hardware ${label}_retention.tcldict] {WRONLY CREAT EXCL}]
    set d [lesson05d_attach]
    set_property PARAM.FREQUENCY 6000000 [current_hw_target]
    set done [get_property {REGISTER.CONFIG_STATUS.BIT[14]_DONE_PIN} $d]
    set result [dict create observed_unix [clock seconds] done $done program_executed false output_commit_executed false]
    puts $h $result; flush $h
    if {!$done} {close $h; return $result}
    set_property PROBES.FILE [file join $out lesson05k_pcie_perst_top.ltx] $d
    refresh_hw_device $d
    set values [lesson05k_values]
    set v [get_hw_vios]
    dict set result identity_hex [format %08x [lindex $values 0]]
    dict set result metadata_hex [lesson05d_hex_vector [lindex $values 7] 128]
    dict set result read_data_hex [lesson05d_hex_vector [lindex $values 6] 256]
    dict set result controls_hex [lesson05d_hex_vector [lindex $values 4] 128]
    refresh_hw_vio -update_output_values $v
    foreach p [get_hw_probes -of_objects $v -filter {TYPE==vio_output}] {
        dict set result output_[get_property PROBE_PORT $p] [get_property OUTPUT_VALUE $p]
    }
    if {[dict get $result identity_hex] ne "465805e6" && [dict get $result identity_hex] ne "465805e4"} {
        error "Unexpected current image identity"
    }
    puts $h $result; close $h; puts $result; return $result
}

proc lesson05k_values {} {
    set v [get_hw_vios]
    if {[llength $v]!=1} {error "Expected one startup VIO"}
    set_property INPUT_VALUE_RADIX HEX [get_hw_probes -of_objects $v -filter {TYPE==vio_input}]
    refresh_hw_vio $v
    set widths {32 64 64 64 128 128 256 128};set values {0 0 0 0 0 0 0 0};set masks {0 0 0 0 0 0 0 0}
    foreach p [get_hw_probes -of_objects $v -filter {TYPE==vio_input}] {
        set port [get_property PROBE_PORT $p];set first [get_property PROBE_PORT_BITS $p]
        set width [get_property PROBE_PORT_BIT_COUNT $p];set raw [get_property INPUT_VALUE $p]
        if {$port<0 || $port>7 || ![string is integer -strict $first] || ![regexp {^[a-fA-F0-9]+$} $raw]} {error "Unknown probe metadata/value"}
        set mask [expr {((1<<$width)-1)<<$first}]
        if {[lindex $masks $port]&$mask} {error "Overlapping probe fragments"}
        lset masks $port [expr {[lindex $masks $port]|$mask}]
        lset values $port [expr {[lindex $values $port]|([expr 0x$raw]<<$first)}]
    }
    for {set n 0} {$n<8} {incr n} {if {[lindex $masks $n] != ((1<<[lindex $widths $n])-1)} {error "Incomplete startup probe $n"}}
    if {[lindex $values 0]!=0x465805e6} {error "Wrong startup image"}
    return $values
}

proc lesson05k_output {port value} {
    if {$port==0} {error "e6 output0 is reserved; never write it"}
    if {$port ni {1 2}} {error "Only read_address/arm may be written on e6"}
    set v [get_hw_vios];set probes [get_hw_probes -of_objects $v -filter {TYPE==vio_output}]
    # commit_hw_vio commits every output; refresh actual retained values first so
    # an indexed RAM read cannot reassert a cached control.
    refresh_hw_vio -update_output_values $v
    set before [dict create]
    foreach probe $probes {dict set before [get_property PROBE_PORT $probe] [expr 0x[get_property OUTPUT_VALUE $probe]]}
    set p {};foreach probe $probes {if {[get_property PROBE_PORT $probe]==$port} {set p $probe}}
    if {[llength $p]!=1 || $value<0 || $value>=(1<<[get_property WIDTH $p])} {error "Invalid control port/value"}
    if {[dict get $before 0]!=0} {error "Reserved output0 is not 0 before commit"}
    set_property OUTPUT_VALUE_RADIX HEX $p
    set digits [expr {([get_property WIDTH $p]+3)/4}]
    set_property OUTPUT_VALUE [format %0*x $digits $value] $p;commit_hw_vio $v
    refresh_hw_vio -update_output_values $v
    foreach probe $probes {
        set other [get_property PROBE_PORT $probe]
        if {$other==0 && [expr 0x[get_property OUTPUT_VALUE $probe]]!=0} {error "Reserved output0 changed"}
        if {$other!=$port && $other!=0 && [expr 0x[get_property OUTPUT_VALUE $probe]]!=[dict get $before $other]} {error "Unrelated VIO control changed"}
    }
    set actual [expr 0x[get_property OUTPUT_VALUE $p]]
    if {$value!=$actual} {error "Control readback differs"}
    return $actual
}

proc lesson05k_snapshot {out label {count 12}} {
    if {![regexp {^[a-zA-Z0-9_-]+$} $label] || $count<1 || $count>32} {error "Invalid sample request"}
    set path [file join $out hardware ${label}.tsv];file mkdir [file dirname $path]
    set h [open $path {WRONLY CREAT EXCL}]
    puts $h "unix_ms\tindex\tbuild_hex\traw_hex\tever_high_hex\tever_low_hex\tclocks_hex\ttraining_hex\tevent_hex\tmetadata_hex"
    for {set i 0} {$i<$count} {incr i} {
        set values [lesson05k_values];set row [list [clock milliseconds] $i]
        foreach value $values width {32 64 64 64 128 128 256 128} {lappend row [lesson05d_hex_vector $value $width]}
        puts $h [join $row \t];flush $h
        puts "BOOT_SAMPLE label=$label index=$i raw=[lindex $row 3] meta=[lindex $row 9]"
        after 150
    };close $h
}

proc lesson05k_program {out} {
    if {![file exists [file join $out verification.json]]} {error "Accepted build proof required"}
    set d [lesson05d_attach];set_property PARAM.FREQUENCY 6000000 [current_hw_target]
    set_property PROGRAM.FILE [file join $out lesson05k_pcie_perst_top.bit] $d
    set_property PROBES.FILE [file join $out lesson05k_pcie_perst_top.ltx] $d
    program_hw_devices $d;refresh_hw_device $d
    if {![get_property {REGISTER.CONFIG_STATUS.BIT[14]_DONE_PIN} $d]} {error "DONE low"}
    set values [lesson05k_values]
    set v [get_hw_vios];refresh_hw_vio -update_output_values $v
    foreach p [get_hw_probes -of_objects $v -filter {TYPE==vio_output}] {
        if {[get_property PROBE_PORT $p]==0 && [expr 0x[get_property OUTPUT_VALUE $p]]!=0} {error "Reserved output0 not 0 after program"}
    }
    file mkdir [file join $out hardware]
    set h [open [file join $out hardware programmed.tcldict] {WRONLY CREAT EXCL}]
    puts $h [dict create build 465805e6 configuration JTAG_SRAM programmed_unix [clock seconds] done 1 jtag_hz [get_property PARAM.FREQUENCY [current_hw_target]] reset_contract PERST_ONLY output0 0]
    close $h;puts BOOT_IMAGE_PROGRAMMED
}

proc lesson05k_read_index {address {settle_ms 5}} {
    if {$address<0 || $address>511} {error "Invalid event address"}
    if {[lesson05k_output 1 $address]!=$address} {error "Read address echo mismatch"}
    after $settle_ms
    set first [lesson05k_values]
    after $settle_ms
    set second [lesson05k_values]
    return [dict create address $address first $first second $second equal [expr {[lindex $first 6]==[lindex $second 6]}]]
}

proc lesson05k_probe_read_path {out label} {
    if {![regexp {^[a-zA-Z0-9_-]+$} $label]} {error "Invalid label"}
    set path [file join $out hardware ${label}_read_path.tsv];file mkdir [file dirname $path]
    set h [open $path {WRONLY CREAT EXCL}]
    puts $h "step\taddress\techo\tevent_first_hex\tevent_second_hex\tequal\tmetadata_hex"
    set step 0
    foreach addr {0 1 0 511 0} {
        set r [lesson05k_read_index $addr 5]
        set a [dict get $r first];set b [dict get $r second]
        puts $h "$step\t$addr\t$addr\t[lesson05d_hex_vector [lindex $a 6] 256]\t[lesson05d_hex_vector [lindex $b 6] 256]\t[dict get $r equal]\t[lesson05d_hex_vector [lindex $a 7] 128]"
        flush $h;incr step
    };close $h;puts BOOT_READ_PATH_PROBE=$label
}

proc lesson05k_read_events {out label start {count 32}} {
    if {![regexp {^[a-zA-Z0-9_-]+$} $label] || $start<0 || $count<1 || $count>32 || $start+$count>512} {error "Invalid event request"}
    set old [lesson05k_values];set meta [lindex $old 7]
    set epoch [expr {($meta>>64)&65535}];set entries [expr {($meta>>80)&1023}]
    if {$start+$count>$entries} {error "Requested entries are not captured yet"}
    set path [file join $out hardware ${label}_events_${start}.tsv]
    set h [open $path {WRONLY CREAT EXCL}];puts $h "index\tepoch\tevent_hex\tmetadata_hex\taddress_echo"
    for {set i $start} {$i<$start+$count} {incr i} {
        if {[lesson05k_output 1 $i]!=$i} {close $h;error "Read address echo mismatch"}
        after 3
        set now [lesson05k_values];set meta [lindex $now 7]
        if {(($meta>>64)&65535)!=$epoch || !(($meta>>91)&1)} {close $h;error "Epoch changed or invalid indexed read"}
        puts $h "$i\t$epoch\t[lesson05d_hex_vector [lindex $now 6] 256]\t[lesson05d_hex_vector $meta 128]\t$i";flush $h
    };close $h;puts "BOOT_EVENTS label=$label start=$start count=$count epoch=$epoch"
}

proc lesson05k_capture {out label} {
    if {![regexp {^[a-zA-Z0-9_-]+$} $label]} {error "Invalid label"}
    lesson05k_values;set ila [get_hw_ilas]
    if {[llength $ila]!=1} {error "Expected one independent-clock ILA"}
    if {[get_property CONTROL.CAPTURE_MODE $ila] ne "ALWAYS"} {error "Expected unqualified ILA sampling"}
    foreach ext {csv ila} {if {[file exists [file join $out hardware ${label}.$ext]]} {error "Refuse to overwrite ILA evidence"}}
    set_property CONTROL.DATA_DEPTH 4096 $ila;set_property CONTROL.TRIGGER_POSITION 0 $ila
    run_hw_ila -trigger_now $ila;wait_on_hw_ila -timeout 10 $ila
    set data [upload_hw_ila_data $ila]
    set h [open [file join $out hardware ${label}_layout.tsv] {WRONLY CREAT EXCL}]
    puts $h "object\tname\tport\tfirst_bit\twidth"
    foreach p [get_hw_probes -of_objects $ila] {
        puts $h "$p\t[get_property NAME $p]\t[get_property PROBE_PORT $p]\t[get_property PROBE_PORT_BITS $p]\t[get_property PROBE_PORT_BIT_COUNT $p]"
        set_property DISPLAY_RADIX HEX $p
    };close $h
    write_hw_ila_data -csv_file [file join $out hardware ${label}.csv] $data
    write_hw_ila_data [file join $out hardware ${label}.ila] $data
    puts "BOOT_CLOCK_CAPTURE=$label"
}
