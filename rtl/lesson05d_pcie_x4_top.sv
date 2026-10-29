// Match the motherboard's electrical x4 slot to four reversed board lanes.
// VIO initially holds local PCIe reset asserted; hardware release is explicit.
module lesson05d_pcie_x4_top (
    input wire SYS_CLK,pcie_refclk_p,pcie_refclk_n,pcie_reset_n,
    input wire [3:0] pcie_rx_p,pcie_rx_n,
    output wire [3:0] pcie_tx_p,pcie_tx_n,
    output wire LED1,LED2
);
    lesson05d_pcie_top #(.PCIE_LANES(4),.MONITOR_BUILD_ID(32'h465805d3),.RESET_VIA_VIO(1)) core(.*);
endmodule
