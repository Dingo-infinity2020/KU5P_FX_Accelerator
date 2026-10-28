# Rebuildable project flow: create FFT IP locally, simulate, optionally synthesize.
# Usage: -tclargs <external_build_dir> <part> <synthesize:0|1>
if {[llength $argv] != 3} { error "Expected external_build_dir, part, synthesize" }
lassign $argv build_dir part do_synthesize
set repo_dir [file normalize [file join [file dirname [info script]] ..]]
set build_dir [file normalize $build_dir]
set repo_lower [string tolower [string map {\\ /} $repo_dir]]
set build_lower [string tolower [string map {\\ /} $build_dir]]
if {$build_lower eq $repo_lower || [string first "$repo_lower/" "$build_lower/"] == 0} {
    error "Build directory must be outside the source repository"
}
if {[current_project -quiet] ne ""} { error "Use a new Vivado process" }
set project_dir [file join $build_dir vivado_project]
set xpr [file join $project_dir lesson03_fx.xpr]
if {[file exists $xpr]} {
    open_project $xpr
    if {[get_property PART [current_project]] ne $part} { error "Existing project part differs" }
} else {
    create_project lesson03_fx $project_dir -part $part
}
foreach source {two_channel_correlator.sv fft_pair_512.sv channelized_x_engine.sv two_channel_fft_fx.sv} {
    set path [file join $repo_dir rtl $source]
    if {[llength [get_files -quiet $path]] == 0} { add_files -norecurse $path }
}
set timing_file [file join $repo_dir constraints lesson03_ooc.xdc]
if {[llength [get_files -quiet $timing_file]] == 0} { add_files -fileset constrs_1 -norecurse $timing_file }
set tb [file join $repo_dir sim tb_two_channel_fft_fx.sv]
if {[llength [get_files -quiet $tb]] == 0} { add_files -fileset sim_1 -norecurse $tb }
foreach name {stimulus.txt expected_fft.txt expected_fx.txt} {
    set path [file join $build_dir $name]
    if {![file exists $path]} { error "Missing generated vector file $path" }
    if {[llength [get_files -quiet $path]] == 0} { add_files -fileset sim_1 -norecurse $path }
    set_property file_type {Data Files} [get_files $path]
}
set ip_config [list CONFIG.transform_length 512 CONFIG.implementation_options pipelined_streaming_io \
    CONFIG.input_width 16 CONFIG.phase_factor_width 24 CONFIG.scaling_options unscaled \
    CONFIG.rounding_modes convergent_rounding CONFIG.aresetn true CONFIG.xk_index true \
    CONFIG.output_ordering natural_order CONFIG.throttle_scheme nonrealtime CONFIG.target_clock_frequency 100]
if {[llength [get_ips -quiet lesson03_fft512]] == 0} {
    set ip_dir [file join $project_dir ip]
    file mkdir $ip_dir
    create_ip -name xfft -vendor xilinx.com -library ip -version 9.1 -module_name lesson03_fft512 -dir $ip_dir
    set_property -dict $ip_config [get_ips lesson03_fft512]
} else {
    foreach {property expected} $ip_config {
        if {![string equal -nocase [get_property $property [get_ips lesson03_fft512]] $expected]} {
            error "Existing FFT IP configuration differs at $property. Use another build directory."
        }
    }
}
generate_target all [get_ips lesson03_fft512]
set_property top two_channel_fft_fx [get_filesets sources_1]
set_property top tb_two_channel_fft_fx [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
set_property xsim.simulate.log_all_signals false [get_filesets sim_1]
set wave_script [file join $build_dir log_waves.tcl]
set wave_handle [open $wave_script w]
puts $wave_handle {log_wave /tb_two_channel_fft_fx/dut/*}
puts $wave_handle {foreach sig {pending_a pending_b configured expected_bin load_index a_out_valid b_out_valid a_out_ready b_out_ready} {log_wave /tb_two_channel_fft_fx/dut/fft_pair/$sig}}
puts $wave_handle {foreach sig {state saved_bin saved_first saved_last previous_a previous_real sum_a sum_real product_valid product_ready} {log_wave /tb_two_channel_fft_fx/dut/x_engine/$sig}}
close $wave_handle
set_property xsim.simulate.tcl.pre $wave_script [get_filesets sim_1]
set_property -dict [list {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} {-mode out_of_context}] [get_runs synth_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
set reports [file join $build_dir reports]
file mkdir $reports
report_property [get_ips lesson03_fft512] -file [file join $reports fft_ip_properties.txt]
report_ip_status -file [file join $reports ip_status.rpt]
set sim_dir [file join $project_dir lesson03_fx.sim sim_1 behav xsim]
set pass_path [file join $sim_dir simulation_pass.txt]
if {[file exists $pass_path]} { file delete $pass_path }
launch_simulation -mode behavioral
if {![file exists $pass_path]} { error "Simulation did not reach a fresh PASS marker" }
set handle [open $pass_path r]
set pass_text [string trim [read $handle]]
close $handle
if {![string match "PASS windows=*" $pass_text]} { error "Invalid simulation marker" }
file copy -force $pass_path [file join $build_dir simulation_pass.txt]
close_sim
puts "LESSON03_SIMULATION=$pass_text"
if {$do_synthesize} {
    if {[get_property PROGRESS [get_runs synth_1]] ne "0%"} { reset_run synth_1 }
    launch_runs synth_1 -jobs 2
    wait_on_run synth_1
    if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { error "Synthesis run failed" }
    open_run synth_1
    set blackboxes [get_cells -hierarchical -quiet -filter {IS_BLACKBOX == 1}]
    if {[llength $blackboxes] != 0} { error "Unresolved synthesis black boxes: $blackboxes" }
    report_utilization -file [file join $reports utilization_synth.rpt]
    report_utilization -hierarchical -file [file join $reports utilization_hierarchical_synth.rpt]
    report_timing_summary -file [file join $reports timing_synth.rpt]
    check_timing -verbose -file [file join $reports check_timing_synth.rpt]
    write_checkpoint -force [file join $build_dir two_channel_fft_fx_synth.dcp]
    set handle [open [file join $build_dir synthesis_scope.txt] w]
    puts $handle "part=$part"
    puts $handle "tool=[version -short]"
    puts $handle "scope=OOC synthesis of two FFT IP instances and channelized X; no placement/routing or board validation"
    puts $handle "requested_clock_period_ns=10.000"
    puts $handle "clock_constraint_read_before_synthesis=true"
    puts $handle "blackboxes=0"
    close $handle
    puts "LESSON03_SYNTHESIS_COMPLETE"
}
puts "LESSON03_PROJECT=$xpr"
close_project
exit
