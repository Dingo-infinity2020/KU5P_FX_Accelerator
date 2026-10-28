# Arithmetic-only OOC synthesis, with the clock constraint read before synth.
if {[llength $argv] < 1} {
    error "Usage: -tclargs <external_build_dir> \[part\]"
}
set repo_dir [file normalize [file join [file dirname [info script]] ..]]
set build_dir [file normalize [lindex $argv 0]]
set repo_lower [string tolower [string map {\\ /} $repo_dir]]
set build_lower [string tolower [string map {\\ /} $build_dir]]
if {$build_lower eq $repo_lower || [string first "$repo_lower/" "$build_lower/"] == 0} {
    error "Build directory must be outside the repository"
}
if {[llength $argv] > 1} {
    set part [lindex $argv 1]
} else {
    set part xcku5p-ffvb676-1-i
}
if {[llength [get_parts -quiet $part]] != 1} {
    error "Requested KU5P part is not installed: $part"
}

set report_dir [file join $build_dir reports]
file mkdir $report_dir
puts "LESSON02_PART=$part"
create_project -in_memory -part $part
read_verilog -sv [file join $repo_dir rtl two_channel_correlator.sv]
read_xdc [file join $repo_dir constraints lesson02_ooc.xdc]
synth_design -mode out_of_context -top two_channel_correlator -part $part
report_utilization -file [file join $report_dir utilization_synth.rpt]
report_timing_summary -file [file join $report_dir timing_synth.rpt]
check_timing -verbose -file [file join $report_dir check_timing_synth.rpt]
write_checkpoint -force [file join $build_dir two_channel_correlator_synth.dcp]
set summary [open [file join $build_dir synthesis_scope.txt] w]
puts $summary "part=$part"
puts $summary "tool=[version -short]"
puts $summary "scope=out-of-context synthesis only; no board validation or routed frequency guarantee"
puts $summary "requested_clock_period_ns=10.000"
puts $summary "clock_constraint_read_before_synthesis=true"
close $summary
puts "LESSON02_SYNTHESIS_COMPLETE"
exit
