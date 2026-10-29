# Qualify SYS_CLK with an independent MMCM; do not drive functional logic from it.
# Spare PHY bit27=MMCM LOCKED, bit31=CLKINSTOPPED. Base is accepted df.
proc lesson05d_monitor_pll {out part base} {
    global repo_dir
    if {$part ne "xcku5p-ffvb676-1-i"} {error "Unverified target"}
    set_param tcl.collectionResultDisplayLimit 0
    source -notrace [file join $repo_dir tcl lesson05d_ref_prescale.tcl]
    set out [file normalize $out];set reports [file join $out reports];file mkdir $reports
    if {![file exists [file join $out monitor_pll_sim simulation_pass.txt]]} {error "MMCM simulation required"}
    open_checkpoint $base
    lesson05d_prescale_inputs [file join $reports functional_inputs_before.tsv]
    set zero [get_nets {<const0>}];set one [get_nets {<const1>}]
    set fixed [get_cells -hier -filter {IS_PRIMITIVE==1 && LOC!=""}]
    if {[llength $fixed]<10000} {error "Incomplete placement inventory"}
    set_property IS_LOC_FIXED true $fixed
    create_cell -reference MMCME4_ADV diagnostic_sysclk_mmcm
    set_property -dict {CLKIN1_PERIOD 10.0 CLKIN2_PERIOD 10.0 CLKFBOUT_MULT_F 10.0 DIVCLK_DIVIDE 1 CLKOUT0_DIVIDE_F 10.0 CLKOUT1_DIVIDE 10 CLKOUT2_DIVIDE 10 CLKOUT3_DIVIDE 10 CLKOUT4_DIVIDE 10 CLKOUT5_DIVIDE 10 CLKOUT6_DIVIDE 10 BANDWIDTH OPTIMIZED STARTUP_WAIT FALSE} [get_cells diagnostic_sysclk_mmcm]
    create_cell -reference BUFGCE diagnostic_sysclk_feedback
    set_property SIM_DEVICE ULTRASCALE_PLUS [get_cells diagnostic_sysclk_feedback]
    set sysclk [get_nets -of_objects [get_pins monitor_buffer/I]]
    connect_net -hierarchical -net $sysclk -objects [get_pins diagnostic_sysclk_mmcm/CLKIN1]
    set reset [get_nets -of_objects [get_pins {monitor/probe_out0[0]}]]
    set reset_protection [get_property DONT_TOUCH $reset]
    set_property DONT_TOUCH false $reset
    connect_net -hierarchical -net $reset -objects [get_pins diagnostic_sysclk_mmcm/RST]
    set_property DONT_TOUCH $reset_protection $reset
    foreach name {CDDCREQ CLKIN2 DCLK DEN DWE PSCLK PSEN PSINCDEC PWRDWN} {
        connect_net -hierarchical -net $zero -objects [get_pins diagnostic_sysclk_mmcm/$name]
    }
    foreach {name width} {DADDR 7 DI 16} {for {set bit 0} {$bit<$width} {incr bit} {
        connect_net -hierarchical -net $zero -objects [get_pins [format {diagnostic_sysclk_mmcm/%s[%d]} $name $bit]]
    }}
    connect_net -hierarchical -net $one -objects [get_pins diagnostic_sysclk_mmcm/CLKINSEL]
    connect_net -hierarchical -net $one -objects [get_pins diagnostic_sysclk_feedback/CE]
    set raw [create_net diagnostic_sysclk_feedback_raw]
    connect_net -hierarchical -net $raw -objects [get_pins {diagnostic_sysclk_mmcm/CLKFBOUT diagnostic_sysclk_feedback/I}]
    set fb [create_net diagnostic_sysclk_feedback_clock]
    connect_net -hierarchical -net $fb -objects [get_pins {diagnostic_sysclk_feedback/O diagnostic_sysclk_mmcm/CLKFBIN}]
    foreach {bit port} {27 LOCKED 31 CLKINSTOPPED} {
        set net [create_net diagnostic_sysclk_$port]
        connect_net -hierarchical -net $net -objects [get_pins diagnostic_sysclk_mmcm/$port]
        set sink [get_pins [format {phy_monitor/sample1_reg[%d]/D} $bit]]
        disconnect_net -net [get_nets -of_objects $sink] -objects $sink
        connect_net -hierarchical -net $net -objects $sink
    }
    foreach bit {0 1 2 3 4 5} {
        set p [get_pins [format {monitor/probe_in1[%d]} $bit]]
        disconnect_net -net [get_nets -of_objects $p] -objects $p
        if {$bit==5} {set net $one} else {set net $zero}
        connect_net -hierarchical -net $net -objects $p
    }
    place_design -directive Quick -no_psip -no_bufg_opt
    route_design
    foreach {cmd file} {report_timing_summary timing_routed.rpt check_timing check_timing_routed.rpt report_route_status route_status.rpt report_drc drc_routed.rpt report_cdc cdc_routed.rpt report_bus_skew bus_skew_routed.rpt report_utilization utilization_routed.rpt report_clocks clocks.rpt} {
        $cmd -file [file join $reports $file]
    }
    write_checkpoint -force [file join $out lesson05d_pcie_top_routed.dcp]
    close_project;open_checkpoint [file join $out lesson05d_pcie_top_routed.dcp]
    foreach {bit port} {27 LOCKED 31 CLKINSTOPPED} {
        if {![lesson05d_prescale_joined diagnostic_sysclk_mmcm/$port [format {phy_monitor/sample1_reg[%d]/D} $bit]]} {error "MMCM observer did not persist"}
    }
    if {![lesson05d_prescale_joined diagnostic_sysclk_mmcm/CLKIN1 monitor_buffer/I]} {error "MMCM source changed"}
    if {![lesson05d_prescale_joined diagnostic_sysclk_mmcm/RST {monitor/probe_out0[0]}]} {error "MMCM reset changed"}
    lesson05d_prescale_inputs [file join $reports functional_inputs_after.tsv]
    set h [open [file join $reports functional_inputs_before.tsv] r];set before [read $h];close $h
    set h [open [file join $reports functional_inputs_after.tsv] r];set after [read $h];close $h
    if {$before ne $after} {error "Functional GT/PCIe inputs changed"}
    foreach delay {max min} {if {[llength [get_timing_paths -quiet -delay_type $delay -slack_lesser_than 0 -max_paths 1]]} {error "Timing failed"}}
    set h [open [file join $reports verified_pins.tsv] w];puts $h "port\tpackage_pin"
    foreach p [get_ports] {puts $h "$p\t[get_property PACKAGE_PIN $p]"};close $h
    write_debug_probes -force [file join $out lesson05d_pcie_top.ltx]
    write_bitstream -force [file join $out lesson05d_pcie_top.bit]
    puts "MONITOR_PLL_EXPERIMENT_COMPLETE"
}
