# Controlled cross-quad clock-selection experiment based on d8 observations.
proc lesson05d_refclk_fix {out part base} {
    if {$part ne "xcku5p-ffvb676-1-i"} {error "Unverified part"}
    set out [file normalize $out];file mkdir [file join $out reports]
    open_checkpoint $base
    set clocknet [get_nets -of_objects [get_pins reference_input/O]]
    set zero [get_nets -of_objects [get_pins {monitor/probe_in1[0]}]]
    set one [get_nets -of_objects [get_pins {monitor/probe_in1[3]}]]
    set changed [list $clocknet $zero $one]
    set endpoints {}
    foreach c [get_cells -hier -filter {REF_NAME==GTYE4_CHANNEL || REF_NAME==GTYE4_COMMON}] {
        if {[get_property REF_NAME $c] eq "GTYE4_CHANNEL"} {
            set oldports {GTREFCLK0};set newports {GTNORTHREFCLK1};set selectors {CPLLREFCLKSEL}
        } else {
            set oldports {GTREFCLK00 GTREFCLK01};set newports {GTNORTHREFCLK10 GTNORTHREFCLK11};set selectors {QPLL0REFCLKSEL QPLL1REFCLKSEL}
        }
        foreach name $oldports {
            set p [get_pins -of_objects $c -filter "REF_PIN_NAME==$name"]
            lappend changed {*}[get_nets -segments -of_objects $p]
            disconnect_net -net [get_nets -of_objects $p] -objects $p
            connect_net -hierarchical -net $zero -objects $p
        }
        foreach name $newports {
            set p [get_pins -of_objects $c -filter "REF_PIN_NAME==$name"]
            lappend changed {*}[get_nets -segments -of_objects $p]
            disconnect_net -net [get_nets -of_objects $p] -objects $p
            connect_net -hierarchical -net $clocknet -objects $p
            lappend endpoints [get_property NAME $p]
        }
        foreach name $selectors {
            foreach bit {0 1 2} {
                set p [get_pins -of_objects $c -filter [format {REF_PIN_NAME==%s[%d]} $name $bit]]
                lappend changed {*}[get_nets -segments -of_objects $p]
                disconnect_net -net [get_nets -of_objects $p] -objects $p
                if {$bit==2} {set n $one} else {set n $zero}
                connect_net -hierarchical -net $n -objects $p
            }
        }
    }
    set p [get_pins {monitor/probe_in1[0]}]
    disconnect_net -net [get_nets -of_objects $p] -objects $p
    connect_net -hierarchical -net $one -objects $p
    # Hierarchical reconnection may prune old segments; reroute the placed design.
    route_design -unroute
    route_design
    foreach {cmd file} {report_timing_summary timing_routed.rpt check_timing check_timing_routed.rpt report_route_status route_status.rpt report_drc drc_routed.rpt report_cdc cdc_routed.rpt report_bus_skew bus_skew_routed.rpt} {
        $cmd -file [file join $out reports $file]
    }
    write_checkpoint -force [file join $out lesson05d_pcie_top_routed.dcp]
    close_project;open_checkpoint [file join $out lesson05d_pcie_top_routed.dcp]
    set clocknets [get_nets -segments -of_objects [get_pins reference_input/O]]
    foreach name $endpoints {
        set joined 0
        foreach n [get_nets -segments -of_objects [get_pins $name]] {if {$n in $clocknets} {set joined 1}}
        if {!$joined} {error "Clock connection not retained: $name"}
    }
    write_debug_probes -force [file join $out lesson05d_pcie_top.ltx]
    write_bitstream -force [file join $out lesson05d_pcie_top.bit]
    puts "REFCLK_SELECTION_EXPERIMENT_COMPLETE"
}
