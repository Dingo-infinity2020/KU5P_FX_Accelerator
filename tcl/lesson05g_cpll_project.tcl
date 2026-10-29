# Standalone one-channel CPLL bring-up. Source defines procedures only.
proc lesson05g_gt_input_drivers {channel} {
    set result [dict create]
    foreach pin [lsort [get_pins -of_objects $channel -filter {DIRECTION==IN}]] {
        set nets [get_nets -segments -of_objects $pin]
        set drivers {}
        foreach driver [get_pins -quiet -leaf -of_objects $nets -filter {DIRECTION==OUT}] {lappend drivers "primitive:$driver"}
        foreach port [get_ports -quiet -of_objects $nets -filter {DIRECTION==IN}] {lappend drivers "port:$port"}
        dict set result $pin [lsort -unique $drivers]
    }
    return $result
}
proc lesson05g_gt_hier_drivers {channel} {
    set result [dict create]
    foreach pin [lsort [get_pins -of_objects $channel -filter {DIRECTION==IN}]] {
        dict set result $pin [lsort -unique [get_pins -quiet -of_objects [get_nets -segments -of_objects $pin] -filter {DIRECTION==OUT}]]
    }
    return $result
}
proc lesson05g_write_drivers {path inputs} {
    set h [open $path w];puts $h "pin\tdrivers"
    dict for {pin drivers} $inputs {puts $h "$pin\t[join $drivers ,]"};close $h
}
proc lesson05g_attach_controls {out} {
    set_param tcl.collectionResultDisplayLimit 0
    set channel [get_cells -hier -filter {REF_NAME==GTYE4_CHANNEL}]
    if {[llength $channel]!=1} {error "Expected one GTY channel"}
    set before [lesson05g_gt_input_drivers $channel]
    lesson05g_write_drivers [file join $out reports gt_inputs_before.tsv] $before
    set hier_before [lesson05g_gt_hier_drivers $channel]
    lesson05g_write_drivers [file join $out reports gt_hier_inputs_before.tsv] $hier_before
    # Explicit read-only loads, never changes the reset helper or GT controls.
    foreach {source destination} {
        CPLLRESET {body/diagnostics/control_meta_reg[0]/D}
        CPLLPD {body/diagnostics/control_meta_reg[1]/D}
    } {
        set from [get_pins [format {%s/%s} $channel $source]]
        set to [get_pins -quiet $destination]
        if {[llength $from]!=1 || [llength $to]!=1} {error "Missing reserved control observer: $destination"}
        set old [get_nets -of_objects $to]
        if {[llength $old]} {disconnect_net -net $old -objects $to}
        connect_net -hierarchical -net [get_nets -of_objects $from] -objects $to
    }
    set to [get_pins {body/diagnostics/control_meta_reg[2]/D}]
    set old [get_nets -of_objects $to]
    if {[llength $old]} {disconnect_net -net $old -objects $to}
    set vcc [get_cells -hier -filter {REF_NAME==VCC}]
    if {![llength $vcc]} {error "No VCC net"}
    set net [get_nets -of_objects [get_pins -of_objects [lindex $vcc 0] -filter {DIRECTION==OUT}]]
    connect_net -hierarchical -net $net -objects $to
    set after [lesson05g_gt_input_drivers $channel]
    lesson05g_write_drivers [file join $out reports gt_inputs_after.tsv] $after
    set hier_after [lesson05g_gt_hier_drivers $channel]
    lesson05g_write_drivers [file join $out reports gt_hier_inputs_after.tsv] $hier_after
    set h [open [file join $out reports hierarchical_alias_changes.tsv] w];puts $h "pin\tremoved_hierarchical_aliases\tadded_hierarchical_aliases"
    dict for {pin previous} $hier_before {
        set next [dict get $hier_after $pin]
        if {$previous ne $next} {
            set removed {};set added {}
            foreach name $previous {if {[lsearch -exact $next $name]<0} {lappend removed $name}}
            foreach name $next {if {[lsearch -exact $previous $name]<0} {lappend added $name}}
            puts $h "$pin\t[join $removed ,]\t[join $added ,]"
        }
    };close $h
    if {$before ne $after} {error "Functional primitive/port GT input driver changed while attaching observers"}
}
proc lesson05g_cpll_audit {directory} {
    file mkdir $directory
    set_param tcl.collectionResultDisplayLimit 0
    set channels [get_cells -hier -filter {REF_NAME==GTYE4_CHANNEL}]
    if {[llength $channels]!=1 || [llength [get_cells -hier -quiet -filter {REF_NAME==GTYE4_COMMON || REF_NAME==PCIE40E4}]]} {error "Unexpected serial core population"}
    set channel [lindex $channels 0]
    if {[get_property LOC $channel] ne "GTYE4_CHANNEL_X0Y4"} {error "Wrong CPLL channel"}
    set h [open [file join $directory primitive_audit.tsv] w];puts $h "object\tproperty\tvalue"
    foreach property {LOC CPLL_FBDIV CPLL_FBDIV_45 CPLL_REFCLK_DIV TXOUT_DIV RXOUT_DIV} {
        puts $h "$channel\t$property\t[get_property $property $channel]"
    }
    foreach name {TXINHIBIT TXELECIDLE} {
        set drivers [get_cells -of_objects [get_pins -of_objects [get_nets -segments -of_objects [get_pins $channel/$name]] -filter {DIRECTION==OUT}]]
        if {[llength $drivers]!=1 || [get_property REF_NAME $drivers] ne "VCC"} {error "Transmitter enable is not permanently inhibited"}
        puts $h "$channel/$name\tconstant\t1"
    }
    foreach {pin port} {GTYTXP pcie_tx_p GTYTXN pcie_tx_n GTYRXP pcie_rx_p GTYRXN pcie_rx_n} {
        set ports [get_ports -of_objects [get_nets -segments -of_objects [get_pins $channel/$pin]]]
        if {$ports ne $port} {error "Wrong single-lane connector map"}
        puts $h "$channel/$pin\tport\t$ports"
    }
    close $h
    set h [open [file join $directory pins.tsv] w];puts $h "port\tpin\tiostandard\tdirection"
    foreach {name pin direction ios} {SYS_CLK AB21 IN LVCMOS18 pcie_refclk_p AB7 IN {} pcie_refclk_n AB6 IN {} pcie_reset_n T19 IN LVCMOS12 pcie_rx_p Y2 IN {} pcie_rx_n Y1 IN {} pcie_tx_p AA5 OUT {} pcie_tx_n AA4 OUT {} LED1 AF14 OUT LVCMOS33 LED2 AF15 OUT LVCMOS33} {
        set p [get_ports $name]
        if {[get_property PACKAGE_PIN $p] ne $pin || [get_property DIRECTION $p] ne $direction} {error "Board pin mismatch: $name"}
        if {$ios ne "" && [get_property IOSTANDARD $p] ne $ios} {error "I/O voltage mismatch: $name"}
        puts $h "$name\t$pin\t[get_property IOSTANDARD $p]\t$direction"
    };close $h
    set h [open [file join $directory control_observers.tsv] w];puts $h "control\tobserver\tactual_drivers"
    foreach {control destination} {CPLLRESET {body/diagnostics/control_meta_reg[0]/D} CPLLPD {body/diagnostics/control_meta_reg[1]/D}} {
        set from [get_pins $channel/$control];set to [get_pins $destination]
        set actual [lsort -unique [get_pins -of_objects [get_nets -segments -of_objects $from] -filter {DIRECTION==OUT}]]
        set observed [lsort -unique [get_pins -of_objects [get_nets -segments -of_objects $to] -filter {DIRECTION==OUT}]]
        if {![llength $actual] || $actual ne $observed} {error "Control observer disconnected"}
        set cell [get_cells -of_objects $to]
        if {![get_property ASYNC_REG $cell]} {error "Control observer is not a synchronizer"}
        puts $h "$control\t$destination\t[join $actual ,]"
    }
    set drivers [get_cells -of_objects [get_pins -of_objects [get_nets -segments -of_objects [get_pins {body/diagnostics/control_meta_reg[2]/D}]] -filter {DIRECTION==OUT}]]
    if {[llength $drivers]!=1 || [get_property REF_NAME $drivers] ne "VCC"} {error "Hardware control observations not qualified"}
    puts $h "VALID\tbody/diagnostics/control_meta_reg\[2\]/D\tVCC";close $h
    set h [open [file join $directory reference_route.tsv] w];puts $h "object\tproperty\tvalue"
    set ibuf [get_cells body/reference_input];set net [get_nets -of_objects [get_pins $ibuf/O]]
    puts $h "$ibuf\tLOC\t[get_property LOC $ibuf]"
    foreach property {ROUTE_STATUS ROUTE} {puts $h "$net\t$property\t[get_property $property $net]"}
    puts $h "$net\tPIPS\t[get_pips -of_objects $net]"
    set pin [get_pins $channel/GTREFCLK0]
    puts $h "$pin\tBEL_PIN\t[get_bel_pins -of_objects $pin]"
    puts $h "$pin\tSITE_PIN\t[get_site_pins -of_objects $pin]"
    close $h
}
proc lesson05g_cpll_build {out part action} {
    global repo_dir
    if {$part ne "xcku5p-ffvb676-1-i" || $action ni {all simulate implement}} {error "Invalid CPLL profile"}
    set out [file normalize $out]
    set root_guard [string tolower [string map {\\ /} $repo_dir]]
    set out_guard [string tolower [string map {\\ /} $out]]
    if {$root_guard eq $out_guard || [string first "$root_guard/" "$out_guard/"]==0} {error "External build required"}
    if {![file exists [file join $out inputs.json]]} {error "Freeze CPLL sources first"}
    file mkdir [file join $out reports]
    set project [file join $out vivado_project]
    if {[file exists [file join $project cpll_board.xpr]]} {open_project [file join $project cpll_board.xpr]} else {create_project cpll_board $project -part $part}
    set_property XPM_LIBRARIES {XPM_CDC} [current_project]
    foreach name {lesson05g_cpll_top.sv lesson05g_cpll_body.sv cpll_diagnostics.sv gt_isolation_clocking.sv pcie_phy_monitor.sv} {
        set path [file join $repo_dir rtl $name]
        if {![llength [get_files -quiet $path]]} {add_files -norecurse $path}
    }
    set path [file join $repo_dir constr lesson05g_cpll.xdc]
    if {![llength [get_files -quiet $path]]} {add_files -fileset constrs_1 -norecurse $path}
    set path [file join $repo_dir sim tb_cpll_board.sv]
    if {![llength [get_files -quiet $path]]} {add_files -fileset sim_1 -norecurse $path}
    set ip_dir [file join $project ip];file mkdir $ip_dir
    set gt_config {CONFIG.GT_TYPE GTY CONFIG.CHANNEL_ENABLE X0Y4 CONFIG.TX_MASTER_CHANNEL X0Y4 CONFIG.RX_MASTER_CHANNEL X0Y4
        CONFIG.TX_LINE_RATE 5 CONFIG.RX_LINE_RATE 5 CONFIG.TX_REFCLK_FREQUENCY 100 CONFIG.RX_REFCLK_FREQUENCY 100
        CONFIG.TX_PLL_TYPE CPLL CONFIG.RX_PLL_TYPE CPLL CONFIG.TX_DATA_ENCODING 8B10B CONFIG.RX_DATA_DECODING 8B10B
        CONFIG.TX_USER_DATA_WIDTH 32 CONFIG.TX_INT_DATA_WIDTH 40 CONFIG.RX_USER_DATA_WIDTH 32 CONFIG.RX_INT_DATA_WIDTH 40
        CONFIG.FREERUN_FREQUENCY 100 CONFIG.LOCATE_RESET_CONTROLLER CORE CONFIG.LOCATE_TX_USER_CLOCKING CORE
        CONFIG.LOCATE_RX_USER_CLOCKING CORE CONFIG.ENABLE_OPTIONAL_PORTS {cplllock_out gtpowergood_out txelecidle_in txinhibit_in}}
    foreach {module ip version config} [list lesson05g_cpll_gt gtwizard_ultrascale 1.7 $gt_config \
        lesson05g_cpll_vio vio 3.0 {CONFIG.C_NUM_PROBE_IN 5 CONFIG.C_NUM_PROBE_OUT 1 CONFIG.C_PROBE_IN0_WIDTH 32 CONFIG.C_PROBE_IN1_WIDTH 96 CONFIG.C_PROBE_IN2_WIDTH 32 CONFIG.C_PROBE_IN3_WIDTH 32 CONFIG.C_PROBE_IN4_WIDTH 128 CONFIG.C_PROBE_OUT0_WIDTH 1 CONFIG.C_PROBE_OUT0_INIT_VAL 0x1} \
        lesson05g_cpll_ila ila 6.2 {CONFIG.C_NUM_OF_PROBES 2 CONFIG.C_PROBE0_WIDTH 32 CONFIG.C_PROBE1_WIDTH 128 CONFIG.C_DATA_DEPTH 8192}] {
        if {![llength [get_ips -quiet $module]]} {
            create_ip -name $ip -vendor xilinx.com -library ip -version $version -module_name $module -dir $ip_dir
            set_property -dict $config [get_ips $module]
        } else {
            foreach {key value} $config {if {![string equal -nocase [get_property $key [get_ips $module]] $value]} {error "Changed IP configuration: $module $key"}}
        }
        generate_target all [get_ips $module]
        set_property GENERATE_SYNTH_CHECKPOINT false [get_files [get_property IP_FILE [get_ips $module]]]
    }
    report_property [get_ips lesson05g_cpll_gt] -file [file join $out reports gt_properties.rpt]
    set_property top lesson05g_cpll_top [get_filesets sources_1]
    set marker [file join $project cpll_board.sim sim_1 behav xsim cpll_board_pass.txt]
    if {$action in {all simulate}} {
        if {[file exists $marker]} {file delete $marker}
        set_property top tb_cpll_board [get_filesets sim_1]
        set_property xsim.simulate.runtime 0us [get_filesets sim_1]
        launch_simulation -simset sim_1 -mode behavioral
        run all;close_sim
        if {![file exists $marker]} {error "CPLL dynamic simulation did not finish successfully"}
        set h [open $marker r];set result [string trim [read $h]];close $h
        if {$result ne "PASS cpll_board_checks=12"} {error "Wrong dynamic PASS result"}
        file copy -force $marker [file join $out cpll_board_pass.txt]
    }
    if {![file exists [file join $out cpll_board_pass.txt]]} {error "Dynamic simulation required"}
    if {$action eq "simulate"} {puts CPLL_BOARD_SIMULATION_COMPLETE;return}
    synth_design -top lesson05g_cpll_top -part $part
    lesson05g_attach_controls $out
    opt_design;place_design;route_design
    set reports [file join $out reports]
    foreach {cmd file} {report_timing_summary timing.rpt check_timing check_timing.rpt report_route_status route.rpt report_drc drc.rpt report_bus_skew bus_skew.rpt report_utilization utilization.rpt report_clocks clocks.rpt} {$cmd -file [file join $reports $file]}
    report_cdc -details -no_waiver -file [file join $reports cdc.rpt]
    report_waivers -file [file join $reports vendor_waivers.rpt]
    lesson05g_cpll_audit [file join $out reports]
    foreach delay {max min} {if {[llength [get_timing_paths -quiet -delay_type $delay -slack_lesser_than 0 -max_paths 1]]} {error "Timing failed"}}
    write_checkpoint -force [file join $out lesson05g_cpll_top_routed.dcp]
    write_debug_probes -force [file join $out lesson05g_cpll_top.ltx]
    write_bitstream -force [file join $out lesson05g_cpll_top.bit]
    close_project
    open_checkpoint [file join $out lesson05g_cpll_top_routed.dcp]
    lesson05g_cpll_audit [file join $out reopened_audit]
    close_design
    puts CPLL_BOARD_BUILD_COMPLETE
}
