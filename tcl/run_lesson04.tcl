# Usage: -tclargs <external_build_dir> <part> <prepare|simulate|all>
# prepare leaves the project open so the same flow can be driven through MCP.
if {[llength $argv]!=3} { error "Expected build_dir, part, action" }
lassign $argv build_dir part action
if {$action ni {prepare simulate all}} { error "Invalid lesson04 action" }
set repo_dir [file normalize [file join [file dirname [info script]] ..]]
set build_dir [file normalize $build_dir]
set repo_lower [string tolower [string map {\\ /} $repo_dir]]
set build_lower [string tolower [string map {\\ /} $build_dir]]
if {$build_lower eq $repo_lower || [string first "$repo_lower/" "$build_lower/"]==0} {
    error "Build directory must be outside the source repository"
}
if {[current_project -quiet] ne ""} { error "Close the current project before starting lesson04" }
file mkdir $build_dir
set project_dir [file join $build_dir vivado_project]
set xpr [file join $project_dir lesson04_pfb.xpr]
if {[file exists $xpr]} {
    open_project $xpr
    if {[get_property PART [current_project]] ne $part} { error "Existing project part differs" }
} else { create_project lesson04_pfb $project_dir -part $part }
foreach name {two_channel_correlator.sv fft_pair_512.sv channelized_x_engine.sv pfb_fir_pair_512.sv two_channel_pfb_fx.sv} {
    set path [file join $repo_dir rtl $name]
    if {[llength [get_files -quiet $path]]==0} { add_files -norecurse $path }
}
set xdc [file join $repo_dir constraints lesson04_ooc.xdc]
if {[llength [get_files -quiet $xdc]]==0} { add_files -fileset constrs_1 -norecurse $xdc }
set tb [file join $repo_dir sim tb_two_channel_pfb_fx.sv]
if {[llength [get_files -quiet $tb]]==0} { add_files -fileset sim_1 -norecurse $tb }
foreach name {stimulus.txt expected_pfb.txt expected_fft.txt expected_fx.txt} {
    set path [file join $build_dir $name]
    if {![file exists $path]} { error "Missing reference data $path" }
    if {[llength [get_files -quiet $path]]==0} { add_files -fileset sim_1 -norecurse $path }
    set_property file_type {Data Files} [get_files $path]
}
set coeff_file [file join $build_dir pfb_coeffs.mem]
if {![file exists $coeff_file]} { error "Missing PFB coefficients" }
if {[llength [get_files -quiet $coeff_file]]==0} { add_files -norecurse $coeff_file }
set_property file_type {Memory Initialization Files} [get_files $coeff_file]

# Reuse the third lesson's wrapper and identical FFT configuration; generate
# the vendor IP again in THIS external project, without copying vendor sources.
set ip_config [list CONFIG.transform_length 512 CONFIG.implementation_options pipelined_streaming_io \
    CONFIG.input_width 16 CONFIG.phase_factor_width 24 CONFIG.scaling_options unscaled \
    CONFIG.rounding_modes convergent_rounding CONFIG.aresetn true CONFIG.xk_index true \
    CONFIG.output_ordering natural_order CONFIG.throttle_scheme nonrealtime CONFIG.target_clock_frequency 100]
if {[llength [get_ips -quiet lesson03_fft512]]==0} {
    file mkdir [file join $project_dir ip]
    create_ip -name xfft -vendor xilinx.com -library ip -version 9.1 -module_name lesson03_fft512 -dir [file join $project_dir ip]
    set_property -dict $ip_config [get_ips lesson03_fft512]
} else {
    foreach {property expected} $ip_config {
        if {![string equal -nocase [get_property $property [get_ips lesson03_fft512]] $expected]} {
            error "FFT config mismatch at $property; choose a new build directory"
        }
    }
}
generate_target all [get_ips lesson03_fft512]
set_property top two_channel_pfb_fx [get_filesets sources_1]
set_property top tb_two_channel_pfb_fx [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
set_property xsim.simulate.log_all_signals false [get_filesets sim_1]
set wave_path [file join $build_dir log_waves.tcl]
set handle [open $wave_path w]
puts $handle {log_wave /tb_two_channel_pfb_fx/dut/*}
puts $handle {foreach sig {phase tap state depth history_valid_a history_valid_b contribution_a contribution_b coefficient accumulator_ai sum_ai} {log_wave /tb_two_channel_pfb_fx/dut/pfb/$sig}}
close $handle
set_property xsim.simulate.tcl.pre $wave_path [get_filesets sim_1]
set_property -dict [list {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} {-mode out_of_context}] [get_runs synth_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
file mkdir [file join $build_dir reports]
report_property [get_ips lesson03_fft512] -file [file join $build_dir reports fft_ip_properties.txt]
set sim_dir [file join $project_dir lesson04_pfb.sim sim_1 behav xsim]
foreach path [list [file join $sim_dir simulation_pass.txt] [file join $build_dir simulation_pass.txt]] {
    if {[file exists $path]} { file delete $path }
}

proc lesson04_finish {do_synthesize} {
    global build_dir sim_dir part xpr
    set pass_path [file join $sim_dir simulation_pass.txt]
    if {![file exists $pass_path]} { error "No fresh lesson04 PASS marker" }
    set handle [open $pass_path r]; set text [string trim [read $handle]]; close $handle
    if {![string match "PASS windows=*" $text]} { error "Invalid PASS marker" }
    file copy -force $pass_path [file join $build_dir simulation_pass.txt]
    close_sim
    puts "LESSON04_SIMULATION=$text"
    if {$do_synthesize} {
        if {[get_property PROGRESS [get_runs synth_1]] ne "0%"} { reset_run synth_1 }
        launch_runs synth_1 -jobs 2
        wait_on_run synth_1
        if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { error "Lesson04 synthesis failed" }
        open_run synth_1
        set bb [get_cells -hierarchical -quiet -filter {IS_BLACKBOX==1}]
        if {[llength $bb]!=0} { error "Unresolved black boxes: $bb" }
        set reports [file join $build_dir reports]
        report_utilization -file [file join $reports utilization_synth.rpt]
        report_utilization -hierarchical -file [file join $reports utilization_hierarchical_synth.rpt]
        report_timing_summary -file [file join $reports timing_synth.rpt]
        check_timing -verbose -file [file join $reports check_timing_synth.rpt]
        write_checkpoint -force [file join $build_dir two_channel_pfb_fx_synth.dcp]
        set handle [open [file join $build_dir synthesis_scope.txt] w]
        puts $handle "part=$part\ntool=[version -short]\nscope=OOC synthesis; no placement/routing or board validation"
        puts $handle "requested_clock_period_ns=10.000\nclock_constraint_read_before_synthesis=true\nblackboxes=0"
        close $handle
        puts "LESSON04_SYNTHESIS_COMPLETE"
    }
    puts "LESSON04_PROJECT=$xpr"
}
puts "LESSON04_PREPARED=$xpr"
if {$action ne "prepare"} {
    launch_simulation -mode behavioral
    lesson04_finish [expr {$action eq "all"}]
    close_project
}
