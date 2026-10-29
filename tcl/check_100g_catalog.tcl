# Catalog-only preparation. No IP output generation or hardware access.
set ::cmac_catalog_source_root [file normalize [file join [file dirname [info script]] ..]]

proc check_100g_catalog {output_dir} {
    if {[current_project -quiet] ne ""} {
        error "Close the current project before the catalog-only check"
    }
    set out [file normalize $output_dir]
    set root [string tolower [string map {\\ /} $::cmac_catalog_source_root]]
    set normalized [string tolower [string map {\\ /} $out]]
    if {$normalized eq $root || [string first "$root/" "$normalized/"] == 0} {
        error "Write preparation reports outside the source repository"
    }
    file mkdir $out
    set part xcku5p-ffvb676-1-i
    create_project -in_memory -part $part cmac_catalog_preflight
    try {
        set defs [get_ipdefs -quiet -all xilinx.com:ip:cmac_usplus:*]
        set report [open [file join $out cmac_catalog.tsv] w]
        try {
            puts $report "vivado_version\t[version -short]"
            puts $report "part\t$part"
            puts $report "catalog_entries\t[llength $defs]"
            foreach ipdef $defs {
                set families [get_property SUPPORTED_FAMILIES $ipdef]
                set listed [expr {[string first ":$part:" $families] >= 0}]
                puts $report "vlnv\t[get_property VLNV $ipdef]"
                puts $report "part_listed\t$listed"
                puts $report "requires_license\t[get_property REQUIRES_LICENSE $ipdef]"
                puts $report "license_keys\t[get_property LICENSE_KEYS $ipdef]"
            }
            puts $report "license_checkout_tested\t0"
            puts $report "ip_generated\t0"
            puts $report "board_network_tested\t0"
        } finally {close $report}
    } finally {close_project}
    puts "CMAC catalog report: [file join $out cmac_catalog.tsv]"
}
