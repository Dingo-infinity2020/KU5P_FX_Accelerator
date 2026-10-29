proc lesson05f_si5338_audit {out} {
    set h [open [file join $out reports pins.tsv] w];puts $h "port\tpin\tiostandard\tdirection"
    foreach {name pin ios direction} {SYS_CLK AB21 LVCMOS18 IN SI5338_SCL F14 LVCMOS33 INOUT SI5338_SDA F13 LVCMOS33 INOUT SI5338_INTR E13 LVCMOS33 IN SI5338_I2C_LSB E12 LVCMOS33 IN CLK_SEL D13 LVCMOS33 IN LED1 AF14 LVCMOS33 OUT LED2 AF15 LVCMOS33 OUT} {
        set p [get_ports $name]
        if {[get_property PACKAGE_PIN $p] ne $pin || [get_property IOSTANDARD $p] ne $ios || [get_property DIRECTION $p] ne $direction} {error "Clock-chip port mismatch: $name"}
        puts $h "$name\t$pin\t$ios\t$direction"
    };close $h
    set h [open [file join $out reports open_drain.tsv] w];puts $h "cell\tinput_driver\ttristate_driver"
    foreach name {scl_buffer sda_buffer} {
        set cell [get_cells $name]
        if {[get_property REF_NAME $cell] ne "IOBUF"} {error "Expected open-drain IOBUF"}
        set drivers [get_cells -of_objects [get_pins -of_objects [get_nets -segments -of_objects [get_pins $name/I]] -filter {DIRECTION==OUT}]]
        if {[llength $drivers]!=1 || [get_property REF_NAME $drivers] ne "GND"} {error "I2C output can drive high"}
        puts $h "$name\tGND\t[get_pins -of_objects [get_nets -segments -of_objects [get_pins $name/T]] -filter {DIRECTION==OUT}]"
    };close $h
    if {[llength [get_cells -hier -quiet -filter {REF_NAME==GTYE4_CHANNEL || REF_NAME==PCIE40E4}]]} {error "Unexpected serial/DMA logic"}
}
proc lesson05f_si5338_build {out part} {
    global repo_dir
    if {$part ne "xcku5p-ffvb676-1-i"} {error "Unverified part"}
    set out [file normalize $out]
    set root_guard [string tolower [string map {\\ /} $repo_dir]]
    set out_guard [string tolower [string map {\\ /} $out]]
    if {$out_guard eq $root_guard || [string first "$root_guard/" "$out_guard/"]==0} {error "External build required"}
    if {![file exists [file join $out inputs.json]] || ![file exists [file join $out i2c_sim simulation_pass.txt]]} {error "Freeze sources and pass I2C simulation first"}
    file mkdir [file join $out reports]
    set project_file [file join $out vivado_project si5338_readonly.xpr]
    if {[file exists $project_file]} {open_project $project_file} else {create_project si5338_readonly [file join $out vivado_project] -part $part}
    foreach name {i2c_register_readonly.sv lesson05f_si5338_top.sv} {
        set path [file join $repo_dir rtl $name]
        if {![llength [get_files -quiet $path]]} {add_files -norecurse $path}
    }
    set path [file join $repo_dir constr lesson05f_si5338.xdc]
    if {![llength [get_files -quiet $path]]} {add_files -fileset constrs_1 -norecurse $path}
    set ip_dir [file join $out vivado_project ip];file mkdir $ip_dir
    foreach {module ip version config} [list lesson05f_si5338_vio vio 3.0 {CONFIG.C_NUM_PROBE_IN 3 CONFIG.C_NUM_PROBE_OUT 2 CONFIG.C_PROBE_IN0_WIDTH 32 CONFIG.C_PROBE_IN1_WIDTH 64 CONFIG.C_PROBE_IN2_WIDTH 32 CONFIG.C_PROBE_OUT0_WIDTH 9 CONFIG.C_PROBE_OUT1_WIDTH 1 CONFIG.C_PROBE_OUT0_INIT_VAL 0x000 CONFIG.C_PROBE_OUT1_INIT_VAL 0x0} \
        lesson05f_si5338_ila ila 6.2 {CONFIG.C_NUM_OF_PROBES 2 CONFIG.C_PROBE0_WIDTH 8 CONFIG.C_PROBE1_WIDTH 1 CONFIG.C_DATA_DEPTH 8192}] {
        if {![llength [get_ips -quiet $module]]} {
            create_ip -name $ip -vendor xilinx.com -library ip -version $version -module_name $module -dir $ip_dir
            set_property -dict $config [get_ips $module]
        } else {
            foreach {key value} $config {if {![string equal -nocase [get_property $key [get_ips $module]] $value]} {error "IP configuration changed: $module $key"}}
        }
        generate_target all [get_ips $module]
        set_property GENERATE_SYNTH_CHECKPOINT false [get_files [get_property IP_FILE [get_ips $module]]]
    }
    set_property top lesson05f_si5338_top [get_filesets sources_1]
    synth_design -top lesson05f_si5338_top -part $part
    opt_design;place_design;route_design
    set reports [file join $out reports]
    foreach {cmd file} {report_timing_summary timing.rpt check_timing check_timing.rpt report_route_status route.rpt report_drc drc.rpt report_utilization utilization.rpt report_clocks clocks.rpt} {$cmd -file [file join $reports $file]}
    report_cdc -details -no_waiver -file [file join $reports cdc.rpt]
    lesson05f_si5338_audit $out
    foreach delay {max min} {if {[llength [get_timing_paths -quiet -delay_type $delay -slack_lesser_than 0 -max_paths 1]]} {error "Timing failed"}}
    write_checkpoint -force [file join $out lesson05f_si5338_top_routed.dcp]
    write_debug_probes -force [file join $out lesson05f_si5338_top.ltx]
    write_bitstream -force [file join $out lesson05f_si5338_top.bit]
    puts SI5338_READONLY_BUILD_COMPLETE
}
