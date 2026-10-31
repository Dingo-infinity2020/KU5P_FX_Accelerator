# build.tcl -- reproducible Vivado build for KU5P designs
#
# usage:
#   vivado -mode batch -source tcl/build.tcl -tclargs <part> <top> [build_dir]
#
# example:
#   vivado -mode batch -source tcl/build.tcl -tclargs xcku5p-ffva676-1-i top D:\work\ku5p_build
#
# Builds: synth_design -> opt_design -> place_design -> route_design -> write_bitstream
# Reports are written to <build_dir>/reports.

if {[llength $argv] < 2} {
    puts "ERROR: usage: -tclargs <part> <top> \[build_dir\]"
    exit 1
}
lassign $argv part top build_dir
if {![info exists build_dir] || $build_dir eq ""} {
    set build_dir [file normalize [file join [pwd] build]]
}

set repo_dir [file normalize [file join [file dirname [info script]] ..]]
set rtl_dir  [file join $repo_dir rtl]
set xdc_dir  [file join $repo_dir constr]
set rpt_dir  [file join $build_dir reports]

proc log {msg} { puts "\[build\] $msg" }

proc rglob {dir patterns} {
    set out {}
    if {![file isdirectory $dir]} { return $out }
    foreach p $patterns {
        foreach f [glob -nocomplain -directory $dir $p] { lappend out $f }
    }
    foreach d [glob -nocomplain -directory $dir -type d *] {
        lappend out {*}[rglob $d $patterns]
    }
    return $out
}

log "part      = $part"
log "top       = $top"
log "build_dir = $build_dir"

if {$top eq "lesson05j_pcie_reference_top"} {
    source -notrace [file join $repo_dir tcl lesson05i_boot_project.tcl]
    lesson05i_boot_build $build_dir $part e5
    return
}

if {$top eq "lesson05i_pcie_boot_top"} {
    source -notrace [file join $repo_dir tcl lesson05i_boot_project.tcl]
    lesson05i_boot_build $build_dir $part
    return
}

if {$top eq "lesson05h_cpll_source_top"} {
    set action [lindex $argv 3]
    if {$action eq ""} {set action all}
    source -notrace [file join $repo_dir tcl lesson05h_cpll_source_project.tcl]
    lesson05h_cpll_build $build_dir $part $action
    return
}

if {$top eq "lesson05g_cpll_top"} {
    set action [lindex $argv 3]
    if {$action eq ""} {set action all}
    source -notrace [file join $repo_dir tcl lesson05g_cpll_project.tcl]
    lesson05g_cpll_build $build_dir $part $action
    return
}

if {$top eq "lesson05f_si5338_top"} {
    source -notrace [file join $repo_dir tcl lesson05f_si5338_project.tcl]
    lesson05f_si5338_build $build_dir $part
    return
}

if {$top eq "lesson05e_gt_top"} {
    set action [lindex $argv 3]
    if {$action eq ""} {set action all}
    source -notrace [file join $repo_dir tcl lesson05e_gt_project.tcl]
    lesson05e_gt_build $build_dir $part $action
    return
}

if {$top in {lesson05d_monitor_pll lesson05d_ref_ungated lesson05d_ref_prescale lesson05d_raw_power lesson05d_clock_sanity lesson05d_clock_ungate lesson05d_clock_measure lesson05d_refclk_fix lesson05d_pll_audit}} {
    set root_guard [string tolower [string map {\\ /} $repo_dir]]
    set out_guard [string tolower [string map {\\ /} [file normalize $build_dir]]]
    if {$root_guard eq $out_guard || [string first "$root_guard/" "$out_guard/"]==0} {error "External diagnostic output directory required"}
    if {[llength $argv]!=4} {error "Diagnostic profile requires explicit parent checkpoint (unused for HDL clock measure)"}
}

if {$top eq "lesson05d_monitor_pll"} {
    source -notrace [file join $repo_dir tcl lesson05d_monitor_pll.tcl]
    lesson05d_monitor_pll $build_dir $part [lindex $argv 3]
    return
}

if {$top eq "lesson05d_ref_ungated"} {
    source -notrace [file join $repo_dir tcl lesson05d_ref_ungated.tcl]
    lesson05d_ref_ungated $build_dir $part [lindex $argv 3]
    return
}

if {$top eq "lesson05d_ref_prescale"} {
    source -notrace [file join $repo_dir tcl lesson05d_ref_prescale.tcl]
    lesson05d_ref_prescale $build_dir $part [lindex $argv 3]
    return
}

