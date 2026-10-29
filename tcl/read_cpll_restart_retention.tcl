# Source defines a read-only post-restart procedure; it does not program/reset.
source -notrace [file join [file dirname [info script]] lesson05d_hardware.tcl]
proc lesson05gh_read_restart_retention {out label} {
    if {![regexp {^[A-Za-z0-9_-]+$} $label]} {error "Invalid capture label"}
    set out [file normalize $out];file mkdir [file join $out hardware]
    set record [file join $out hardware ${label}_retention.tcldict]
    if {[file exists $record]} {error "Do not overwrite a prior startup observation"}
    set device [lesson05d_attach]
    set_property PARAM.FREQUENCY 6000000 [current_hw_target]
    set done [get_property {REGISTER.CONFIG_STATUS.BIT[14]_DONE_PIN} $device]
    set result [dict create observed_unix [clock seconds] configuration_done $done \
        programmed_after_restart false reset_written_after_restart false jtag_hz [get_property PARAM.FREQUENCY [current_hw_target]]]
    set h [open $record w];puts $h $result;close $h
    if {!$done} {puts "RETENTION_NOT_CONFIRMED: configuration DONE is low";return $result}
    # Associate probe metadata only; this does not change FPGA SRAM or VIO.
    set_property PROBES.FILE [file join $out lesson05d_pcie_top.ltx] $device
    refresh_hw_device $device
    set vio [get_hw_vios -of_objects $device]
    dict set result vio_count [llength $vio]
    if {[llength $vio]==1} {
        set probes [get_hw_probes -of_objects $vio -filter {TYPE==vio_input}]
        set_property INPUT_VALUE_RADIX HEX $probes
        refresh_hw_vio $vio
        set values {0 0};set masks {0 0}
        foreach p $probes {
            set port [get_property PROBE_PORT $p]
            if {$port ni {0 1}} {continue}
            set first [get_property PROBE_PORT_BITS $p];set width [get_property PROBE_PORT_BIT_COUNT $p]
            if {![string is integer -strict $first]} {error "Unknown input fragments"}
            set raw [get_property INPUT_VALUE $p]
            if {![regexp {^[0-9a-fA-F]+$} $raw]} {error "Unknown observed bits"}
            set mask [expr {((1<<$width)-1)<<$first}]
            if {[lindex $masks $port]&$mask} {error "Overlapping fragments"}
            lset masks $port [expr {[lindex $masks $port]|$mask}]
            lset values $port [expr {[lindex $values $port]|([expr 0x$raw]<<$first)}]
        }
        if {$masks ne {255 4294967295}} {error "Incomplete e0 identity/status ports"}
        dict set result observed_build [format %08x [lindex $values 1]]
        dict set result observed_status [format %02x [lindex $values 0]]
        set reset [get_hw_probes -of_objects $vio -filter {TYPE==vio_output}]
        if {[llength $reset]==1 && [get_property WIDTH $reset]==1} {
            refresh_hw_vio -update_output_values $vio
            scan [get_property OUTPUT_VALUE $reset] %x value
            dict set result local_reset_readback $value
        }
    }
    set h [open $record w];puts $h $result;close $h
    if {![dict exists $result observed_build] || [dict get $result observed_build] ne "465805e0" ||
        ![dict exists $result local_reset_readback] || [dict get $result local_reset_readback]!=0} {
        puts "RETENTION_NOT_CONFIRMED: expected e0/reset0 was not observed; preserved state without programming or resetting"
        return $result
    }
    lesson05d_read_status $out $label 465805e0
    lesson05d_read_phy $out $label 465805e0
    lesson05d_read_training $out $label 465805e0
    puts "EXPECTED_E0_RESET0_RETAINED: further link/enumeration analysis still required"
    return $result
}
