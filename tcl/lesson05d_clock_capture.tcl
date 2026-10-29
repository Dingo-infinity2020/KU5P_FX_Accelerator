# Sourcing performs no action. Call only after a verified clock ILA image is loaded.
proc lesson05d_capture_clock {build_dir label} {
    if {![regexp {^[a-zA-Z0-9_-]+$} $label]} {error "Invalid capture label"}
    set device [lesson05d_attach]
    set ila [get_hw_ilas -of_objects $device]
    if {[llength $ila]!=1} {error "Expected one clock ILA"}
    set probe [get_hw_probes -of_objects $ila]
    if {[llength $probe]!=1 || [get_property WIDTH $probe]!=2} {error "Expected two clock bits"}
    set_property CONTROL.DATA_DEPTH 4096 $ila
    set_property CONTROL.TRIGGER_POSITION 0 $ila
    if {[get_property CONTROL.CAPTURE_MODE $ila] ne "ALWAYS"} {error "Unqualified capture required"}
    set_property DISPLAY_RADIX HEX $probe
    run_hw_ila -trigger_now $ila
    wait_on_hw_ila -timeout 15 $ila
    set data [upload_hw_ila_data $ila]
    set out [file join [file normalize $build_dir] hardware]
    file mkdir $out
    write_hw_ila_data -force -csv_file [file join $out ${label}.csv] $data
    write_hw_ila_data -force [file join $out ${label}.ila] $data
    puts "CLOCK_CAPTURE=$label"
}
