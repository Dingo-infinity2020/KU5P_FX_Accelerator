# HDL-instantiated ILA flow, supported by BASIC; no netlist debug insertion.
proc lesson05d_clock_measure {out part base} {
    global repo_dir
    set out [file normalize $out]
    source -notrace [file join $repo_dir tcl lesson05d_project.tcl]
    lesson05d_prepare $out $part 4 1 1
    set cache [file join [file dirname $out] lesson05d_pcie_phy vivado_project lesson05d_pcie.cache ip]
    if {[file isdirectory $cache]} {set_property IP_OUTPUT_REPO $cache [current_project]}
    create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name lesson05d_clock_ila -dir [file join $out vivado_project ip]
    set_property -dict {CONFIG.C_NUM_OF_PROBES 1 CONFIG.C_DATA_DEPTH 4096 CONFIG.C_PROBE0_WIDTH 2 CONFIG.C_PROBE0_TYPE 0 CONFIG.C_INPUT_PIPE_STAGES 1} [get_ips lesson05d_clock_ila]
    generate_target all [get_ips lesson05d_clock_ila]
    create_ip_run [get_files [get_property IP_FILE [get_ips lesson05d_clock_ila]]]
    set_property STEPS.SYNTH_DESIGN.TCL.PRE [file join $repo_dir tcl lesson05d_synth_settings.tcl] [get_runs lesson05d_clock_ila_synth_1]
    add_files -norecurse [file join $repo_dir rtl lesson05d_pcie_clock_top.sv]
    set ::l5d_top lesson05d_pcie_clock_top
    set_property top $::l5d_top [get_filesets sources_1]
    update_compile_order -fileset sources_1
    lesson05d_accept_simulation
    lesson05d_start_implementation
    puts "HDL_CLOCK_MEASURE_STARTED"
}
