# Arithmetic-module clock target. No board pins, I/O delays or clock source.
# Read before synthesis so the timing-driven synthesizer sees the target.
create_clock -name clk -period 10.000 [get_ports clk]
