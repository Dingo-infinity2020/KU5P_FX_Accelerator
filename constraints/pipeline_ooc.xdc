# 125 MHz processing-clock target; no physical pinout or I/O timing claim.
create_clock -name clk -period 8.000 [get_ports clk]
