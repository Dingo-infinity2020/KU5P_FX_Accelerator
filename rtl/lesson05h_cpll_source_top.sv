// Source-quad diagnostic counterpart, prepared separately from the e2 build.
// Its external project must generate lesson05g_cpll_gt for GTY X0Y0/bank224.
// Same body, CPLL5Gbps, nominal100MHz reference and management as e2;
// connector lane7 is not a PCIe data link on the current electrical x4 slot.
module lesson05h_cpll_source_top (
    input wire SYS_CLK,pcie_refclk_p,pcie_refclk_n,pcie_reset_n,
    input wire pcie_rx_p,pcie_rx_n,
    output wire pcie_tx_p,pcie_tx_n,
    output wire LED1,LED2
);
    wire monitor_clk,manual_reset,reset_all,qualifier_locked,qualifier_stopped;
    wire [95:0] observation;
    wire [31:0] heartbeat,ref_counter;
    wire [127:0] event_counters;
    gt_isolation_clocking system_clocking (.*);
    lesson05g_cpll_body body (.*);
    lesson05g_cpll_vio monitor (.clk(monitor_clk),.probe_in0(32'h465805e3),
        .probe_in1(observation),.probe_in2(heartbeat),.probe_in3(ref_counter),
        .probe_in4(event_counters),.probe_out0(manual_reset));
    lesson05g_cpll_ila capture (.clk(monitor_clk),.probe0(observation[31:0]),
        .probe1(event_counters));
    assign LED1=heartbeat[25];
    assign LED2=observation[1];
endmodule
