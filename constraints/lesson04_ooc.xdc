# Replay arithmetic target only; no board pinout or physical clock source.
create_clock -name clk -period 10.000 [get_ports clk]
