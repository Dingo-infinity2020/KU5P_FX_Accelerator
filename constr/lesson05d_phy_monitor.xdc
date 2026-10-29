# Each flag is independently synchronized, with no encoded bus reconstruction.
set_false_path -to [get_pins -hier -filter {NAME =~ *phy_monitor/sample1_reg*/D}]
