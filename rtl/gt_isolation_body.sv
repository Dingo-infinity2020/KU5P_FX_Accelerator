// Four-channel, fixed-rate QPLL1 experiment. No PCIe controller or DMA.
// Wizard vector bit0 is GTY X0Y4, which is board connector lane3.
module gt_isolation_body #(parameter integer SIM_SINGLE_CHANNEL=0) (
    input wire monitor_clk,qualifier_locked,qualifier_stopped,
    input wire pcie_refclk_p,pcie_refclk_n,pcie_reset_n,
    input wire [3:0] pcie_rx_p,pcie_rx_n,
    output wire [3:0] pcie_tx_p,pcie_tx_n,
    input wire manual_reset,
    output wire reset_all,
    output wire [95:0] observation,
    output reg [31:0] heartbeat=0,
    output wire [1:0] clock_samples
);
    gt_isolation_reset reset_control (.clk(monitor_clk),.manual_reset(manual_reset),
        .qualifier_locked_async(qualifier_locked),.reset_all(reset_all));

    wire refclk,refclk_fabric,refclk_div8;
    IBUFDS_GTE4 #(.REFCLK_HROW_CK_SEL(2'b00)) reference_input (
        .I(pcie_refclk_p),.IB(pcie_refclk_n),.CEB(1'b0),.O(refclk),.ODIV2(refclk_fabric));
    BUFG_GT #(.SIM_DEVICE("ULTRASCALE_PLUS")) reference_divider (
        .I(refclk_fabric),.CE(1'b1),.CEMASK(1'b1),.CLR(1'b0),.CLRMASK(1'b1),
        .DIV(3'b111),.O(refclk_div8));
    reg [4:0] ref_counter=0;
    always @(posedge refclk_div8) ref_counter<=ref_counter+1'b1;
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) reg ref_meta=0,ref_sync=0;
    always @(posedge monitor_clk) begin
        ref_meta<=ref_counter[4];ref_sync<=ref_meta;
        heartbeat<=heartbeat+1'b1;
    end
    assign clock_samples={heartbeat[7],ref_sync};

    wire [3:0] powergood,txpma,rxpma,txdone,rxdone,txp,txn;
    wire qpll1lock,helper_txdone,helper_rxdone,txactive,rxactive;
    wire tx_clock_reset=SIM_SINGLE_CHANNEL ? ~txpma[0] : ~(&txpma);
    wire rx_clock_reset=SIM_SINGLE_CHANNEL ? ~rxpma[0] : ~(&rxpma);
    generate if(SIM_SINGLE_CHANNEL) begin: single_channel_model
    // Explicitly smaller simulation scope for BASIC's model instance limit.
    // Unused lanes are zero, never represented as simulated working channels.
    assign powergood[3:1]=0;assign txpma[3:1]=0;assign rxpma[3:1]=0;
    assign txdone[3:1]=0;assign rxdone[3:1]=0;assign txp[3:1]=0;assign txn[3:1]=0;
    lesson05e_gtwizard_single_sim transceivers (
        .gtwiz_userclk_tx_reset_in(tx_clock_reset),.gtwiz_userclk_rx_reset_in(rx_clock_reset),
        .gtwiz_userclk_tx_active_out(txactive),.gtwiz_userclk_rx_active_out(rxactive),
        .gtwiz_reset_clk_freerun_in(monitor_clk),.gtwiz_reset_all_in(reset_all),
        .gtwiz_reset_tx_pll_and_datapath_in(1'b0),.gtwiz_reset_tx_datapath_in(1'b0),
        .gtwiz_reset_rx_pll_and_datapath_in(1'b0),.gtwiz_reset_rx_datapath_in(1'b0),
        .gtwiz_reset_tx_done_out(helper_txdone),.gtwiz_reset_rx_done_out(helper_rxdone),
        .gtwiz_userdata_tx_in(32'b0),.gtrefclk01_in(refclk),.qpll1lock_out(qpll1lock),
        .gtyrxp_in(pcie_rx_p[3]),.gtyrxn_in(pcie_rx_n[3]),
        .gtytxp_out(txp[0]),.gtytxn_out(txn[0]),.rx8b10ben_in(1'b1),.tx8b10ben_in(1'b1),
        .txctrl0_in(16'b0),.txctrl1_in(16'b0),.txctrl2_in(8'b0),
        .txelecidle_in(1'b1),.txinhibit_in(1'b1),.gtpowergood_out(powergood[0]),
        .txpmaresetdone_out(txpma[0]),.rxpmaresetdone_out(rxpma[0]),
        .txresetdone_out(txdone[0]),.rxresetdone_out(rxdone[0]));
    end else begin: four_channel_hardware
    lesson05e_gtwizard transceivers (
        .gtwiz_userclk_tx_reset_in(tx_clock_reset),.gtwiz_userclk_rx_reset_in(rx_clock_reset),
        .gtwiz_userclk_tx_active_out(txactive),.gtwiz_userclk_rx_active_out(rxactive),
        .gtwiz_reset_clk_freerun_in(monitor_clk),.gtwiz_reset_all_in(reset_all),
        .gtwiz_reset_tx_pll_and_datapath_in(1'b0),.gtwiz_reset_tx_datapath_in(1'b0),
        .gtwiz_reset_rx_pll_and_datapath_in(1'b0),.gtwiz_reset_rx_datapath_in(1'b0),
        .gtwiz_reset_tx_done_out(helper_txdone),.gtwiz_reset_rx_done_out(helper_rxdone),
        .gtwiz_userdata_tx_in(128'b0),.gtrefclk01_in(refclk),.qpll1lock_out(qpll1lock),
        .gtyrxp_in({pcie_rx_p[0],pcie_rx_p[1],pcie_rx_p[2],pcie_rx_p[3]}),
        .gtyrxn_in({pcie_rx_n[0],pcie_rx_n[1],pcie_rx_n[2],pcie_rx_n[3]}),
        .gtytxp_out(txp),.gtytxn_out(txn),.rx8b10ben_in(4'hf),.tx8b10ben_in(4'hf),
        .txctrl0_in(64'b0),.txctrl1_in(64'b0),.txctrl2_in(32'b0),
        .txelecidle_in(4'hf),.txinhibit_in(4'hf),
        .gtpowergood_out(powergood),.txpmaresetdone_out(txpma),.rxpmaresetdone_out(rxpma),
        .txresetdone_out(txdone),.rxresetdone_out(rxdone));
    end endgenerate
    assign pcie_tx_p={txp[0],txp[1],txp[2],txp[3]};
    assign pcie_tx_n={txn[0],txn[1],txn[2],txn[3]};

    // Raw RESETDONE and userclk ACTIVE already enter Wizard synchronizers in
    // this same destination domain. A second parallel diagnostic synchronizer
    // creates CDC-11 fan-out; observe the helper's synchronized aggregate done.
    // Bits13..20 and23..24 are reserved, not raw per-channel reset/clock flags.
    wire [31:0] flags={1'b0,heartbeat[7],pcie_reset_n,manual_reset,reset_all,
        qualifier_stopped,qualifier_locked,2'b0,helper_rxdone,helper_txdone,
        8'b0,rxpma,txpma,qpll1lock,powergood};
    pcie_phy_monitor #(.WIDTH(32)) flag_monitor (.monitor_clk(monitor_clk),
        .flags_async(flags),.observation(observation));
endmodule
