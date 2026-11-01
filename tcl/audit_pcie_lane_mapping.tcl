# Read-only netlist audit. Caller opens a saved DCP; this file never connects
# hardware, edits placement/routing or writes a checkpoint.
proc audit_pcie_leaf_outputs {pin} {
    return [get_pins -quiet -leaf -of_objects [get_nets -quiet -segments -of_objects $pin] -filter {DIRECTION==OUT}]
}
proc audit_pcie_leaf_inputs {pin} {
    return [get_pins -quiet -leaf -of_objects [get_nets -quiet -segments -of_objects $pin] -filter {DIRECTION==IN}]
}
proc audit_pcie_lane_mapping {path} {
    set cores [get_cells -hier -filter {REF_NAME==PCIE40E4}]
    if {[llength $cores]!=1} {error "Expected one PCIE40E4"}
    set core [lindex $cores 0]
    set h [open $path {WRONLY CREAT EXCL}]
    puts $h "kind\tlane\tpolarity_or_bit\tpackage_pin\tgt_loc\thard_pin\tverified"
    for {set lane 0} {$lane<4} {incr lane} {
        set rx {};set tx {}
        foreach direction {rx tx} {
            foreach polarity {p n} {
                set port [get_ports [format {pcie_%s_%s[%d]} $direction $polarity $lane]]
                set pins [concat [audit_pcie_leaf_inputs $port] [audit_pcie_leaf_outputs $port]]
                set candidates {}
                foreach pin $pins {
                    set c [get_cells -of_objects $pin]
                    if {[get_property REF_NAME $c] eq "GTYE4_CHANNEL"} {lappend candidates $c}
                }
                set candidates [lsort -unique $candidates]
                if {[llength $candidates]!=1} {error "Ambiguous serial port $port"}
                set channel [lindex $candidates 0]
                if {[set $direction] ne "" && [set $direction] ne $channel} {error "Differential pair channel mismatch"}
                set $direction $channel
                puts $h "$direction\t$lane\t$polarity\t[get_property PACKAGE_PIN $port]\t[get_property LOC $channel]\t-\t1"
            }
        }
        if {$rx ne $tx} {error "TX/RX channel mismatch"}
        for {set bit 0} {$bit<32} {incr bit} {
            set gt_pin [get_pins [format {%s/TXDATA[%d]} $tx $bit]]
            set q [audit_pcie_leaf_outputs $gt_pin]
            if {[llength $q]!=1 || [get_property REF_NAME [get_cells -of_objects $q]] ne "FDRE"} {error "Unexpected TX data path"}
            set d [get_pins [get_cells -of_objects $q]/D]
            set source [audit_pcie_leaf_outputs $d]
            set expected [get_pins [format {%s/PIPETX%02dDATA[%d]} $core $lane $bit]]
            if {$source ne $expected} {error "TX logical lane/bit mapping differs at lane$lane bit$bit"}
            puts $h "TX_DATA\t$lane\t$bit\t-\t[get_property LOC $tx]\t$expected\t1"
            set gt_pin [get_pins [format {%s/RXDATA[%d]} $rx $bit]]
            set sinks [audit_pcie_leaf_inputs $gt_pin];set chains {}
            foreach sink $sinks {
                set c [get_cells -of_objects $sink]
                if {[get_property REF_NAME $c] eq "FDRE" && [get_property REF_PIN_NAME $sink] eq "D"} {lappend chains $c}
            }
            if {[llength $chains]!=1} {error "Unexpected RX data path"}
            set expected [get_pins [format {%s/PIPERX%02dDATA[%d]} $core $lane $bit]]
            if {$expected ni [audit_pcie_leaf_inputs [get_pins [lindex $chains 0]/Q]]} {error "RX logical lane/bit mapping differs"}
            puts $h "RX_DATA\t$lane\t$bit\t-\t[get_property LOC $rx]\t$expected\t1"
        }
    }
    close $h
    puts "PCIE_LANE_MAP_PASS serial_ports=16 data_bits=256"
}
