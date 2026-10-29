# Independently generated Wizard IP; never copy or edit AMD-generated RTL.
proc lesson05e_gt_audit {out} {
    set_param tcl.collectionResultDisplayLimit 0
    if {[llength [get_cells -hier -filter {REF_NAME==PCIE40E4}]]} {error "Unexpected PCIe controller"}
    set channels [lsort [get_cells -hier -filter {REF_NAME==GTYE4_CHANNEL}]]
    set commons [get_cells -hier -filter {REF_NAME==GTYE4_COMMON}]
    if {[llength $channels]!=4 || [llength $commons]!=1} {error "Wrong GT population"}
    set h [open [file join $out reports primitive_audit.tsv] w];puts $h "object\tproperty\tvalue"
    set sites {}
    foreach cell $channels {
        set loc [get_property LOC $cell];lappend sites $loc
        puts $h "$cell\tLOC\t$loc"
        foreach pin {TXINHIBIT TXELECIDLE} {
            set net [get_nets -segments -of_objects [get_pins $cell/$pin]]
            set driver [get_cells -of_objects [get_pins -of_objects $net -filter {DIRECTION==OUT}]]
            if {[llength $driver]!=1 || [get_property REF_NAME $driver] ne "VCC"} {error "Transmitter not inhibited: $cell/$pin"}
            puts $h "$cell/$pin\tconstant\t1"
        }
        regexp {Y([0-9]+)$} $loc ignored y
        set lane [expr {7-$y}]
        foreach {pin signal} {GTYTXP pcie_tx_p GTYTXN pcie_tx_n GTYRXP pcie_rx_p GTYRXN pcie_rx_n} {
            set ports [get_ports -of_objects [get_nets -segments -of_objects [get_pins $cell/$pin]]]
            if {$ports ne [format {%s[%d]} $signal $lane]} {error "Connector lane mismatch: $cell/$pin -> $ports"}
            puts $h "$cell/$pin\tport\t$ports"
        }
    }
    if {[lsort $sites] ne {GTYE4_CHANNEL_X0Y4 GTYE4_CHANNEL_X0Y5 GTYE4_CHANNEL_X0Y6 GTYE4_CHANNEL_X0Y7}} {error "Wrong GT sites"}
    if {[get_property LOC $commons] ne "GTYE4_COMMON_X0Y1"} {error "Wrong common quad"}
    foreach property {LOC QPLL1_FBDIV QPLL1_REFCLK_DIV QPLL1CLKOUT_RATE} {
        puts $h "$commons\t$property\t[get_property $property $commons]"
    }
    foreach pin {GTREFCLK01 GTNORTHREFCLK01 GTSOUTHREFCLK01 QPLL1RESET QPLL1PD QPLL1LOCKDETCLK QPLL1REFCLKSEL[0] QPLL1REFCLKSEL[1] QPLL1REFCLKSEL[2]} {
        set p [get_pins [format {%s/%s} $commons $pin]]
        set drivers [get_pins -of_objects [get_nets -segments -of_objects $p] -filter {DIRECTION==OUT}]
        puts $h "$p\tdrivers\t[join [lsort -unique $drivers] ,]"
    }
    close $h
    set h [open [file join $out reports verified_pins.tsv] w];puts $h "port\tpackage_pin"
    foreach p [lsort [get_ports]] {puts $h "$p\t[get_property PACKAGE_PIN $p]"};close $h
}

