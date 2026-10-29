# Diagnostic ECO from a verified d5 routed checkpoint. No AMD source is edited.
# Reuse constant-input synchronizers, leaving PLL controls themselves unchanged.
proc lesson05d_pll_audit {out part base} {
    if {$part ne "xcku5p-ffvb676-1-i"} {error "Unverified part"}
    if {[current_design -quiet] ne ""} {error "Close current design first"}
    set out [file normalize $out]
    file mkdir [file join $out reports]
    open_checkpoint $base
    set channels [get_cells -hier -filter {REF_NAME==GTYE4_CHANNEL}]
    if {[llength $channels]!=4} {error "Expected four GT channels"}
    # Generated x4 wrapper reverses arrays: native GT_CPLL[0] -> primitive [3].
    set channel {}
    foreach c $channels {if {[string first {gen_gtye4_channel_inst[3]} $c]>=0} {lappend channel $c}}
    if {[llength $channel]!=1} {error "Cannot identify logical channel 0"}
    set common [get_cells -hier -filter {REF_NAME==GTYE4_COMMON}]
    if {[llength $common]!=1} {error "Expected one common"}
    # Preserve names as plain strings across close_project/open_checkpoint.
    set channel [get_property NAME $channel]
    set common [get_property NAME $common]
    set map [list 17 $channel CPLLRESET 18 $channel CPLLPD 19 $common QPLL1RESET \
        26 $common QPLL1PD 27 $channel CPLLREFCLKLOST 31 $common QPLL1REFCLKLOST]
    set h [open [file join $out reports eco_connections.tsv] w]
    puts $h "bit\tprimitive_port\tsource_net\tinput_register"
    set changed {}
    foreach {bit cell port} $map {
        set sink [get_pins [format {phy_monitor/sample1_reg[%d]/D} $bit]]
        set next [get_cells [format {phy_monitor/sample2_reg[%d]} $bit]]
        if {[llength $sink]!=1 || [llength $next]!=1 || ![get_property ASYNC_REG $next]} {error "Missing existing synchronizer"}
        set old [get_nets -of_objects $sink]
        set old_driver [get_cells -of_objects [get_pins -of_objects $old -filter {DIRECTION==OUT}]]
        if {[llength $old_driver]!=1 || [get_property REF_NAME $old_driver] ne "GND"} {error "Spare input is not constant zero"}
        set driver [get_pins -of_objects $cell -filter "REF_PIN_NAME==$port"]
        if {[llength $driver]!=1} {error "Missing primitive port $port"}
        set source [get_nets -quiet -of_objects $driver]
        if {![llength $source]} {
            set source [create_net pll_audit_$port]
            connect_net -hierarchical -net $source -objects $driver
        }
        disconnect_net -net $old -objects $sink
        connect_net -hierarchical -net $source -objects $sink
        if {![llength [get_nets -segments -of_objects $sink]]} {error "Unconnected ECO observer"}
        lappend changed $old $source
        puts $h "$bit\t$port\t$source\t$sink"
    }
    close $h
    # d5 -> d8: low nibble 0101 -> 1000.
    set p0 [get_pins {monitor/probe_in1[0]}]
    set p1 [get_pins {monitor/probe_in1[1]}]
    set one [get_nets -of_objects $p0];set zero [get_nets -of_objects $p1]
    if {![string match *<const1> $one] || ![string match *<const0> $zero]} {error "Unexpected base identity"}
    foreach bit {0 2 3} {
        set p [get_pins [format {monitor/probe_in1[%d]} $bit]]
        disconnect_net -net [get_nets -of_objects $p] -objects $p
        if {$bit==3} {set n $one} else {set n $zero}
        connect_net -hierarchical -net $n -objects $p
    }
    lappend changed $zero $one
    route_design -unroute -nets [lsort -unique $changed]
    route_design
    set reports [file join $out reports]
    report_timing_summary -file [file join $reports timing_routed.rpt]
    check_timing -verbose -file [file join $reports check_timing_routed.rpt]
    report_route_status -file [file join $reports route_status.rpt]
    report_drc -file [file join $reports drc_routed.rpt]
    report_cdc -details -file [file join $reports cdc_routed.rpt]
    report_bus_skew -file [file join $reports bus_skew_routed.rpt]
    write_checkpoint -force [file join $out lesson05d_pcie_top_routed.dcp]
    close_project
    open_checkpoint [file join $out lesson05d_pcie_top_routed.dcp]
    foreach {bit cell port} $map {
        set sink [get_pins [format {phy_monitor/sample1_reg[%d]/D} $bit]]
        set src [get_pins -of_objects [get_cells $cell] -filter "REF_PIN_NAME==$port"]
        set a [get_nets -segments -of_objects $sink]
        set b [get_nets -segments -of_objects $src]
        set joined 0
        foreach n $a {if {$n in $b} {set joined 1}}
        if {!$joined} {error "Persisted ECO connection missing: $port"}
    }
    write_debug_probes -force [file join $out lesson05d_pcie_top.ltx]
    write_bitstream -force [file join $out lesson05d_pcie_top.bit]
    puts "PLL_AUDIT_ECO_COMPLETE"
}
