# Arithmetic-only out-of-context check. No board constraints or bitstream.
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
    set part ""
    foreach candidate {xcku5p-ffvb676-1-i xcku5p-ffva676-1-i} {
        if {[llength [get_parts -quiet $candidate]] != 0} {
            set part $candidate
            break
        }
    }
}
if {$part eq "" || [llength [get_parts -quiet $part]] == 0} {
    error "Requested/default KU5P part is not installed; provide an explicit installed part"
}

set report_dir [file join $build_dir reports]
file mkdir $report_dir
puts "LESSON01_PART=$part"
puts "SCOPE=Arithmetic-only OOC synthesis; no board pinout or routed timing validation"
create_project -in_memory -part $part
read_verilog -sv [file join $repo_dir rtl complex_power_accumulator.sv]
synth_design -mode out_of_context -top complex_power_accumulator -part $part
create_clock -name clk -period 10.000 [get_ports clk]
report_utilization -file [file join $report_dir utilization_synth.rpt]
report_timing_summary -file [file join $report_dir timing_synth.rpt]
write_checkpoint -force [file join $build_dir complex_power_accumulator_synth.dcp]
set summary [open [file join $build_dir synthesis_scope.txt] w]
puts $summary "part=$part"
puts $summary "scope=out-of-context synthesis only; no board validation or routed frequency guarantee"
puts $summary "requested_clock_period_ns=10.000"
close $summary
puts "LESSON01_SYNTHESIS_COMPLETE"
exit
