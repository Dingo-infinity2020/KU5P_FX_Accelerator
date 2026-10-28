# Calibrate the capture path using a same-clock counter. Base is da, not db.
# probe0[0] remains divided reference, probe0[1] becomes SYS_CLK heartbeat[7].
proc lesson05d_clock_sanity {out part base} {
    if {$part ne "xcku5p-ffvb676-1-i"} {error "Unverified target"}
    set out [file normalize $out];file mkdir [file join $out reports]
    open_checkpoint $base
    set zero [get_nets -of_objects [get_pins -hier -filter {REF_PIN_NAME==G && NAME =~ *GND*}]]
    set one [get_nets -of_objects [get_pins -hier -filter {REF_PIN_NAME==P && NAME =~ *VCC*}]]
    set zero [lindex $zero 0];set one [lindex $one 0]
    set heartbeat [get_nets -of_objects [get_pins {heartbeat_reg[7]/Q}]]
    if {$zero eq "" || $one eq "" || [llength $heartbeat]!=1} {error "Missing source"}
    # Keep the HDL ILA untouched. Change an external diagnostic register input.
    # This also repurposes the AXI activity watchdog: status bit7 is invalid as
    # an AXI clock indicator in this calibration profile.
    foreach {name net} [list {clock_monitor/sample2_reg[1]/D} $heartbeat {monitor/probe_in1[1]} $zero {monitor/probe_in1[2]} $one] {
        set pin [get_pins $name]
        if {[llength $pin]!=1} {error "Missing target pin"}
        disconnect_net -net [get_nets -of_objects $pin] -objects $pin
        connect_net -hierarchical -net $net -objects $pin
    }
    route_design -unroute
    route_design
    foreach {cmd file} {report_timing_summary timing_routed.rpt check_timing check_timing_routed.rpt report_route_status route_status.rpt report_drc drc_routed.rpt report_cdc cdc_routed.rpt report_bus_skew bus_skew_routed.rpt report_utilization utilization_routed.rpt} {
        $cmd -file [file join $out reports $file]
    }
    write_checkpoint -force [file join $out lesson05d_pcie_top_routed.dcp]
    close_project;open_checkpoint [file join $out lesson05d_pcie_top_routed.dcp]
    set a [get_nets -segments -of_objects [get_pins {heartbeat_reg[7]/Q}]]
    set joined 0
    foreach n [get_nets -segments -of_objects [get_pins {clock_monitor/sample2_reg[1]/D}]] {if {$n in $a} {set joined 1}}
    if {!$joined} {error "Heartbeat observation did not persist"}
    write_debug_probes -force [file join $out lesson05d_pcie_top.ltx]
    write_bitstream -force [file join $out lesson05d_pcie_top.bit]
    puts "CLOCK_SANITY_EXPERIMENT_COMPLETE"
}
