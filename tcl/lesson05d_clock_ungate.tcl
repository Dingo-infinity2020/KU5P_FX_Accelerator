# Single-functional-input experiment: bypass reference fabric BUFG_GT CE.
# The GT analog reference input, selectors and PLL configuration stay unchanged.
proc lesson05d_clock_ungate {out part base} {
    if {$part ne "xcku5p-ffvb676-1-i"} {error "Unverified target"}
    set out [file normalize $out];file mkdir [file join $out reports]
    open_checkpoint $base
    set one [get_nets -of_objects [get_pins -hier -filter {REF_PIN_NAME==P && NAME =~ *VCC*}]]
    set one [lindex $one 0]
    if {$one eq ""} {error "Missing constant one"}
    foreach name {reference_monitor_buffer/CEMASK monitor/probe_in1[0]} {
        set pin [get_pins $name]
        if {[llength $pin]!=1} {error "Missing target pin"}
        disconnect_net -net [get_nets -of_objects $pin] -objects $pin
        connect_net -hierarchical -net $one -objects $pin
    }
    route_design -unroute
    route_design
    foreach {cmd file} {report_timing_summary timing_routed.rpt check_timing check_timing_routed.rpt report_route_status route_status.rpt report_drc drc_routed.rpt report_cdc cdc_routed.rpt report_bus_skew bus_skew_routed.rpt report_utilization utilization_routed.rpt} {
        $cmd -file [file join $out reports $file]
    }
    write_checkpoint -force [file join $out lesson05d_pcie_top_routed.dcp]
    close_project;open_checkpoint [file join $out lesson05d_pcie_top_routed.dcp]
    foreach name {reference_monitor_buffer/CEMASK monitor/probe_in1[0]} {
        set nets [get_nets -segments -of_objects [get_pins $name]]
        set drivers [get_cells -of_objects [get_pins -of_objects $nets -filter {DIRECTION==OUT}]]
        if {[llength $drivers]!=1 || [get_property REF_NAME $drivers] ne "VCC"} {error "Constant not retained: $name"}
    }
    write_debug_probes -force [file join $out lesson05d_pcie_top.ltx]
    write_bitstream -force [file join $out lesson05d_pcie_top.bit]
    puts "UNGATE_EXPERIMENT_COMPLETE"
}
