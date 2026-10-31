# Offline IP-generation experiment only. No synthesis or hardware commands.
# Both cases start in different empty projects; generated sources stay external.
if {[llength $argv] ni {1 2} || ([llength $argv]==2 && [lindex $argv 1] ne "probe_child_api")} {
    error "Usage: reproduce_xdma_lane_config.tcl fresh_output_dir ?probe_child_api?"
}
set probe [expr {[llength $argv]==2}]
set out [file normalize [lindex $argv 0]]
set repo [file normalize [file join [file dirname [info script]] ..]]
if {[string first "[string tolower $repo]/" "[string tolower $out]/"]==0 || [file exists $out]} {
    error "Use a fresh external output directory"
}
if {[version -short] ne "2026.1"} {error "This reproducer requires Vivado 2026.1"}
file mkdir $out
set cases [expr {$probe ? [list true] : [list false true]}]
foreach reversal $cases {
    set directory [file join $out reversal_$reversal]
    create_project cfg_repro $directory -part xcku5p-ffvb676-1-i
    file mkdir [file join $directory ip]
    create_ip -name xdma -vendor xilinx.com -library ip -version 4.2 \
        -module_name cfg_xdma -dir [file join $directory ip]
    set_property -dict [list CONFIG.mode_selection Advanced \
        CONFIG.pl_link_cap_max_link_width X4 CONFIG.pl_link_cap_max_link_speed 8.0_GT/s \
        CONFIG.axi_data_width 256_bit CONFIG.axisten_freq 125 \
        CONFIG.xdma_axi_intf_mm AXI_Stream CONFIG.axilite_master_en true \
        CONFIG.axilite_master_scale Kilobytes CONFIG.axilite_master_size 4 \
        CONFIG.ref_clk_freq 100_MHz CONFIG.en_gt_selection true \
        CONFIG.select_quad GTY_Quad_225 CONFIG.enable_lane_reversal $reversal \
        CONFIG.xdma_rnum_chnl 1 CONFIG.xdma_wnum_chnl 1 CONFIG.en_debug_ports false \
        CONFIG.ext_sys_clk_bufg true CONFIG.enable_pcie_debug_ports True \
        CONFIG.en_transceiver_status_ports true] [get_ips cfg_xdma]
    report_property [get_ips cfg_xdma] -file [file join $directory parent_properties.txt]
    generate_target all [get_ips cfg_xdma]
    if {$probe} {
        # Ask the documented IP-property interface; never unlock a managed IP
        # or edit its generated files if the interface rejects customization.
        set child [get_ips -all cfg_xdma_pcie4_ip]
        set before [get_property CONFIG.PL_DISABLE_LANE_REVERSAL $child]
        set failed [catch {set_property CONFIG.PL_DISABLE_LANE_REVERSAL FALSE $child} message]
        set h [open [file join $directory child_api_probe.tcldict] {WRONLY CREAT EXCL}]
        puts $h [dict create before $before customization_rejected $failed message $message]
        close $h
        if {!$failed} {
            generate_target all [get_ips cfg_xdma]
            set h [open [file join $directory child_after_parent_regeneration.txt] {WRONLY CREAT EXCL}]
            puts $h [get_property CONFIG.PL_DISABLE_LANE_REVERSAL [get_ips -all cfg_xdma_pcie4_ip]]
            close $h
        }
    }
    set h [open [file join $directory generated_ips.txt] {WRONLY CREAT EXCL}]
    foreach ip [get_ips -all] {puts $h "$ip\t[get_property IPDEF $ip]\t[get_property IP_FILE $ip]"}
    close $h
    close_project
    puts "LANE_CONFIG_GENERATED reversal=$reversal"
}
set h [open [file join $out generation_complete.txt] {WRONLY CREAT EXCL}]
puts $h "PASS tool=2026.1 xdma=4.2 cases=[llength $cases] scope=GENERATION_ONLY child_api_probe=$probe"
close $h
puts "LANE_CONFIG_REPRODUCTION_COMPLETE"
