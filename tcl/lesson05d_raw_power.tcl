# Observe each primitive's raw GTPOWERGOOD, not sys_clk_ce_out's soft alias.
proc lesson05d_raw_power {out part base} {
    if {$part ne "xcku5p-ffvb676-1-i"} {error "Unverified target"}
    set out [file normalize $out];file mkdir [file join $out reports]
    open_checkpoint $base
    set endpoints {}
    foreach site {GTYE4_CHANNEL_X0Y4 GTYE4_CHANNEL_X0Y5 GTYE4_CHANNEL_X0Y6 GTYE4_CHANNEL_X0Y7} bit {17 18 19 26} {
        set cell [get_cells -hier -filter "REF_NAME==GTYE4_CHANNEL && LOC==$site"]
        if {[llength $cell]!=1} {error "Missing channel $site"}
        set src [get_pins -of_objects $cell -filter {REF_PIN_NAME==GTPOWERGOOD}]
        set sink [get_pins [format {phy_monitor/sample1_reg[%d]/D} $bit]]
        set net [get_nets -quiet -of_objects $src]
        if {![llength $net]} {
            set net [create_net raw_powergood_$bit]
            connect_net -hierarchical -net $net -objects $src
        }
        disconnect_net -net [get_nets -of_objects $sink] -objects $sink
        connect_net -hierarchical -net $net -objects $sink
        lappend endpoints $bit [get_property NAME $src]
    }
    set one [lindex [get_nets -of_objects [get_pins -hier -filter {REF_PIN_NAME==P && NAME =~ *VCC*}]] 0]
    set p [get_pins {monitor/probe_in1[0]}]
    disconnect_net -net [get_nets -of_objects $p] -objects $p
    connect_net -hierarchical -net $one -objects $p
    route_design -unroute
    route_design
    foreach {cmd file} {report_timing_summary timing_routed.rpt check_timing check_timing_routed.rpt report_route_status route_status.rpt report_drc drc_routed.rpt report_cdc cdc_routed.rpt report_bus_skew bus_skew_routed.rpt report_utilization utilization_routed.rpt} {
        $cmd -file [file join $out reports $file]
    }
    write_checkpoint -force [file join $out lesson05d_pcie_top_routed.dcp]
    close_project;open_checkpoint [file join $out lesson05d_pcie_top_routed.dcp]
    set h [open [file join $out reports persisted_raw_power.tsv] w]
    puts $h "bit\tprimitive_pin\tconnected"
    foreach {bit name} $endpoints {
        set a [get_nets -segments -of_objects [get_pins $name]]
        set joined 0
        foreach n [get_nets -segments -of_objects [get_pins [format {phy_monitor/sample1_reg[%d]/D} $bit]]] {if {$n in $a} {set joined 1}}
        if {!$joined} {error "Raw power observation not retained"}
        puts $h "$bit\t$name\t$joined"
    }
    close $h
    write_debug_probes -force [file join $out lesson05d_pcie_top.ltx]
    write_bitstream -force [file join $out lesson05d_pcie_top.bit]
    puts "RAW_POWER_OBSERVERS_COMPLETE"
}
