# Invoked through tcl/build.tcl. Build outputs and generated AMD IP stay external.
proc lesson05d_prepare {output_dir target_part {lanes 8} {training_debug 0} {phy_debug 0} {lane_reversal true}} {
    global repo_dir
    if {$lanes ni {4 8}} {error "Unsupported PCIe width"}
    if {$training_debug && $lanes!=4} {error "Training diagnostic requires x4"}
    if {$phy_debug && !$training_debug} {error "PHY diagnostic requires training monitor"}
    if {$lane_reversal ni {true false}} {error "Invalid lane reversal intent"}
    set ::l5d_training_debug $training_debug
    set ::l5d_lanes $lanes
    set ::l5d_top [expr {$lanes==4 ? "lesson05d_pcie_x4_top" : "lesson05d_pcie_top"}]
    if {$training_debug} {set ::l5d_top lesson05d_pcie_training_top}
    if {$phy_debug} {set ::l5d_top lesson05d_pcie_phy_top}
    set ::l5d_build [file normalize $output_dir]
    set root [string tolower [string map {\\ /} $repo_dir]]
    set out [string tolower [string map {\\ /} $::l5d_build]]
    if {$root eq $out || [string first "$root/" "$out/"]==0} {error "External build directory required"}
    if {$target_part ne "xcku5p-ffvb676-1-i"} {error "Unverified board target"}
    if {[current_project -quiet] ne ""} {error "Close current project first"}
    set project_dir [file join $::l5d_build vivado_project]
    set xpr [file join $project_dir lesson05d_pcie.xpr]
    if {[file exists $xpr]} {open_project $xpr} else {create_project lesson05d_pcie $project_dir -part $target_part}
    if {[get_property PART [current_project]] ne $target_part} {error "Wrong existing project part"}
    if {[info exists ::reference_ip_cache] && $::reference_ip_cache ne ""} {
        if {![file isdirectory $::reference_ip_cache]} {error "Missing explicitly selected IP cache"}
        config_ip_cache -use_cache_location [file normalize $::reference_ip_cache]
        set_property IP_CACHE_PERMISSIONS read [current_project]
    }
    set rtl_names {dma_pattern_source.sv pcie_test_endpoint.sv pcie_clock_monitor.sv lesson05d_pcie_top.sv}
    if {$lanes==4} {lappend rtl_names lesson05d_pcie_x4_top.sv}
    if {$training_debug} {lappend rtl_names pcie_training_monitor.sv lesson05d_pcie_training_top.sv}
    if {$phy_debug} {lappend rtl_names pcie_phy_monitor.sv lesson05d_pcie_phy_top.sv}
    foreach name $rtl_names {
        set path [file join $repo_dir rtl $name]
        if {![llength [get_files -quiet $path]]} {add_files -norecurse $path}
    }
    set constraint [expr {$lanes==4 ? "lesson05d_fnic_ku5p_x4.xdc" : "lesson05d_fnic_ku5p.xdc"}]
    set path [file join $repo_dir constr $constraint]
    if {![llength [get_files -quiet $path]]} {add_files -fileset constrs_1 -norecurse $path}
    if {$phy_debug} {
        set path [file join $repo_dir constr lesson05d_phy_monitor.xdc]
        if {![llength [get_files -quiet $path]]} {add_files -fileset constrs_1 -norecurse $path}
    }
    set ip_dir [file join $project_dir ip];file mkdir $ip_dir
    set frequency [expr {$lanes==4 ? 125 : 250}]
    set dma_config [list CONFIG.mode_selection Advanced CONFIG.pl_link_cap_max_link_width X$lanes \
        CONFIG.pl_link_cap_max_link_speed 8.0_GT/s CONFIG.axi_data_width 256_bit CONFIG.axisten_freq $frequency \
        CONFIG.xdma_axi_intf_mm AXI_Stream CONFIG.axilite_master_en true \
        CONFIG.axilite_master_scale Kilobytes CONFIG.axilite_master_size 4 CONFIG.ref_clk_freq 100_MHz \
        CONFIG.en_gt_selection true CONFIG.select_quad GTY_Quad_225 CONFIG.enable_lane_reversal $lane_reversal \
        CONFIG.xdma_rnum_chnl 1 CONFIG.xdma_wnum_chnl 1 CONFIG.en_debug_ports false CONFIG.ext_sys_clk_bufg true]
    lappend dma_config CONFIG.enable_pcie_debug_ports [expr {$training_debug ? "True" : "False"}]
    lappend dma_config CONFIG.en_transceiver_status_ports [expr {$phy_debug ? "true" : "false"}]
    set outputs [expr {$lanes==4 ? 1 : 0}]
    set inputs [expr {$phy_debug ? 5 : ($training_debug ? 4 : 2)}]
    set vio_config [list CONFIG.C_NUM_PROBE_IN $inputs CONFIG.C_NUM_PROBE_OUT $outputs \
        CONFIG.C_PROBE_IN0_WIDTH 8 CONFIG.C_PROBE_IN1_WIDTH 32]
    if {$outputs} {lappend vio_config CONFIG.C_PROBE_OUT0_WIDTH 1 CONFIG.C_PROBE_OUT0_INIT_VAL 0x1}
    if {$training_debug} {
        lappend vio_config CONFIG.C_PROBE_IN2_WIDTH 128 CONFIG.C_PROBE_IN3_WIDTH 1
        set_property XPM_LIBRARIES XPM_CDC [current_project]
    }
    if {$phy_debug} {lappend vio_config CONFIG.C_PROBE_IN4_WIDTH 144}
    set hook [file join $repo_dir tcl lesson05d_synth_settings.tcl]
    if {![llength [get_files -quiet $hook]]} {add_files -fileset utils_1 -norecurse $hook}
    foreach {module ipname ver config} [list lesson05d_xdma xdma 4.2 $dma_config lesson05d_vio vio 3.0 $vio_config] {
        if {![llength [get_ips -quiet $module]]} {
            create_ip -name $ipname -vendor xilinx.com -library ip -version $ver -module_name $module -dir $ip_dir
            set_property -dict $config [get_ips $module]
        } else {
            foreach {key value} $config {
                if {![string equal -nocase [get_property $key [get_ips $module]] $value]} {error "IP config mismatch $module $key"}
            }
        }
        generate_target all [get_ips $module]
        if {![llength [get_runs -quiet ${module}_synth_1]]} {
            create_ip_run [get_files [get_property IP_FILE [get_ips $module]]]
        }
        set_property STEPS.SYNTH_DESIGN.TCL.PRE [file join $repo_dir tcl lesson05d_synth_settings.tcl] [get_runs ${module}_synth_1]
    }
    set_property STEPS.SYNTH_DESIGN.TCL.PRE [file join $repo_dir tcl lesson05d_synth_settings.tcl] [get_runs synth_1]
    set_property top $::l5d_top [get_filesets sources_1]
    update_compile_order -fileset sources_1
    file mkdir [file join $::l5d_build reports]
    report_property [get_ips lesson05d_xdma] -file [file join $::l5d_build reports xdma_properties.txt]
    report_ip_status -file [file join $::l5d_build reports ip_status.rpt]
    puts "LESSON05D_PREPARED=$xpr"
}
proc lesson05d_accept_simulation {} {
    set marker [file join $::l5d_build application_test simulation_pass.txt]
    if {![file exists $marker]} {error "No application PASS"}
    set h [open $marker r];set value [string trim [read $h]];close $h
    if {![string match "PASS packets=29 beats=3712 *" $value]} {error "Unexpected application result"}
    file copy -force $marker [file join $::l5d_build simulation_pass.txt]
    puts "LESSON05D_APPLICATION=$value"
}
proc lesson05d_start_implementation {} {
    if {![file exists [file join $::l5d_build simulation_pass.txt]]} {error "Accept application simulation first"}
    reset_run synth_1
    launch_runs impl_1 -to_step write_bitstream -jobs 2
}
proc lesson05d_collect_implementation {} {
    if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {error "Implementation is not complete"}
    open_run impl_1
    if {[llength [get_cells -hier -quiet -filter {IS_BLACKBOX==1}]]} {error "Unresolved black boxes"}
    set reports [file join $::l5d_build reports]
    report_utilization -file [file join $reports utilization_routed.rpt]
    report_timing_summary -file [file join $reports timing_routed.rpt]
    check_timing -verbose -file [file join $reports check_timing_routed.rpt]
    report_route_status -file [file join $reports route_status.rpt]
    report_bus_skew -file [file join $reports bus_skew_routed.rpt]
    report_drc -file [file join $reports drc_routed.rpt]
    report_cdc -details -file [file join $reports cdc_routed.rpt]
    report_io -file [file join $reports io_routed.rpt]
    set pin_handle [open [file join $reports verified_pins.tsv] w]
    puts $pin_handle "port\tpackage_pin"
    set expected_pins [list SYS_CLK AB21 LED1 AF14 LED2 AF15 pcie_refclk_p AB7 pcie_refclk_n AB6 pcie_reset_n T19]
    foreach {signal values} {pcie_rx_p {P2 T2 V2 Y2 AB2 AD2 AE4 AF2} pcie_rx_n {P1 T1 V1 Y1 AB1 AD1 AE3 AF1} pcie_tx_p {R5 U5 W5 AA5 AC5 AD7 AE9 AF7} pcie_tx_n {R4 U4 W4 AA4 AC4 AD6 AE8 AF6}} {
        set lane 0
        foreach pin [lrange $values 0 [expr {$::l5d_lanes-1}]] {lappend expected_pins [format {%s[%d]} $signal $lane] $pin;incr lane}
    }
    foreach {name pin} $expected_pins {
        set actual [get_property PACKAGE_PIN [get_ports $name]]
        if {$actual ne $pin} {close $pin_handle;error "Pin mismatch $name $actual != $pin"}
        puts $pin_handle "$name\t$actual"
    }
    close $pin_handle
    write_checkpoint -force [file join $::l5d_build lesson05d_pcie_top_routed.dcp]
    write_debug_probes -force [file join $::l5d_build lesson05d_pcie_top.ltx]
    set bit [file join $::l5d_build vivado_project lesson05d_pcie.runs impl_1 ${::l5d_top}.bit]
    if {![file exists $bit]} {error "Missing bitstream"}
    file copy -force $bit [file join $::l5d_build lesson05d_pcie_top.bit]
    puts "LESSON05D_IMPLEMENTED"
}
