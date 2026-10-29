# Explicit hardware actions; sourcing this file performs none.
proc lesson05d_attach {} {
    open_hw_manager
    if {![llength [get_hw_servers -quiet]]} {connect_hw_server -url localhost:3121}
    set targets [get_hw_targets -quiet */Digilent/*]
    if {[llength $targets]!=1} {error "Expected exactly one Digilent target"}
    set target [lindex $targets 0];current_hw_target $target
    if {![get_property IS_OPENED $target]} {open_hw_target}
    set devices [get_hw_devices -quiet]
    if {[llength $devices]!=1 || [get_property PART [lindex $devices 0]] ne "xcku5p"} {error "Expected exactly one KU5P"}
    current_hw_device [lindex $devices 0]
    return [lindex $devices 0]
}
proc lesson05d_program {build_dir} {
    set out [file normalize $build_dir]
    foreach name {verification.json lesson05d_pcie_top.bit lesson05d_pcie_top.ltx} {
        if {![file exists [file join $out $name]]} {error "Missing verified artifact $name"}
    }
    set device [lesson05d_attach]
    set_property PROGRAM.FILE [file join $out lesson05d_pcie_top.bit] $device
    set_property PROBES.FILE [file join $out lesson05d_pcie_top.ltx] $device
    program_hw_devices $device
    refresh_hw_device $device
    if {![get_property {REGISTER.CONFIG_STATUS.BIT[14]_DONE_PIN} $device]} {error "DONE low"}
    if {[llength [get_hw_vios -of_objects $device]]!=1} {error "Expected one readonly VIO"}
    file mkdir [file join $out hardware]
    set h [open [file join $out hardware programmed.txt] w]
    puts $h "device=xcku5p\nconfiguration=JTAG_SRAM\nprogrammed_unix=[clock seconds]"
    puts $h "bit_bytes=[file size [file join $out lesson05d_pcie_top.bit]]"
    close $h
    puts "LESSON05D_SRAM_PROGRAMMED"
}
proc lesson05d_read_status {build_dir label {expected_build_id 465805d2}} {
    if {![regexp {^[a-zA-Z0-9_-]+$} $label]} {error "Invalid label"}
    set device [lesson05d_attach]
    set vio [get_hw_vios -of_objects $device]
    if {[llength $vio]!=1} {error "Expected one VIO"}
    # Hardware Manager exposes net names, and constant ports split into bits.
    # Reassemble each port using its actual PROBE_PORT/BITS/COUNT metadata.
    set probes [get_hw_probes -of_objects $vio -filter {TYPE==vio_input}]
    set_property INPUT_VALUE_RADIX HEX $probes
    set out [file join [file normalize $build_dir] hardware];file mkdir $out
    set h [open [file join $out ${label}.tsv] w]
    puts $h "index\tstatus_hex\tbuild_hex"
    for {set i 0} {$i<6} {incr i} {
        refresh_hw_vio $vio
        set values {0 0};set masks {0 0}
        foreach probe $probes {
            set port [get_property PROBE_PORT $probe]
            set first [get_property PROBE_PORT_BITS $probe]
            set width [get_property PROBE_PORT_BIT_COUNT $probe]
            if {$port ni {0 1}} {continue}
            if {![string is integer -strict $first]} {error "Unexpected probe layout"}
            set mask [expr {((1<<$width)-1)<<$first}]
            if {[lindex $masks $port]&$mask} {error "Overlapping probes"}
            lset masks $port [expr {[lindex $masks $port]|$mask}]
            set raw [get_property INPUT_VALUE $probe]
            if {![regexp {^[0-9a-fA-F]+$} $raw]} {error "Unknown probe value"}
            scan $raw %x value
            lset values $port [expr {[lindex $values $port]|($value<<$first)}]
        }
        if {[lindex $masks 0]!=255 || [lindex $masks 1]!=0xffffffff} {error "Incomplete monitor ports"}
        set status [format %02x [lindex $values 0]]
        set identity [format %08x [lindex $values 1]]
        if {$identity ne $expected_build_id} {error "Wrong hardware build identity"}
        puts $h "$i\t$status\t$identity"
        puts "PCIE_MONITOR index=$i status=$status build=$identity"
        after 150
    }
    close $h
}
proc lesson05d_read_training {build_dir label {expected_build_id 465805d4}} {
    if {![regexp {^[a-zA-Z0-9_-]+$} $label]} {error "Invalid label"}
    set device [lesson05d_attach]
    set vio [get_hw_vios -of_objects $device]
    if {[llength $vio]!=1} {error "Expected one VIO"}
    set probes [get_hw_probes -of_objects $vio -filter {TYPE==vio_input}]
    set_property INPUT_VALUE_RADIX HEX $probes
    set out [file join [file normalize $build_dir] hardware];file mkdir $out
    set rows {}
    for {set i 0} {$i<12} {incr i} {
        refresh_hw_vio $vio
        set values {0 0 0 0};set masks {0 0 0 0}
        foreach probe $probes {
            set port [get_property PROBE_PORT $probe]
            set first [get_property PROBE_PORT_BITS $probe]
            set width [get_property PROBE_PORT_BIT_COUNT $probe]
            if {$port==4} {continue}
            if {$port ni {0 1 2 3} || ![string is integer -strict $first]} {error "Unexpected probe layout"}
            set mask [expr {((1<<$width)-1)<<$first}]
            if {[lindex $masks $port]&$mask} {error "Overlapping probes"}
            lset masks $port [expr {[lindex $masks $port]|$mask}]
            set raw [get_property INPUT_VALUE $probe]
            if {![regexp {^[0-9a-fA-F]+$} $raw]} {error "Unknown probe value"}
            set value [expr 0x$raw]
            lset values $port [expr {[lindex $values $port]|($value<<$first)}]
        }
        foreach port {0 1 2 3} width {8 32 128 1} {
            if {[lindex $masks $port] != ((1<<$width)-1)} {error "Incomplete diagnostic ports"}
        }
        if {[format %08x [lindex $values 1]] ne $expected_build_id} {error "Wrong training diagnostic build"}
        set packed [lindex $values 2]
        # Tcl format %x narrows bignums; concatenate fixed 32-bit chunks.
        set hex ""
        foreach shift {96 64 32 0} {append hex [format %08x [expr {($packed>>$shift)&0xffffffff}]]}
        lappend rows "$i\t[format %02x [lindex $values 0]]\t$expected_build_id\t$hex\t[lindex $values 3]"
        puts "TRAINING index=$i status=[format %02x [lindex $values 0]] valid=[lindex $values 3] state=[format %02x [expr {($packed>>96)&63}]] seen=[string range $hex 16 31]"
        after 150
    }
    set h [open [file join $out ${label}_training.tsv] w]
    puts $h "index\tstatus_hex\tbuild_hex\tsnapshot_hex\tvalid"
    puts $h [join $rows \n];close $h
}
proc lesson05d_hex_vector {value bits} {
    set result ""
    for {set shift [expr {$bits-4}]} {$shift>=0} {incr shift -4} {
        append result [format %x [expr {($value>>$shift)&15}]]
    }
    return $result
}
proc lesson05d_read_phy {build_dir label {expected_build_id 465805d5}} {
    if {![regexp {^[a-zA-Z0-9_-]+$} $label]} {error "Invalid label"}
    set device [lesson05d_attach]
    set vio [get_hw_vios -of_objects $device]
    if {[llength $vio]!=1} {error "Expected one VIO"}
    set probes [get_hw_probes -of_objects $vio -filter {TYPE==vio_input}]
    set_property INPUT_VALUE_RADIX HEX $probes
    set out [file join [file normalize $build_dir] hardware];file mkdir $out
    set rows {}
    for {set i 0} {$i<12} {incr i} {
        refresh_hw_vio $vio
        set values {0 0 0 0 0};set masks {0 0 0 0 0}
        foreach probe $probes {
            set port [get_property PROBE_PORT $probe]
            if {$port ni {0 1 4}} {continue}
            set first [get_property PROBE_PORT_BITS $probe]
            set width [get_property PROBE_PORT_BIT_COUNT $probe]
            if {![string is integer -strict $first]} {error "Unexpected probe layout"}
            set mask [expr {((1<<$width)-1)<<$first}]
            if {[lindex $masks $port]&$mask} {error "Overlapping probes"}
            lset masks $port [expr {[lindex $masks $port]|$mask}]
            set raw [get_property INPUT_VALUE $probe]
            if {![regexp {^[0-9a-fA-F]+$} $raw]} {error "Unknown probe value"}
            lset values $port [expr {[lindex $values $port]|([expr 0x$raw]<<$first)}]
        }
        foreach port {0 1 4} width {8 32 144} {
            if {[lindex $masks $port] != ((1<<$width)-1)} {error "Incomplete PHY ports"}
        }
        if {[format %08x [lindex $values 1]] ne $expected_build_id} {error "Wrong PHY diagnostic build"}
        set packed [lindex $values 4]
        set hex [lesson05d_hex_vector $packed 144]
        lappend rows "$i\t[format %02x [lindex $values 0]]\t$expected_build_id\t$hex"
        puts "PHY index=$i status=[format %02x [lindex $values 0]] current=[string range $hex 24 35] high=[string range $hex 12 23] low=[string range $hex 0 11]"
        after 150
    }
    set h [open [file join $out ${label}_phy.tsv] w]
    puts $h "index\tstatus_hex\tbuild_hex\tobservation_hex"
    puts $h [join $rows \n];close $h
}
proc lesson05d_set_local_reset {value} {
    if {$value ni {0 1}} {error "Reset must be 0 or 1"}
    set vio [get_hw_vios]
    if {[llength $vio]!=1} {error "Expected one VIO"}
    set probe [get_hw_probes -of_objects $vio -filter {TYPE==vio_output}]
    if {[llength $probe]!=1 || [get_property WIDTH $probe]!=1} {error "Expected one local reset output"}
    set_property OUTPUT_VALUE $value $probe
    commit_hw_vio $vio
    refresh_hw_vio -update_output_values $vio
    scan [get_property OUTPUT_VALUE $probe] %x actual
    if {$actual!=$value} {error "Local reset readback mismatch"}
    puts "LOCAL_PCIE_RESET=$actual"
    return $actual
}
