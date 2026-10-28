# Explicit JTAG SRAM programming and capture functions. Sourcing is read-only.
# Call lesson05_program only after validating the build manifest and bit/LTX.
proc lesson05_attach {} {
    open_hw_manager
    if {[llength [get_hw_servers -quiet]]==0} { connect_hw_server -url localhost:3121 }
    set targets [get_hw_targets -quiet */Digilent/*]
    if {[llength $targets]!=1} { error "Expected exactly one local Digilent target" }
    set target [lindex $targets 0]
    current_hw_target $target
    if {![get_property IS_OPENED $target]} { open_hw_target }
    set devices [get_hw_devices -quiet]
    if {[llength $devices]!=1 || [get_property PART [lindex $devices 0]] ne "xcku5p"} {
        error "Expected exactly one XCKU5P device"
    }
    current_hw_device [lindex $devices 0]
    return [lindex $devices 0]
}

proc lesson05_program {build_dir} {
    set build_dir [file normalize $build_dir]
    foreach name {verification.json lesson05_board_top.bit lesson05_board_top.ltx} {
        if {![file exists [file join $build_dir $name]]} { error "Missing verified artifact $name" }
    }
    set device [lesson05_attach]
    set_property PROGRAM.FILE [file join $build_dir lesson05_board_top.bit] $device
    set_property PROBES.FILE [file join $build_dir lesson05_board_top.ltx] $device
    program_hw_devices $device
    refresh_hw_device $device
    if {![get_property {REGISTER.CONFIG_STATUS.BIT[14]_DONE_PIN} $device]} { error "Configuration DONE is low" }
    if {[llength [get_hw_vios -of_objects $device]]!=1 || [llength [get_hw_ilas -of_objects $device]]!=1} {
        error "Expected one VIO and one ILA from lesson05"
    }
    set output_dir [file join $build_dir hardware]
    file mkdir $output_dir
    set h [open [file join $output_dir programmed.txt] w]
    puts $h "device=xcku5p\nconfiguration=JTAG_SRAM\nprogrammed_unix=[clock seconds]"
    puts $h "bit_mtime=[file mtime [file join $build_dir lesson05_board_top.bit]]"
    puts $h "bit_bytes=[file size [file join $build_dir lesson05_board_top.bit]]"
    puts $h "ltx_bytes=[file size [file join $build_dir lesson05_board_top.ltx]]"
    close $h
    puts "LESSON05_SRAM_PROGRAMMED device=xcku5p"
}

proc lesson05_unique_probe {core pattern} {
    set probes [get_hw_probes -quiet $pattern -of_objects $core]
    if {[llength $probes]!=1} { error "Expected one probe matching $pattern" }
    return [lindex $probes 0]
}

proc lesson05_capture {build_dir label} {
    if {![regexp {^[a-zA-Z0-9_-]+$} $label]} { error "Invalid capture label" }
    set device [lesson05_attach]
    set vio [get_hw_vios -of_objects $device]
    set ila [get_hw_ilas -of_objects $device]
    if {[llength $vio]!=1 || [llength $ila]!=1} { error "Load the verified lesson05 bitstream first" }
    set reset_probe [lesson05_unique_probe $vio *control_reset*]
    set start_probe [lesson05_unique_probe $vio *control_start*]
    set valid_probe [lesson05_unique_probe $ila *debug_valid*]
    set_property OUTPUT_VALUE 1 $reset_probe
    set_property OUTPUT_VALUE 0 $start_probe
    commit_hw_vio $vio
    refresh_hw_vio $vio
    set before_inputs [get_property INPUT_VALUE [lesson05_unique_probe $vio *input_count*]]
    set before_results [get_property INPUT_VALUE [lesson05_unique_probe $vio *result_count*]]
    if {![regexp {^(0x)?0+$} $before_inputs] || ![regexp {^(0x)?0+$} $before_results]} {
        error "VIO reset did not clear replay counters"
    }
    set_property CONTROL.DATA_DEPTH 2048 $ila
    set_property CONTROL.TRIGGER_POSITION 0 $ila
    set_property CONTROL.CAPTURE_MODE BASIC $ila
    set_property CONTROL.CAPTURE_CONDITION AND $ila
    set_property CAPTURE_COMPARE_VALUE eq1'b1 $valid_probe
    set_property CONTROL.TRIGGER_CONDITION AND $ila
    set_property TRIGGER_COMPARE_VALUE eq1'b1 $valid_probe
    # Arm before starting the ROM source; storage qualification keeps valid rows.
    run_hw_ila $ila
    set_property OUTPUT_VALUE 0 $reset_probe
    set_property OUTPUT_VALUE 1 $start_probe
    # Release reset and request start in the same VIO update, as in the TB.
    commit_hw_vio $vio
    wait_on_hw_ila -timeout 15 $ila
    set data [upload_hw_ila_data $ila]
    set output_dir [file join [file normalize $build_dir] hardware]
    file mkdir $output_dir
    write_hw_ila_data -force -csv_file [file join $output_dir ${label}.csv] $data
    write_hw_ila_data -force [file join $output_dir ${label}.ila] $data
    refresh_hw_vio $vio
    set h [open [file join $output_dir ${label}_vio.txt] w]
    puts $h "before_input_count $before_inputs\nbefore_result_count $before_results"
    foreach pattern {*debug_status* *input_count* *result_count* *signature* *run_cycles*} {
        set probe [lesson05_unique_probe $vio $pattern]
        puts $h "$pattern [get_property INPUT_VALUE $probe]"
    }
    close $h
    puts "LESSON05_CAPTURE=$output_dir/${label}.csv"
}
