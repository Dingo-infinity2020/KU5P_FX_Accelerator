# Fresh HDL build. Generated vendor RTL is never edited.
proc lesson05i_drivers {path} {
    set h [open $path w];puts $h "pin\tprimitive_or_top_drivers"
    foreach cell [lsort [get_cells -hier -filter {REF_NAME==GTYE4_CHANNEL || REF_NAME==GTYE4_COMMON || REF_NAME==PCIE40E4}]] {
        foreach pin [lsort [get_pins -of_objects $cell -filter {DIRECTION==IN}]] {
            set nets [get_nets -segments -of_objects $pin];set drivers {}
            foreach p [get_pins -quiet -leaf -of_objects $nets -filter {DIRECTION==OUT}] {lappend drivers "primitive:$p"}
            foreach p [get_ports -quiet -of_objects $nets -filter {DIRECTION==IN}] {lappend drivers "port:$p"}
            puts $h "$pin\t[join [lsort -unique $drivers] ,]"
        }
    };close $h
}
proc lesson05i_observer_map {} {
    set result [dict create]
    set fields {GTPOWERGOOD CPLLLOCK TXRESETDONE RXRESETDONE TXPMARESETDONE RXPMARESETDONE RXELECIDLE RXVALID RXCOMMADET RXCDRLOCK TXELECIDLE TXINHIBIT CPLLRESET CPLLPD}
    set channels [get_cells -hier -filter {REF_NAME==GTYE4_CHANNEL}]
    if {[llength $channels]!=4} {error "Expected four physical GTY channels"}
    foreach channel $channels {
        set loc [get_property LOC $channel]
        if {![regexp {^GTYE4_CHANNEL_X0Y([4-7])$} $loc -> y]} {error "Wrong channel location $loc"}
        set lane [expr {$y-4}];set group 0
        foreach field $fields {
            dict set result [expr {4*$group+$lane}] $channel/$field;incr group
        }
    }
    set common [get_cells -hier -filter {REF_NAME==GTYE4_COMMON}]
    if {[llength $common]!=1} {error "Expected one PCIe common"}
    set loc [get_property LOC $common]
    if {$loc ne "" && $loc ne "GTYE4_COMMON_X0Y1"} {error "Wrong placed PCIe common"}
    # QPLL reset/PD are combinational in this IP. Do not add asynchronous
    # observers that create CDC-10 or pretend their unobserved bits are zero.
    foreach {bit field} {56 QPLL1LOCK 59 QPLL0LOCK} {dict set result $bit $common/$field}
    dict set result 63 VCC
    return $result
}
proc lesson05i_attach_observers {out} {
    lesson05i_drivers [file join $out reports functional_inputs_before.tsv]
    dict for {bit source} [lesson05i_observer_map] {
        set sink [get_pins [format {diagnostics/raw_meta_reg[%d]/D} $bit]]
        if {[llength $sink]!=1} {error "Missing retained observer bit $bit"}
        disconnect_net -net [get_nets -of_objects $sink] -objects $sink
        if {$source eq "VCC"} {set net [get_nets {<const1>}]} else {
            set p [get_pins $source]
            set net [get_nets -of_objects $p]
            if {![llength $net]} {
                set net [create_net [format {boot_raw_%d} $bit]]
                connect_net -hierarchical -net $net -objects $p
            }
        }
        connect_net -hierarchical -net $net -objects $sink
    }
    lesson05i_drivers [file join $out reports functional_inputs_after.tsv]
    set h [open [file join $out reports functional_inputs_before.tsv]];set before [read $h];close $h
    set h [open [file join $out reports functional_inputs_after.tsv]];set after [read $h];close $h
    if {$before ne $after} {error "Observer attachment altered functional GT/PCIe input drivers"}
}
proc lesson05i_audit {directory {reset_pin {reset_bridge/endpoint_pipe_reg[1]/Q}}} {
    file mkdir $directory
    set common [get_cells -hier -filter {REF_NAME==GTYE4_COMMON}]
    if {[llength $common]!=1 || [get_property LOC $common] ne "GTYE4_COMMON_X0Y1"} {error "Final common placement is incorrect"}
    set h [open [file join $directory observers.tsv] w];puts $h "bit\tprimitive_pin\tobserver\tleaf_drivers"
    dict for {bit source} [lesson05i_observer_map] {
        set sink [get_pins [format {diagnostics/raw_meta_reg[%d]/D} $bit]]
        set nets [get_nets -segments -of_objects $sink]
        set drivers [lsort -unique [get_pins -leaf -of_objects $nets -filter {DIRECTION==OUT}]]
        if {$source eq "VCC"} {
            set cells [get_cells -of_objects $drivers]
            if {[llength $cells]!=1 || [get_property REF_NAME $cells] ne "VCC"} {error "Observer-valid is not VCC"}
        } else {
            set expected [lsort -unique [get_pins -leaf -of_objects [get_nets -segments -of_objects [get_pins $source]] -filter {DIRECTION==OUT}]]
            if {![llength $drivers] || $expected ne $drivers} {error "Disconnected observer $bit"}
        }
        foreach stage {raw_meta raw_sync} {
            if {![get_property ASYNC_REG [get_cells [format {diagnostics/%s_reg[%d]} $stage $bit]]]} {error "Missing ASYNC_REG"}
        }
        set second [get_pins [format {diagnostics/raw_sync_reg[%d]/D} $bit]]
        set first [get_pins [format {diagnostics/raw_meta_reg[%d]/Q} $bit]]
        if {![llength [get_nets -segments -of_objects $first]] ||
            [get_nets -of_objects $first] ne [get_nets -of_objects $second]} {error "Observer second stage disconnected"}
        puts $h "$bit\t$source\t$sink\t[join $drivers ,]"
    };close $h
    set h [open [file join $directory destinations.tsv] w];puts $h "bit\tdestination\tconnected"
    dict for {bit source} [lesson05i_observer_map] {
        set q [get_pins [format {diagnostics/raw_sync_reg[%d]/Q} $bit]]
        set segments [get_nets -segments -of_objects $q]
        foreach target {monitor/probe_in1 clock_trace/probe1} {
            set p [get_pins [format {%s[%d]} $target $bit]];set joined 0
            foreach net [get_nets -segments -of_objects $p] {if {$net in $segments} {set joined 1}}
            if {!$joined} {error "Observer $bit does not reach $target"}
            puts $h "$bit\t$p\t1"
        }
    };close $h
    set h [open [file join $directory pins.tsv] w];puts $h "port\tpackage_pin"
    foreach p [lsort [get_ports]] {puts $h "$p\t[get_property PACKAGE_PIN $p]"};close $h
    set h [open [file join $directory clock_reset.tsv] w];puts $h "object\tproperty\tvalue"
    set memories [get_cells -hier -filter {NAME =~ diagnostics/* && REF_NAME =~ RAMB*}]
    if {![llength $memories]} {error "Event storage did not infer block RAM"}
    puts $h "events\tBLOCK_RAM_PRIMITIVES\t[llength $memories]"
    foreach name {reference_input reference_monitor_buffer ref_observer_buffer} {
        puts $h "$name\tLOC\t[get_property LOC [get_cells $name]]"
    }
    foreach pin {CEMASK CLRMASK {DIV[0]} {DIV[1]} {DIV[2]}} {
        set sources [get_cells -of_objects [get_pins -leaf -of_objects [get_nets -segments -of_objects [get_pins ref_observer_buffer/$pin]] -filter {DIRECTION==OUT}]]
        if {[llength $sources]!=1 || [get_property REF_NAME $sources] ne "VCC"} {error "Wrong observer buffer constant $pin"}
        puts $h "ref_observer_buffer\t$pin\t1"
    }
    foreach name {I CE CLR} {
        set a [get_nets -of_objects [get_pins ref_observer_buffer/$name]]
        set b [get_nets -of_objects [get_pins reference_monitor_buffer/$name]]
        if {$a ne $b} {error "BUFG_GT shared input/control mismatch: $name"}
        puts $h "ref_observer_buffer/$name\tnet\t$a"
    }
    set refnet [get_nets -of_objects [get_pins reference_input/O]]
    puts $h "$refnet\tROUTE_STATUS\t[get_property ROUTE_STATUS $refnet]"
    puts $h "$refnet\tROUTE\t[get_property ROUTE $refnet]"
    set reset [get_pins $reset_pin]
    if {[llength $reset]!=1} {error "Missing expected endpoint reset driver"}
    set resetnets [get_nets -segments -of_objects $reset]
    set core_reset [get_nets -segments -of_objects [get_pins dma/sys_rst_n]]
    set joined 0;foreach n $resetnets {if {$n in $core_reset} {set joined 1}}
    if {!$joined} {error "Endpoint reset is not the registered bridge output"}
    puts $h "dma/sys_rst_n\tdriver\t$reset"
    set first [get_pins -hier -filter {NAME =~ diagnostics/raw_meta_reg*/D || NAME =~ diagnostics/auxiliary_meta_reg*/D}]
    if {[llength $first]!=68} {error "Unexpected first-stage observation count"}
    puts $h "async_observation\tfirst_stage_pins\t[llength $first]"
    if {![llength [get_timing_paths -quiet -from [get_pins {diagnostics/raw_meta_reg[0]/Q}] -to [get_pins {diagnostics/raw_sync_reg[0]/D}] -max_paths 1]]} {error "Second synchronizer stage is no longer timed"}
    puts $h "raw_sync_stage2\ttimed\t1";close $h
}
proc lesson05i_boot_build {out part {profile e4}} {
    global repo_dir
    if {$part ne "xcku5p-ffvb676-1-i"} {error "Unverified part"}
    if {$profile ni {e4 e5}} {error "Invalid diagnostic build profile"}
    set top [expr {$profile eq "e4" ? "lesson05i_pcie_boot_top" : "lesson05j_pcie_reference_top"}]
    set reset_pin [expr {$profile eq "e4" ? {reset_bridge/endpoint_pipe_reg[1]/Q} : {reference_reset/core_reset_gate/O}}]
    set out [file normalize $out]
    if {![file exists [file join $out inputs.json]] || ![file exists [file join $out boot_sim simulation_pass.txt]]} {error "Frozen inputs and diagnostic simulation required"}
    if {$profile eq "e5"} {
        foreach folder {reference_reset_sim boot_provenance_sim} {
            if {![file exists [file join $out $folder simulation_pass.txt]]} {error "Missing reference profile simulation: $folder"}
        }
    }
    set_param tcl.collectionResultDisplayLimit 0
    source -notrace [file join $repo_dir tcl lesson05d_project.tcl]
    lesson05d_prepare $out $part 4 1 1 [expr {$profile eq "e4" ? "true" : "false"}]
    set rtl [list ${top}.sv pcie_boot_diagnostics.sv]
    if {$profile eq "e5"} {lappend rtl pcie_reference_reset.sv}
    foreach name $rtl {add_files -norecurse [file join $repo_dir rtl $name]}
    remove_files [get_files -of_objects [get_filesets constrs_1]]
    add_files -fileset constrs_1 -norecurse [file join $repo_dir constr lesson05i_pcie_boot.xdc]
    set_property -dict {CONFIG.C_NUM_PROBE_IN 8 CONFIG.C_NUM_PROBE_OUT 3
        CONFIG.C_PROBE_IN0_WIDTH 32 CONFIG.C_PROBE_IN1_WIDTH 64 CONFIG.C_PROBE_IN2_WIDTH 64
        CONFIG.C_PROBE_IN3_WIDTH 64 CONFIG.C_PROBE_IN4_WIDTH 128 CONFIG.C_PROBE_IN5_WIDTH 128
        CONFIG.C_PROBE_IN6_WIDTH 256 CONFIG.C_PROBE_IN7_WIDTH 128
        CONFIG.C_PROBE_OUT0_WIDTH 1 CONFIG.C_PROBE_OUT0_INIT_VAL 0x1
        CONFIG.C_PROBE_OUT1_WIDTH 9 CONFIG.C_PROBE_OUT1_INIT_VAL 0x0
        CONFIG.C_PROBE_OUT2_WIDTH 1 CONFIG.C_PROBE_OUT2_INIT_VAL 0x0} [get_ips lesson05d_vio]
    generate_target all [get_ips lesson05d_vio]
    create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name lesson05i_ila -dir [file join $out vivado_project ip]
    set_property -dict {CONFIG.C_NUM_OF_PROBES 3 CONFIG.C_PROBE0_WIDTH 32 CONFIG.C_PROBE1_WIDTH 64 CONFIG.C_PROBE2_WIDTH 64 CONFIG.C_DATA_DEPTH 4096} [get_ips lesson05i_ila]
    generate_target all [get_ips lesson05i_ila]
    set_property GENERATE_SYNTH_CHECKPOINT false [get_files [get_property IP_FILE [get_ips lesson05i_ila]]]
    set_property top $top [get_filesets sources_1]
    update_compile_order -fileset sources_1
    launch_runs synth_1 -jobs 2;wait_on_run synth_1;open_run synth_1
    lesson05i_attach_observers $out
    opt_design
    if {[llength [get_cells -hier -quiet -filter {IS_BLACKBOX==1}]]} {error "Unresolved black box after debug-core implementation"}
    place_design;route_design
    set reports [file join $out reports]
    foreach {cmd file} {report_timing_summary timing.rpt check_timing check_timing.rpt report_route_status route.rpt report_drc drc.rpt report_utilization utilization.rpt report_bus_skew bus_skew.rpt report_clocks clocks.rpt} {$cmd -file [file join $reports $file]}
    report_cdc -details -no_waiver -file [file join $reports cdc.rpt]
    if {[llength [get_drc_violations -quiet -filter {SEVERITY==Error}]]} {error "DRC errors prevent bitstream acceptance"}
    lesson05i_audit $reports $reset_pin
    write_checkpoint -force [file join $out diagnostic_routed_before_acceptance.dcp]
    foreach delay {max min} {if {[llength [get_timing_paths -quiet -delay_type $delay -slack_lesser_than 0 -max_paths 1]]} {error "Timing failed"}}
    set h [open [file join $reports cdc.rpt]];set cdc [read $h];close $h
    if {[regexp -line {^CDC-[0-9]+\s+Critical\s+[1-9]} $cdc]} {error "Unwaived CDC Critical paths: fix before generating bitstream"}
    if {$profile eq "e5"} {
        set cores [get_cells -hier -filter {REF_NAME==PCIE40E4}]
        if {[llength $cores]!=1 || ![get_property PL_DISABLE_LANE_REVERSAL $cores] ||
            ![get_property PF0_LINK_STATUS_SLOT_CLOCK_CONFIG $cores]} {error "Reference candidate primitive contract failed"}
        source -notrace [file join $repo_dir tcl audit_pcie_lane_mapping.tcl]
        audit_pcie_lane_mapping [file join $reports lane_data_contract.tsv]
    }
    write_checkpoint -force [file join $out ${top}_routed.dcp]
    write_debug_probes -force [file join $out ${top}.ltx]
    write_bitstream -force [file join $out ${top}.bit]
    close_project;open_checkpoint [file join $out ${top}_routed.dcp]
    lesson05i_audit [file join $out reopened_audit] $reset_pin;close_design
    puts BOOT_DIAGNOSTIC_BUILD_COMPLETE
}
