// One GTY X0Y4, connector lane3, original PCIe reference. This fixed5Gbps
// experiment is not a PCIe endpoint. All physical serial transmission inhibited.
module lesson05g_cpll_body (
    input wire monitor_clk,qualifier_locked,qualifier_stopped,
    input wire pcie_refclk_p,pcie_refclk_n,pcie_reset_n,
    input wire pcie_rx_p,pcie_rx_n,
    output wire pcie_tx_p,pcie_tx_n,
    input wire manual_reset,
    output reg reset_all=1,
    output wire [95:0] observation,
    output reg [31:0] heartbeat=0,
    output wire [31:0] ref_counter,
    output wire [127:0] event_counters
);
    wire refclk,refclk_fabric,refclk_div8;
    wire powergood,locked,txpma,rxpma,helper_txdone,helper_rxdone;
    reg [15:0] qualification_wait=0;
    reg ref_qualified=0;
    // Use the same synchronized PG/MMCM observations for qualification and
    // diagnostics, rather than adding parallel synchronizers of these flags.
    always @(posedge monitor_clk) begin
        heartbeat<=heartbeat+1'b1;
        if(manual_reset || !observation[0] || !observation[6]) begin
            qualification_wait<=0;reset_all<=1;ref_qualified<=0;
        end else if(!(&qualification_wait)) begin
            qualification_wait<=qualification_wait+1'b1;reset_all<=1;ref_qualified<=0;
        end else begin reset_all<=0;ref_qualified<=1;end
    end
    IBUFDS_GTE4 #(.REFCLK_HROW_CK_SEL(2'b00)) reference_input (
        .I(pcie_refclk_p),.IB(pcie_refclk_n),.CEB(1'b0),.O(refclk),.ODIV2(refclk_fabric));
    // Gate only the diagnostic fabric branch, never the GT reference output O.
    // Tools insert BUFG_GT_SYNC for the CE transfer to the source clock.
    BUFG_GT #(.SIM_DEVICE("ULTRASCALE_PLUS")) reference_divider (
        .I(refclk_fabric),.CE(ref_qualified),.CEMASK(1'b0),.CLR(1'b0),.CLRMASK(1'b1),
        .DIV(3'b111),.O(refclk_div8));
    reg [31:0] ref_binary=0;
    always @(posedge refclk_div8) ref_binary<=ref_binary+1'b1;
    // No manual reset of the monotonic source counter: binary increments/hold
    // preserve the one-bit registered Gray transition across stopped clocks.
    xpm_cdc_gray #(.DEST_SYNC_FF(2),.INIT_SYNC_FF(1),.REG_OUTPUT(1),
        .SIM_ASSERT_CHK(1),.SIM_LOSSLESS_GRAY_CHK(0),.WIDTH(32)) reference_counter_cdc (
        .src_clk(refclk_div8),.src_in_bin(ref_binary),
        .dest_clk(monitor_clk),.dest_out_bin(ref_counter));

    lesson05g_cpll_gt transceivers (
        .gtwiz_userclk_tx_reset_in(~txpma),.gtwiz_userclk_rx_reset_in(~rxpma),
        .gtwiz_reset_clk_freerun_in(monitor_clk),.drpclk_in(monitor_clk),
        .gtwiz_reset_all_in(reset_all),.gtwiz_reset_tx_pll_and_datapath_in(1'b0),
        .gtwiz_reset_tx_datapath_in(1'b0),.gtwiz_reset_rx_pll_and_datapath_in(1'b0),
        .gtwiz_reset_rx_datapath_in(1'b0),.gtwiz_reset_tx_done_out(helper_txdone),
        .gtwiz_reset_rx_done_out(helper_rxdone),.gtwiz_userdata_tx_in(32'b0),
        .gtrefclk0_in(refclk),.cplllock_out(locked),.gtpowergood_out(powergood),
        .gtyrxp_in(pcie_rx_p),.gtyrxn_in(pcie_rx_n),
        .gtytxp_out(pcie_tx_p),.gtytxn_out(pcie_tx_n),
        .rx8b10ben_in(1'b1),.tx8b10ben_in(1'b1),
        .txctrl0_in(16'b0),.txctrl1_in(16'b0),.txctrl2_in(8'b0),
        .txelecidle_in(1'b1),.txinhibit_in(1'b1),
        .txpmaresetdone_out(txpma),.rxpmaresetdone_out(rxpma));
    cpll_diagnostics diagnostics (
        .monitor_clk(monitor_clk),
        .asynchronous_flags({qualifier_stopped,qualifier_locked,helper_rxdone,
            helper_txdone,rxpma,txpma,locked,powergood}),
        .control_observe(3'b000),.manual_reset(manual_reset),.reset_all(reset_all),
        .ref_qualified(ref_qualified),.pcie_reset_n(pcie_reset_n),
        .ref_counter(ref_counter),.heartbeat(heartbeat),
        .observation(observation),.event_counters(event_counters));
endmodule
