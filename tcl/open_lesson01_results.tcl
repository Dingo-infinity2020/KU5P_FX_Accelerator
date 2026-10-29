# Source this in an empty Vivado GUI session to inspect existing synthesis.
# This script does not build a bitstream or connect to a board.
set lesson01_repo_dir [file normalize [file join [file dirname [info script]] ..]]
set lesson01_result_dir [file normalize [file join $lesson01_repo_dir .. build KU5P_FX_Accelerator lesson01_power]]
set lesson01_checkpoint [file join $lesson01_result_dir complex_power_accumulator_synth.dcp]
if {![file exists $lesson01_checkpoint]} {
    error "Missing lesson01 checkpoint. Run scripts/run_lesson01.ps1 with -Synthesize first."
}
if {[current_design -quiet] ne ""} {
    error "A design is already open. Use a separate empty Vivado window to inspect lesson01."
}
open_checkpoint $lesson01_checkpoint
report_utilization -name lesson01_utilization
set lesson01_dsp_cells [get_cells -hierarchical -filter {REF_NAME == DSP48E2}]
puts "LESSON01_INSPECTION_PART=[get_property PART [current_design]]"
puts "LESSON01_DSP_COUNT=[llength $lesson01_dsp_cells]"
puts "LESSON01_DSP_CELLS=$lesson01_dsp_cells"
puts "LESSON01_SCOPE=Synthesized design only; no placement, routing or hardware programming."