if {$top eq "lesson05d_raw_power"} {
    source -notrace [file join $repo_dir tcl lesson05d_raw_power.tcl]
    lesson05d_raw_power $build_dir $part [lindex $argv 3]
    return
}

if {$top eq "lesson05d_clock_sanity"} {
    source -notrace [file join $repo_dir tcl lesson05d_clock_sanity.tcl]
    lesson05d_clock_sanity $build_dir $part [lindex $argv 3]
    return
}

if {$top eq "lesson05d_clock_ungate"} {
    source -notrace [file join $repo_dir tcl lesson05d_clock_ungate.tcl]
    lesson05d_clock_ungate $build_dir $part [lindex $argv 3]
    return
}

if {$top eq "lesson05d_clock_measure"} {
    source -notrace [file join $repo_dir tcl lesson05d_clock_measure.tcl]
    lesson05d_clock_measure $build_dir $part [lindex $argv 3]
    return
}

if {$top eq "lesson05d_refclk_fix"} {
    source -notrace [file join $repo_dir tcl lesson05d_refclk_fix.tcl]
    lesson05d_refclk_fix $build_dir $part [lindex $argv 3]
    return
}

if {$top eq "lesson05d_pll_audit"} {
    set base [lindex $argv 3]
    if {$base eq "" || ![file exists $base]} {error "Explicit verified d5 checkpoint required"}
    source -notrace [file join $repo_dir tcl lesson05d_pll_audit.tcl]
    lesson05d_pll_audit $build_dir $part $base
    return
}

# Versioned board-specific flow; retain this file as the sole bitstream entry.
# Optional fourth argument: prepare (MCP), simulate, or all (default).
if {$top in {lesson05d_pcie_top lesson05d_pcie_x4_top lesson05d_pcie_training_top lesson05d_pcie_phy_top}} {
    set action [lindex $argv 3]
    if {$action eq ""} {set action all}
    if {$action ni {prepare all}} {error "Invalid lesson05d action"}
    source -notrace [file join $repo_dir tcl lesson05d_project.tcl]
    set lanes [expr {$top eq "lesson05d_pcie_top" ? 8 : 4}]
    lesson05d_prepare $build_dir $part $lanes [expr {$top in {lesson05d_pcie_training_top lesson05d_pcie_phy_top}}] [expr {$top eq "lesson05d_pcie_phy_top"}]
    if {$action ne "prepare"} {
        lesson05d_accept_simulation
        lesson05d_start_implementation
        wait_on_run impl_1
        lesson05d_collect_implementation
        close_project
    }
    return
}
if {$top eq "lesson05_board_top"} {
    set action [lindex $argv 3]
    if {$action eq ""} { set action all }
    if {$action ni {prepare simulate all}} { error "Invalid lesson05 action" }
    source -notrace [file join $repo_dir tcl lesson05_project.tcl]
    lesson05_prepare $build_dir $part
    if {$action ne "prepare"} {
        launch_simulation -mode behavioral
        lesson05_accept_simulation
        if {$action eq "all"} { lesson05_implement }
        close_project
    }
    return
}

file mkdir $build_dir
file mkdir $rpt_dir

create_project -force ku5p_build [file join $build_dir project] -part $part
set_property target_language Verilog [current_project]

set srcs [rglob $rtl_dir {*.v *.sv *.vhd}]
if {[llength $srcs] == 0} {
    puts "ERROR: no RTL sources found under $rtl_dir"
    exit 1
}
add_files -fileset sources_1 -norecurse $srcs

set xdcs [rglob $xdc_dir {*.xdc}]
if {[llength $xdcs] > 0} {
    add_files -fileset constrs_1 -norecurse $xdcs
}

set_property top $top [current_fileset]
update_compile_order -fileset sources_1

synth_design -top $top -part $part
report_utilization          -file [file join $rpt_dir post_synth_util.rpt]
report_timing_summary       -file [file join $rpt_dir post_synth_timing.rpt]

opt_design
place_design
route_design

report_utilization          -file [file join $rpt_dir post_route_util.rpt]
report_timing_summary       -file [file join $rpt_dir post_route_timing.rpt]
report_drc                  -file [file join $rpt_dir post_route_drc.rpt]

write_checkpoint -force [file join $build_dir ${top}_routed.dcp]
write_bitstream -force [file join $build_dir ${top}.bit]

log "BITSTREAM: [file join $build_dir ${top}.bit]"
exit
