# Create an inspectable GUI project outside the repository. No source copies,
# implementation, bitstream, board connection or overwrite of existing project.
# Batch: -tclargs <external_build_dir> [part]
# Empty GUI: source this script (uses the default external build directory).
set lesson02_repo [file normalize [file join [file dirname [info script]] ..]]
set lesson02_build [file normalize [file join $lesson02_repo .. build KU5P_FX_Accelerator lesson02_x]]
set lesson02_part xcku5p-ffvb676-1-i
if {[info exists argv] && [llength $argv] > 0} {
    set lesson02_build [file normalize [lindex $argv 0]]
    if {[llength $argv] > 1} { set lesson02_part [lindex $argv 1] }
}
set lesson02_repo_lower [string tolower [string map {\\ /} $lesson02_repo]]
set lesson02_build_lower [string tolower [string map {\\ /} $lesson02_build]]
if {$lesson02_build_lower eq $lesson02_repo_lower
    || [string first "$lesson02_repo_lower/" "$lesson02_build_lower/"] == 0} {
    error "Build directory must be outside the repository"
}
if {[current_project -quiet] ne ""} {
    error "A project is already open. Use a separate empty Vivado window."
}
set lesson02_project_dir [file join $lesson02_build vivado_project]
set lesson02_xpr [file join $lesson02_project_dir lesson02_x.xpr]
if {[file exists $lesson02_xpr]} {
    puts "Existing project: $lesson02_xpr"
    puts "Open it with: open_project {$lesson02_xpr}"
} else {
    set lesson02_vectors [file join $lesson02_build windows.txt]
    if {![file exists $lesson02_vectors]} {
        error "Missing reference vectors. Run scripts/run_lesson02.ps1 first."
    }
    create_project lesson02_x $lesson02_project_dir -part $lesson02_part
    add_files -norecurse [file join $lesson02_repo rtl two_channel_correlator.sv]
    set_property top two_channel_correlator [get_filesets sources_1]
    add_files -fileset constrs_1 -norecurse [file join $lesson02_repo constraints lesson02_ooc.xdc]
    add_files -fileset sim_1 -norecurse [file join $lesson02_repo sim tb_two_channel_correlator.sv]
    add_files -fileset sim_1 -norecurse $lesson02_vectors
    set_property file_type {Data Files} [get_files $lesson02_vectors]
    set_property top tb_two_channel_correlator [get_filesets sim_1]
    set_property xsim.simulate.runtime all [get_filesets sim_1]
    set_property xsim.simulate.log_all_signals true [get_filesets sim_1]
    # Keep Run Synthesis consistent with the standalone arithmetic-only check.
    set_property -dict [list {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} {-mode out_of_context}] [get_runs synth_1]
    update_compile_order -fileset sources_1
    update_compile_order -fileset sim_1
    puts "LESSON02_PROJECT=$lesson02_xpr"
    puts "Use Run Simulation > Run Behavioral Simulation to reproduce the test."
}
