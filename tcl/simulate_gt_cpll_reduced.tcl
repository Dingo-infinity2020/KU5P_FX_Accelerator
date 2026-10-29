# Simulation only. Deliberately different CPLL/5Gbps coverage; no bitstream.
if {[llength $argv]!=1} {error "Usage: simulate_gt_cpll_reduced.tcl external_output"}
set repo_dir [file normalize [file join [file dirname [info script]] ..]]
set out [file normalize [lindex $argv 0]]
set root_guard [string tolower [string map {\\ /} $repo_dir]]
set out_guard [string tolower [string map {\\ /} $out]]
if {$root_guard eq $out_guard || [string first "$root_guard/" "$out_guard/"]==0} {error "External output required"}
file mkdir $out
set project_file [file join $out vivado_project cpll_reduced.xpr]
if {[file exists $project_file]} {open_project $project_file} else {
    create_project cpll_reduced [file join $out vivado_project] -part xcku5p-ffvb676-1-i
}
set ipfile [file join $out ip lesson05e_gt_cpll_sim lesson05e_gt_cpll_sim.xci]
if {[llength [get_ips -quiet lesson05e_gt_cpll_sim]]} {
    # Existing generated simulation IP is checked by the configuration below.
} elseif {[file exists $ipfile]} {read_ip $ipfile} else {
    file mkdir [file join $out ip]
    create_ip -name gtwizard_ultrascale -vendor xilinx.com -library ip -version 1.7 -module_name lesson05e_gt_cpll_sim -dir [file join $out ip]
}
set_property -dict {CONFIG.GT_TYPE GTY CONFIG.CHANNEL_ENABLE X0Y4 CONFIG.TX_MASTER_CHANNEL X0Y4 CONFIG.RX_MASTER_CHANNEL X0Y4
    CONFIG.TX_LINE_RATE 5 CONFIG.RX_LINE_RATE 5 CONFIG.TX_REFCLK_FREQUENCY 100 CONFIG.RX_REFCLK_FREQUENCY 100
    CONFIG.TX_PLL_TYPE CPLL CONFIG.RX_PLL_TYPE CPLL CONFIG.TX_DATA_ENCODING 8B10B CONFIG.RX_DATA_DECODING 8B10B
    CONFIG.TX_USER_DATA_WIDTH 32 CONFIG.TX_INT_DATA_WIDTH 40 CONFIG.RX_USER_DATA_WIDTH 32 CONFIG.RX_INT_DATA_WIDTH 40
    CONFIG.FREERUN_FREQUENCY 100 CONFIG.LOCATE_RESET_CONTROLLER CORE CONFIG.LOCATE_TX_USER_CLOCKING CORE
    CONFIG.LOCATE_RX_USER_CLOCKING CORE CONFIG.ENABLE_OPTIONAL_PORTS {cplllock_out gtpowergood_out txelecidle_in txinhibit_in}} [get_ips lesson05e_gt_cpll_sim]
generate_target all [get_ips lesson05e_gt_cpll_sim]
report_property [get_ips lesson05e_gt_cpll_sim] -file [file join $out properties.rpt]
set path [file join $repo_dir rtl gt_isolation_reset.sv]
if {![llength [get_files -quiet $path]]} {add_files -norecurse $path}
set path [file join $repo_dir sim tb_gt_cpll_reduced.sv]
if {![llength [get_files -quiet $path]]} {add_files -fileset sim_1 -norecurse $path}
set_property top tb_gt_cpll_reduced [get_filesets sim_1]
set_property xsim.simulate.runtime 0us [get_filesets sim_1]
set marker [file join $out vivado_project cpll_reduced.sim sim_1 behav xsim cpll_simulation_pass.txt]
if {[file exists $marker]} {file delete $marker}
launch_simulation -simset sim_1 -mode behavioral
run all
close_sim
if {![file exists $marker]} {error "No CPLL model PASS marker"}
set h [open $marker r];set result [string trim [read $h]];close $h
if {$result ne "PASS gt_cpll_reduced_checks=4"} {error "Wrong CPLL result"}
file copy -force $marker [file join $out cpll_simulation_pass.txt]
puts CPLL_REDUCED_SIMULATION_COMPLETE