proc lesson05e_gt_build {out part action} {
    global repo_dir
    if {$part ne "xcku5p-ffvb676-1-i" || $action ni {all simulate implement}} {error "Invalid independent GT build"}
    set out [file normalize $out]
    set lower_root [string tolower [string map {\\ /} $repo_dir]]
    set lower_out [string tolower [string map {\\ /} $out]]
    if {$lower_root eq $lower_out || [string first "$lower_root/" "$lower_out/"]==0} {error "External output required"}
    if {![file exists [file join $out inputs.json]]} {error "Freeze inputs using gt_isolation_manifest.py first"}
    file mkdir [file join $out reports]
    set project [file join $out vivado_project]
    if {[file exists [file join $project gt_isolation.xpr]]} {
        open_project [file join $project gt_isolation.xpr]
    } else {create_project gt_isolation $project -part $part}
    set_property target_language Verilog [current_project]
    foreach name {gt_isolation_reset.sv gt_isolation_clocking.sv gt_isolation_body.sv lesson05e_gt_top.sv pcie_phy_monitor.sv} {
        set path [file join $repo_dir rtl $name]
        if {![llength [get_files -quiet $path]]} {add_files -norecurse $path}
    }
    set path [file join $repo_dir constr lesson05e_gt_isolation.xdc]
    if {![llength [get_files -quiet $path]]} {add_files -fileset constrs_1 -norecurse $path}
    foreach name {tb_gt_isolation_reset.sv tb_gt_isolation_clocking.sv tb_gt_isolation_body.sv} {
        set path [file join $repo_dir sim $name]
        if {![llength [get_files -quiet $path]]} {add_files -fileset sim_1 -norecurse $path}
    }
    set gt_config {CONFIG.GT_TYPE GTY CONFIG.CHANNEL_ENABLE {X0Y4 X0Y5 X0Y6 X0Y7}
        CONFIG.TX_MASTER_CHANNEL X0Y4 CONFIG.RX_MASTER_CHANNEL X0Y4
        CONFIG.TX_LINE_RATE 8 CONFIG.TX_REFCLK_FREQUENCY 100 CONFIG.TX_PLL_TYPE QPLL1
        CONFIG.RX_LINE_RATE 8 CONFIG.RX_REFCLK_FREQUENCY 100 CONFIG.RX_PLL_TYPE QPLL1
        CONFIG.TX_DATA_ENCODING 8B10B CONFIG.RX_DATA_DECODING 8B10B
        CONFIG.TX_USER_DATA_WIDTH 32 CONFIG.TX_INT_DATA_WIDTH 40
        CONFIG.RX_USER_DATA_WIDTH 32 CONFIG.RX_INT_DATA_WIDTH 40
        CONFIG.FREERUN_FREQUENCY 100 CONFIG.LOCATE_RESET_CONTROLLER CORE
        CONFIG.LOCATE_TX_USER_CLOCKING CORE CONFIG.LOCATE_RX_USER_CLOCKING CORE
        CONFIG.LOCATE_USER_DATA_WIDTH_SIZING CORE
        CONFIG.ENABLE_OPTIONAL_PORTS {gtpowergood_out qpll1lock_out txresetdone_out rxresetdone_out txelecidle_in txinhibit_in}}
    set ip_dir [file join $project ip];file mkdir $ip_dir
    set single_config $gt_config
    set index [lsearch -exact $single_config CONFIG.CHANNEL_ENABLE]
    lset single_config [expr {$index+1}] X0Y4
    foreach {module name version config} [list lesson05e_gtwizard gtwizard_ultrascale 1.7 $gt_config \
        lesson05e_gtwizard_single_sim gtwizard_ultrascale 1.7 $single_config \
        lesson05e_gt_vio vio 3.0 {CONFIG.C_NUM_PROBE_IN 3 CONFIG.C_NUM_PROBE_OUT 1 CONFIG.C_PROBE_IN0_WIDTH 32 CONFIG.C_PROBE_IN1_WIDTH 96 CONFIG.C_PROBE_IN2_WIDTH 32 CONFIG.C_PROBE_OUT0_WIDTH 1 CONFIG.C_PROBE_OUT0_INIT_VAL 0x1} \
        lesson05e_gt_ila ila 6.2 {CONFIG.C_NUM_OF_PROBES 1 CONFIG.C_PROBE0_WIDTH 2 CONFIG.C_DATA_DEPTH 4096 CONFIG.C_TRIGIN_EN false CONFIG.C_TRIGOUT_EN false}] {
        if {![llength [get_ips -quiet $module]]} {
            create_ip -name $name -vendor xilinx.com -library ip -version $version -module_name $module -dir $ip_dir
            set_property -dict $config [get_ips $module]
        } else {
            foreach {key value} $config {if {![string equal -nocase [get_property $key [get_ips $module]] $value]} {error "Changed IP configuration: $module $key"}}
        }
        generate_target all [get_ips $module]
        set_property GENERATE_SYNTH_CHECKPOINT false [get_files [get_property IP_FILE [get_ips $module]]]
    }
    report_property [get_ips lesson05e_gtwizard] -file [file join $out reports gt_properties.rpt]
    # The single-channel IP is an elaboration target only. Exclude its source
    # and scoped XDC files from the four-channel hardware implementation.
    set single_files [get_files -all -filter {NAME =~ *lesson05e_gtwizard_single_sim*}]
    if {![llength $single_files]} {error "Single-channel simulation files not found"}
    foreach f $single_files {
        # The generated IP-XACT XML is a document with no synthesis flags.
        if {[lsearch -exact [list_property $f] USED_IN_SYNTHESIS]>=0} {
            set_property USED_IN_SYNTHESIS false $f
            set_property USED_IN_IMPLEMENTATION false $f
        }
    }
    set_property top lesson05e_gt_top [get_filesets sources_1]
    update_compile_order -fileset sources_1
    set simdir [file join $project gt_isolation.sim sim_1 behav xsim]
    if {$action in {all simulate}} {
        foreach {top marker expected} {tb_gt_isolation_reset reset_simulation_pass.txt {PASS gt_reset_checks=4} tb_gt_isolation_clocking clocking_simulation_pass.txt {PASS gt_clocking_checks=4}} {
            set path [file join $simdir $marker]
            if {[file exists $path]} {file delete $path}
            set_property top $top [get_filesets sim_1]
            set_property xsim.simulate.runtime 0us [get_filesets sim_1]
            launch_simulation -simset sim_1 -mode behavioral
            run all
            close_sim
            if {![file exists $path]} {error "Simulation did not pass: $top"}
            set h [open $path r];set result [string trim [read $h]];close $h
            if {$result ne $expected} {error "Unexpected simulation marker: $result"}
            file copy -force $path [file join $out $marker]
            puts $result
        }
        # Even one real GT model exceeds BASIC's 50000-instance runtime limit.
        # Compile/elaborate it, but explicitly do not claim dynamic simulation.
        set_property top tb_gt_isolation_body [get_filesets sim_1]
        launch_simulation -simset sim_1 -mode behavioral -step compile
        launch_simulation -simset sim_1 -mode behavioral -step elaborate
        file copy -force [file join $simdir elaborate.log] [file join $out reports gt_single_elaboration.log]
        set h [open [file join $out gt_elaboration_only.txt] w]
        puts $h "GT_SINGLE_ELABORATION_ONLY runtime_not_run=BASIC_50000_limit";close $h
    }
    foreach marker {reset_simulation_pass.txt clocking_simulation_pass.txt gt_elaboration_only.txt} {
        if {![file exists [file join $out $marker]]} {error "Simulation required before implementation"}
    }
    if {$action eq "simulate"} {puts GT_ISOLATION_SIMULATION_COMPLETE;return}
    synth_design -top lesson05e_gt_top -part $part
    opt_design
    place_design
    route_design
    set reports [file join $out reports]
    foreach {cmd file} {report_timing_summary timing_routed.rpt check_timing check_timing_routed.rpt report_route_status route_status.rpt report_drc drc_routed.rpt report_bus_skew bus_skew_routed.rpt report_utilization utilization_routed.rpt report_clocks clocks.rpt} {$cmd -file [file join $reports $file]}
    report_cdc -details -no_waiver -file [file join $reports cdc_no_waiver.rpt]
    report_waivers -file [file join $reports vendor_waivers.rpt]
    lesson05e_gt_audit $out
    foreach delay {max min} {if {[llength [get_timing_paths -quiet -delay_type $delay -slack_lesser_than 0 -max_paths 1]]} {error "Timing failed; no GT bitstream"}}
    write_checkpoint -force [file join $out lesson05e_gt_top_routed.dcp]
    write_debug_probes -force [file join $out lesson05e_gt_top.ltx]
    write_bitstream -force [file join $out lesson05e_gt_top.bit]
    puts GT_ISOLATION_IMPLEMENTATION_COMPLETE
}
