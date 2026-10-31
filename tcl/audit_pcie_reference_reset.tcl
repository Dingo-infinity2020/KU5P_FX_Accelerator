# Supporting read-only audit of an opened e5 routed checkpoint.
proc audit_pcie_reference_reset {path} {
    set gate [get_cells reference_reset/core_reset_gate]
    if {[llength $gate]!=1 || [get_property REF_NAME $gate] ne "LUT2"} {error "Reference reset gate missing"}
    set manual_nets [get_nets -segments -of_objects [get_pins monitor/probe_out0]]
    set manual_index -1
    foreach index {0 1} {
        foreach n [get_nets -segments -of_objects [get_pins $gate/I$index]] {
            if {$n in $manual_nets} {set manual_index $index}
        }
    }
    if {$manual_index<0} {error "Reference reset gate manual input differs"}
    set perst_index [expr {1-$manual_index}]
    if {pcie_reset_n ni [all_fanin -flat -startpoints_only -to [get_pins $gate/I$perst_index]]} {
        error "Reference reset gate physical PERST input differs"
    }
    set init_text [get_property INIT $gate]
    if {![regexp {^4'h([a-fA-F0-9])$} $init_text -> hex]} {error "Unexpected LUT truth table format"}
    scan $hex %x init
    foreach perst {0 1} {foreach manual {0 1} {
        set address [expr {($perst<<$perst_index)|($manual<<$manual_index)}]
        if {(($init>>$address)&1)!=($perst && !$manual)} {error "Reference reset gate truth table differs"}
    }}
    set gate_nets [get_nets -segments -of_objects [get_pins $gate/O]]
    foreach n [get_nets -segments -of_objects [get_pins dma/sys_rst_n]] {
        if {$n in $gate_nets} {set connected 1}
    }
    if {![info exists connected]} {error "XDMA reset is not driven by the reference gate"}
    set h [open $path {WRONLY CREAT EXCL}]
    puts $h "check\tvalue"
    puts $h "core_reset_gate_init\t[get_property INIT $gate]"
    puts $h "core_reset_gate_connected\t1"
    puts $h "perst_and_not_manual_truth_table\t1"
    set data [get_pins {reference_reset/reset_observer_pipe_reg[1]/D}]
    set previous [get_pins {reference_reset/reset_observer_pipe_reg[0]/Q}]
    foreach cell [get_cells {reference_reset/reset_observer_pipe_reg[0] reference_reset/reset_observer_pipe_reg[1]}] {
        if {![get_property ASYNC_REG $cell]} {error "Reference reset observer lacks ASYNC_REG"}
    }
    if {[get_nets -of_objects $data] ne [get_nets -of_objects $previous]} {error "Reset observation stages are not connected"}
    set timing [get_timing_paths -quiet -from $previous -to $data -max_paths 1]
    if {![llength $timing]} {error "Reset observation second stage is no longer timed"}
    puts $h "observation_stage2_timed\t1"
    puts $h "observation_stage2_slack\t[get_property SLACK $timing]"
    close $h
    puts REFERENCE_RESET_READONLY_AUDIT_PASS
}
