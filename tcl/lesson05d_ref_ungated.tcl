# From accepted de. Only diagnostic BUFG CEMASK changes; core gate unchanged.
proc lesson05d_ref_ungated {out part base} {
    global repo_dir
    if {$part ne "xcku5p-ffvb676-1-i"} {error "Unverified target"}
    set_param tcl.collectionResultDisplayLimit 0
    source -notrace [file join $repo_dir tcl lesson05d_ref_prescale.tcl]
    set out [file normalize $out];set reports [file join $out reports];file mkdir $reports
    open_checkpoint $base
    lesson05d_prescale_inputs [file join $reports functional_inputs_before.tsv]
    set one [get_nets {<const1>}]
    foreach name {diagnostic_ref_div8/CEMASK monitor/probe_in1[0]} {
        set p [get_pins $name]
        disconnect_net -net [get_nets -of_objects $p] -objects $p
        connect_net -hierarchical -net $one -objects $p
    }
    route_design
    foreach {cmd file} {report_timing_summary timing_routed.rpt check_timing check_timing_routed.rpt report_route_status route_status.rpt report_drc drc_routed.rpt report_cdc cdc_routed.rpt report_bus_skew bus_skew_routed.rpt report_utilization utilization_routed.rpt report_clocks clocks.rpt} {
        $cmd -file [file join $reports $file]
    }
    write_checkpoint -force [file join $out lesson05d_pcie_top_routed.dcp]
    close_project;open_checkpoint [file join $out lesson05d_pcie_top_routed.dcp]
    foreach name {diagnostic_ref_div8/CEMASK monitor/probe_in1[0]} {
        set c [get_cells -of_objects [get_pins -of_objects [get_nets -of_objects [get_pins $name]] -filter {DIRECTION==OUT}]]
        if {[llength $c]!=1 || [get_property REF_NAME $c] ne "VCC"} {error "Ungate/identity not retained"}
    }
    lesson05d_prescale_inputs [file join $reports functional_inputs_after.tsv]
    set h [open [file join $reports functional_inputs_before.tsv] r];set before [read $h];close $h
    set h [open [file join $reports functional_inputs_after.tsv] r];set after [read $h];close $h
    if {$before ne $after} {error "Functional inputs changed"}
    foreach delay {max min} {
        if {[llength [get_timing_paths -quiet -delay_type $delay -slack_lesser_than 0 -max_paths 1]]} {error "Timing failed; no accepted bitstream"}
    }
    set h [open [file join $reports verified_pins.tsv] w];puts $h "port\tpackage_pin"
    foreach p [get_ports] {puts $h "$p\t[get_property PACKAGE_PIN $p]"};close $h
    write_debug_probes -force [file join $out lesson05d_pcie_top.ltx]
    write_bitstream -force [file join $out lesson05d_pcie_top.bit]
    puts "REF_UNGATED_EXPERIMENT_COMPLETE"
}
