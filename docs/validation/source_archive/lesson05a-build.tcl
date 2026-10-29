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

# Versioned board-specific flow; retain this file as the sole bitstream entry.
# Optional fourth argument: prepare (MCP), simulate, or all (default).
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
