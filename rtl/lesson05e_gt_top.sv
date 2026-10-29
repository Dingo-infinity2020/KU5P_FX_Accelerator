module lesson05e_gt_top (
    input wire SYS_CLK,pcie_refclk_p,pcie_refclk_n,pcie_reset_n,
    input wire [3:0] pcie_rx_p,pcie_rx_n,
    output wire [3:0] pcie_tx_p,pcie_tx_n,
    output wire LED1,LED2
);
    wire monitor_clk,manual_reset,reset_all;
    wire [95:0] observation;
    wire [31:0] heartbeat;
    wire [1:0] clock_samples;
    wire qualifier_locked,qualifier_stopped;
    gt_isolation_clocking system_clocking (.*);
    gt_isolation_body body (.*);
    lesson05e_gt_vio monitor (.clk(monitor_clk),.probe_in0(32'h465805e1),
        .probe_in1(observation),.probe_in2(heartbeat),.probe_out0(manual_reset));
    lesson05e_gt_ila clock_capture (.clk(monitor_clk),.probe0(clock_samples));
    assign LED1=heartbeat[25];
    assign LED2=observation[4];
endmodule
