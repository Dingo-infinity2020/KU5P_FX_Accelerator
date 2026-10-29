# Diagnostic-only prescaling from dd: BUFG_GT /8 then counter bit4 (/32).
# Total observed divide stays /256. Core/GT clocks and controls stay unchanged.
proc lesson05d_prescale_inputs {path} {
    set h [open $path w];puts $h "pin\tdrivers"
    foreach cell [lsort [get_cells -hier -filter {REF_NAME==GTYE4_CHANNEL || REF_NAME==GTYE4_COMMON || REF_NAME==PCIE40E4}]] {
        foreach pin [lsort [get_pins -of_objects $cell -filter {DIRECTION==IN}]] {
            set nets [get_nets -quiet -segments -of_objects $pin]
            set drivers [get_pins -quiet -of_objects $nets -filter {DIRECTION==OUT}]
            puts $h "$pin\t[join [lsort -unique $drivers] ,]"
        }
    }
    # Include the core reference fabric clock at the wrapper boundary.
    set p [get_pins dma/sys_clk]
    puts $h "$p\t[join [lsort -unique [get_pins -of_objects [get_nets -segments -of_objects $p] -filter {DIRECTION==OUT}]] ,]"
    close $h
}
proc lesson05d_prescale_joined {left right} {
    set a [get_nets -segments -of_objects [get_pins $left]]
    foreach n [get_nets -segments -of_objects [get_pins $right]] {if {$n in $a} {return 1}}
    return 0
}
proc lesson05d_ref_prescale {out part base} {
    if {$part ne "xcku5p-ffvb676-1-i"} {error "Unverified target"}
    # Constant-net hierarchies can exceed Vivado's default 500-item Tcl display
    # limit. Keep complete collections for exact connectivity verification.
    set_param tcl.collectionResultDisplayLimit 0
    set out [file normalize $out];set reports [file join $out reports];file mkdir $reports
    if {![file exists [file join $out prescale_sim simulation_pass.txt]]} {error "Missing prescaler simulation acceptance"}
    open_checkpoint $base
    lesson05d_prescale_inputs [file join $reports functional_inputs_before.tsv]
    set zero [get_nets {<const0>}];set one [get_nets {<const1>}]
    if {[llength $zero]!=1 || [llength $one]!=1} {error "Missing root constants"}
    create_cell -reference BUFG_GT diagnostic_ref_div8
    set_property SIM_DEVICE ULTRASCALE_PLUS [get_cells diagnostic_ref_div8]
    foreach name {I CE CLR CEMASK CLRMASK} {
        set source [get_nets -of_objects [get_pins reference_monitor_buffer/$name]]
        connect_net -hierarchical -net $source -objects [get_pins diagnostic_ref_div8/$name]
    }
    foreach bit {0 1 2} {connect_net -hierarchical -net $one -objects [get_pins [format {diagnostic_ref_div8/DIV[%d]} $bit]]}
    set divided [create_net diagnostic_ref_clock_div8]
    connect_net -hierarchical -net $divided -objects [get_pins diagnostic_ref_div8/O]
    create_generated_clock -name diagnostic_ref_div8_clk -source [get_pins reference_input/ODIV2] -divide_by 8 [get_pins diagnostic_ref_div8/O]
    foreach bit {0 1 2 3 4 5 6 7} {
        set pin [get_pins [format {clock_monitor/ref_counter_reg[%d]/C} $bit]]
        disconnect_net -net [get_nets -of_objects $pin] -objects $pin
        connect_net -hierarchical -net $divided -objects $pin
    }
    set tap [get_nets -of_objects [get_pins {clock_monitor/ref_counter_reg[4]/Q}]]
    set pin [get_pins {clock_monitor/sample1_reg[0]/D}]
    disconnect_net -net [get_nets -of_objects $pin] -objects $pin
    connect_net -hierarchical -net $tap -objects $pin
    foreach {bit net} [list 0 $zero 1 $one] {
        set pin [get_pins [format {monitor/probe_in1[%d]} $bit]]
        disconnect_net -net [get_nets -of_objects $pin] -objects $pin
        connect_net -hierarchical -net $net -objects $pin
    }
    # Keep the new diagnostic clock within its source row. Do not rely on an
    # uninstantiated BUFG route-through to reach the old counter placement.
    set counters [get_cells -hier -filter {NAME =~ clock_monitor/ref_counter_reg* && IS_PRIMITIVE==1}]
    if {[llength $counters]!=8} {error "Expected eight reference counter FFs"}
    unplace_cell $counters
    set fixed [get_cells -hier -filter {IS_PRIMITIVE==1 && LOC!=""}]
    if {[llength $fixed]<10000} {error "Incomplete placement inventory"}
    set_property IS_LOC_FIXED true $fixed
    create_pblock diagnostic_ref_row
    resize_pblock [get_pblocks diagnostic_ref_row] -add {CLOCKREGION_X0Y0:CLOCKREGION_X3Y0}
    add_cells_to_pblock [get_pblocks diagnostic_ref_row] [concat $counters [get_cells diagnostic_ref_div8]]
    set_property IS_SOFT false [get_pblocks diagnostic_ref_row]
    place_design -directive Quick -no_psip -no_bufg_opt
    # Route only dirty/new connections; retain the accepted core clock tree.
    route_design
    foreach {cmd file} {report_timing_summary timing_routed.rpt check_timing check_timing_routed.rpt report_route_status route_status.rpt report_drc drc_routed.rpt report_cdc cdc_routed.rpt report_bus_skew bus_skew_routed.rpt report_utilization utilization_routed.rpt report_clocks clocks.rpt} {
        $cmd -file [file join $reports $file]
    }
    write_checkpoint -force [file join $out lesson05d_pcie_top_routed.dcp]
    close_project;open_checkpoint [file join $out lesson05d_pcie_top_routed.dcp]
    foreach name {I CE CLR CEMASK CLRMASK} {
        if {![lesson05d_prescale_joined diagnostic_ref_div8/$name reference_monitor_buffer/$name]} {error "Buffer input mismatch: $name"}
    }
    foreach bit {0 1 2} {
        set net [get_nets -of_objects [get_pins [format {diagnostic_ref_div8/DIV[%d]} $bit]]]
        set c [get_cells -of_objects [get_pins -of_objects $net -filter {DIRECTION==OUT}]]
        if {[llength $c]!=1 || [get_property REF_NAME $c] ne "VCC"} {error "Prescale DIV is not 111"}
    }
    foreach bit {0 1 2 3 4 5 6 7} {
        if {![lesson05d_prescale_joined diagnostic_ref_div8/O [format {clock_monitor/ref_counter_reg[%d]/C} $bit]]} {error "Counter clock not retained"}
    }
    if {![lesson05d_prescale_joined {clock_monitor/ref_counter_reg[4]/Q} {clock_monitor/sample1_reg[0]/D}]} {error "Counter tap not retained"}
    set clocks [get_clocks -of_objects [get_pins {clock_monitor/ref_counter_reg[0]/C}]]
    if {[llength $clocks]!=1 || abs([get_property PERIOD $clocks]-80.0)>0.001} {error "Expected /8 generated clock"}
    lesson05d_prescale_inputs [file join $reports functional_inputs_after.tsv]
    set h [open [file join $reports functional_inputs_before.tsv] r];set before [read $h];close $h
    set h [open [file join $reports functional_inputs_after.tsv] r];set after [read $h];close $h
    if {$before ne $after} {error "Functional GT/PCIe inputs changed"}
    foreach delay {max min} {
        if {[llength [get_timing_paths -quiet -delay_type $delay -slack_lesser_than 0 -max_paths 1]]} {error "Timing failed ($delay); do not generate/program diagnostic bitstream"}
    }
    write_debug_probes -force [file join $out lesson05d_pcie_top.ltx]
    write_bitstream -force [file join $out lesson05d_pcie_top.bit]
    puts "REF_PRESCALE_EXPERIMENT_COMPLETE"
}
