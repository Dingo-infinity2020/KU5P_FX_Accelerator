# Authored subset checked against local FNIC-KU5P Rev1.0 schematic and manual.
# 100 MHz single-ended oscillator, bank 64 at 1.8 V; active-low LEDs in bank 84.
create_clock -name sys_clk -period 10.000 [get_ports SYS_CLK]
set_property -dict {PACKAGE_PIN AB21 IOSTANDARD LVCMOS18} [get_ports SYS_CLK]
set_property -dict {PACKAGE_PIN AF14 IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 4} [get_ports LED1]
set_property -dict {PACKAGE_PIN AF15 IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 4} [get_ports LED2]
# LEDs are human-visible status outputs without an external sampling clock.
set_false_path -to [get_ports {LED1 LED2}]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
