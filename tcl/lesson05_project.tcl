# Called only through tcl/build.tcl for lesson05_board_top. No hardware writes.
proc lesson05_prepare {output_dir target_part} {
    global repo_dir
    set ::l5_build [file normalize $output_dir]
    set ::l5_part $target_part
    set build_lower [string tolower [string map {\\ /} $::l5_build]]
    set repo_lower [string tolower [string map {\\ /} $repo_dir]]
    if {$build_lower eq $repo_lower || [string first "$repo_lower/" "$build_lower/"]==0} {
        error "Board build output must be outside repository"
    }
    if {$target_part ne "xcku5p-ffvb676-1-i"} { error "Lesson05 pinout is for FNIC-KU5P FFVB676 only" }
    if {[current_project -quiet] ne ""} { error "Close current project before lesson05 build" }
    set project_dir [file join $::l5_build vivado_project]
    set ::l5_xpr [file join $project_dir lesson05_board.xpr]
    if {[file exists $::l5_xpr]} {
        open_project $::l5_xpr
        if {[get_property PART [current_project]] ne $target_part} { error "Wrong existing project part" }
    } else { create_project lesson05_board $project_dir -part $target_part }
    foreach name {two_channel_correlator.sv fft_pair_512.sv channelized_x_engine.sv pfb_fir_pair_512.sv two_channel_pfb_fx.sv lesson05_replay.sv lesson05_board_top.sv} {
        set path [file join $repo_dir rtl $name]
        if {[llength [get_files -quiet $path]]==0} { add_files -norecurse $path }
    }
    set xdc [file join $repo_dir constr lesson05_fnic_ku5p.xdc]
    if {[llength [get_files -quiet $xdc]]==0} { add_files -fileset constrs_1 -norecurse $xdc }
    foreach name {pfb_coeffs.mem replay_samples.mem replay_good.mem} {
        set path [file join $::l5_build $name]
        if {![file exists $path]} { error "Missing generated $name" }
        if {[llength [get_files -quiet $path]]==0} { add_files -norecurse $path }
        set_property file_type {Memory Initialization Files} [get_files $path]
    }
    foreach path [list [file join $repo_dir sim tb_lesson05_replay.sv] [file join $::l5_build expected_replay.mem]] {
        if {[llength [get_files -quiet $path]]==0} { add_files -fileset sim_1 -norecurse $path }
    }
    set_property file_type {Memory Initialization Files} [get_files [file join $::l5_build expected_replay.mem]]
    set ip_dir [file join $project_dir ip]; file mkdir $ip_dir
    set fft_config [list CONFIG.transform_length 512 CONFIG.implementation_options pipelined_streaming_io \
        CONFIG.input_width 16 CONFIG.phase_factor_width 24 CONFIG.scaling_options unscaled \
        CONFIG.rounding_modes convergent_rounding CONFIG.aresetn true CONFIG.xk_index true \
        CONFIG.output_ordering natural_order CONFIG.throttle_scheme nonrealtime CONFIG.target_clock_frequency 100]
    set ila_config [list CONFIG.C_NUM_OF_PROBES 5 CONFIG.C_DATA_DEPTH 2048 CONFIG.C_EN_STRG_QUAL 1 \
        CONFIG.C_INPUT_PIPE_STAGES 1 CONFIG.C_PROBE0_WIDTH 1 CONFIG.C_PROBE0_TYPE 0 \
        CONFIG.C_PROBE1_WIDTH 394 CONFIG.C_PROBE1_TYPE 1 CONFIG.C_PROBE2_WIDTH 64 CONFIG.C_PROBE2_TYPE 1 \
        CONFIG.C_PROBE3_WIDTH 64 CONFIG.C_PROBE3_TYPE 1 CONFIG.C_PROBE4_WIDTH 128 CONFIG.C_PROBE4_TYPE 1]
    set vio_config [list CONFIG.C_NUM_PROBE_IN 6 CONFIG.C_NUM_PROBE_OUT 2 CONFIG.C_PROBE_IN0_WIDTH 8 \
        CONFIG.C_PROBE_IN1_WIDTH 32 CONFIG.C_PROBE_IN2_WIDTH 32 CONFIG.C_PROBE_IN3_WIDTH 32 \
        CONFIG.C_PROBE_IN4_WIDTH 32 CONFIG.C_PROBE_IN5_WIDTH 32 CONFIG.C_PROBE_OUT0_WIDTH 1 \
        CONFIG.C_PROBE_OUT1_WIDTH 1 CONFIG.C_PROBE_OUT0_INIT_VAL 0 CONFIG.C_PROBE_OUT1_INIT_VAL 0]
    foreach {module ipname version config} [list lesson03_fft512 xfft 9.1 $fft_config \
        lesson05_ila ila 6.2 $ila_config lesson05_vio vio 3.0 $vio_config] {
        if {[llength [get_ips -quiet $module]]==0} {
            create_ip -name $ipname -vendor xilinx.com -library ip -version $version -module_name $module -dir $ip_dir
            set_property -dict $config [get_ips $module]
        } else {
            foreach {key value} $config {
                if {![string equal -nocase [get_property $key [get_ips $module]] $value]} {
                    error "Existing IP config mismatch: $module $key; use a fresh build directory"
                }
            }
        }
        generate_target all [get_ips $module]
    }
    set_property top lesson05_board_top [get_filesets sources_1]
    set_property top tb_lesson05_replay [get_filesets sim_1]
    set_property xsim.simulate.runtime all [get_filesets sim_1]
    set_property xsim.simulate.log_all_signals false [get_filesets sim_1]
    set waves [file join $::l5_build log_waves.tcl]
    set h [open $waves w]; puts $h {log_wave /tb_lesson05_replay/dut/*}; close $h
    set_property xsim.simulate.tcl.pre $waves [get_filesets sim_1]
    update_compile_order -fileset sources_1
    update_compile_order -fileset sim_1
    set ::l5_sim [file join $project_dir lesson05_board.sim sim_1 behav xsim]
    foreach marker [list [file join $::l5_sim simulation_pass.txt] [file join $::l5_build simulation_pass.txt]] {
        if {[file exists $marker]} { file delete $marker }
    }
    file mkdir [file join $::l5_build reports]
    report_ip_status -file [file join $::l5_build reports ip_status.rpt]
    puts "LESSON05_PREPARED=$::l5_xpr"
}

proc lesson05_accept_simulation {} {
    set marker [file join $::l5_sim simulation_pass.txt]
    if {![file exists $marker]} { error "No fresh replay simulation PASS" }
    set h [open $marker r]; set text [string trim [read $h]]; close $h
    if {![string match "PASS replay_samples=8192 result_rows=2048 signature=930aa3d5 *" $text]} { error "Unexpected replay PASS: $text" }
    file copy -force $marker [file join $::l5_build simulation_pass.txt]
    close_sim
    puts "LESSON05_SIMULATION=$text"
}

proc lesson05_start_implementation {} {
    if {![file exists [file join $::l5_build simulation_pass.txt]]} { error "Run and accept simulation first" }
    # A failed synthesis may still report 0%; reset it before every fresh build.
    reset_run synth_1
    launch_runs impl_1 -to_step write_bitstream -jobs 2
}

proc lesson05_implement {} {
    lesson05_start_implementation
    wait_on_run impl_1
    lesson05_collect_implementation
}

proc lesson05_collect_implementation {} {
    if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} { error "Board implementation/bitstream failed" }
    open_run impl_1
    if {[llength [get_cells -hierarchical -quiet -filter {IS_BLACKBOX == 1}]]!=0} { error "Board netlist contains black boxes" }
    set rpt [file join $::l5_build reports]
    report_utilization -file [file join $rpt utilization_route.rpt]
    report_utilization -hierarchical -file [file join $rpt utilization_hierarchical_route.rpt]
    report_timing_summary -file [file join $rpt timing_route.rpt]
    check_timing -verbose -file [file join $rpt check_timing_route.rpt]
    report_drc -file [file join $rpt drc_route.rpt]
    report_route_status -file [file join $rpt route_status.rpt]
    report_cdc -file [file join $rpt cdc_route.rpt]
    set setup [get_timing_paths -delay_type max -max_paths 1]
    set hold [get_timing_paths -delay_type min -max_paths 1]
    if {[llength $setup]==0 || [get_property SLACK $setup]<0 || [llength $hold]==0 || [get_property SLACK $hold]<0} {
        error "Board setup/hold timing not closed"
    }
    set errors [get_drc_violations -quiet -filter {SEVERITY == Error}]
    if {[llength $errors]!=0} { error "Board DRC errors: $errors" }
    write_checkpoint -force [file join $::l5_build lesson05_board_top_routed.dcp]
    write_debug_probes -force [file join $::l5_build lesson05_board_top.ltx]
    file copy -force [file join $::l5_build vivado_project lesson05_board.runs impl_1 lesson05_board_top.bit] \
        [file join $::l5_build lesson05_board_top.bit]
    set h [open [file join $::l5_build implementation_scope.txt] w]
    puts $h "part=$::l5_part\ntool=[version -short]\nclock_period_ns=10.000\nboard=FNIC-KU5P_Rev1.0"
    puts $h "blackboxes=0\ndrc_errors=0\nsetup_slack=[get_property SLACK $setup]\nhold_slack=[get_property SLACK $hold]"
    puts $h "hardware_programmed=false"
    close $h
    puts "LESSON05_IMPLEMENTATION_COMPLETE"
}
