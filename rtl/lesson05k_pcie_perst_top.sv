// e6: PERST-only vendor reset entrance. VIO output0 is reserved, not PHY reset.
// Monitor clock is independent of PCIe, so VIO remains usable before link-up.
module lesson05k_pcie_perst_top (
    input wire SYS_CLK,pcie_refclk_p,pcie_refclk_n,pcie_reset_n,
    input wire [3:0] pcie_rx_p,pcie_rx_n,
    output wire [3:0] pcie_tx_p,pcie_tx_n,
    output wire LED1,LED2
);
    wire sys_input,monitor_clk,sys_clk,sys_clk_gt;
    IBUF monitor_input(.I(SYS_CLK),.O(sys_input));
    BUFG monitor_buffer(.I(sys_input),.O(monitor_clk));
    IBUFDS_GTE4 #(.REFCLK_HROW_CK_SEL(2'b00)) reference_input (
        .I(pcie_refclk_p),.IB(pcie_refclk_n),.CEB(1'b0),.O(sys_clk_gt),.ODIV2(sys_clk)
    );
    wire reference_fabric_clk,sys_clk_ce,sync_sc_ce,sync_sc_clr,ref_div_clk;
    // Same input and synchronized CE/CLR as the functional buffer; only the
    // observation buffer masks them. No change to the core reference path.
    BUFG_GT #(.SIM_DEVICE("ULTRASCALE_PLUS")) ref_observer_buffer (
        .I(sys_clk),.CE(sync_sc_ce),.CEMASK(1'b1),.CLR(sync_sc_clr),
        .CLRMASK(1'b1),.DIV(3'b111),.O(ref_div_clk));
    // The IP's external-buffer option exports GTPOWERGOOD as sys_clk_ce_out.
    // Share this single synchronized buffer between XDMA and its observer.
    BUFG_GT_SYNC reference_monitor_sync (
        .CLK(sys_clk),.CE(sys_clk_ce),.CLR(1'b0),.CESYNC(sync_sc_ce),.CLRSYNC(sync_sc_clr)
    );
    BUFG_GT reference_monitor_buffer (
        .I(sys_clk),.CE(sync_sc_ce),.CEMASK(1'b0),.CLR(sync_sc_clr),.CLRMASK(1'b0),.DIV(3'b000),.O(reference_fabric_clk)
    );
    wire axi_clk,axi_rst_n,link_up,msi_enabled,debug_pcie_reset;
    wire [31:0] awaddr,wdata,araddr,rdata,c2h_keep,h2c_keep;
    wire [3:0] wstrb;
    wire awvalid,awready,wvalid,wready,bvalid,bready,arvalid,arready,rvalid,rready;
    wire [1:0] bresp,rresp;
    wire [255:0] c2h_data;
    wire c2h_valid,c2h_ready,c2h_last,h2c_valid,h2c_ready,h2c_last,busy,done;
    wire [31:0] accepted_beats,completed_packets,signature;
    pcie_test_endpoint application (
        .clk(axi_clk),.rst_n(axi_rst_n),.link_up(link_up),
        .s_axil_awaddr(awaddr),.s_axil_awvalid(awvalid),.s_axil_awready(awready),
        .s_axil_wdata(wdata),.s_axil_wstrb(wstrb),.s_axil_wvalid(wvalid),.s_axil_wready(wready),
        .s_axil_bresp(bresp),.s_axil_bvalid(bvalid),.s_axil_bready(bready),
        .s_axil_araddr(araddr),.s_axil_arvalid(arvalid),.s_axil_arready(arready),
        .s_axil_rdata(rdata),.s_axil_rresp(rresp),.s_axil_rvalid(rvalid),.s_axil_rready(rready),
        .c2h_data(c2h_data),.c2h_keep(c2h_keep),.c2h_last(c2h_last),.c2h_valid(c2h_valid),.c2h_ready(c2h_ready),
        .h2c_valid(h2c_valid),.h2c_last(h2c_last),.h2c_keep(h2c_keep),.h2c_ready(h2c_ready),
        .busy(busy),.done(done),.accepted_beats(accepted_beats),.completed_packets(completed_packets),.signature(signature)
    );
    wire [3:0] gt_txresetdone,gt_rxresetdone,gt_rxpmaresetdone,gt_txpmaresetdone,gt_cplllock,gt_txprogdivresetdone,gt_txsyncdone,gt_rxsyncdone,gt_rxcdrlock;
    wire gt_qpll0lock,gt_qpll1lock,phy_rst_idle,phy_rrst_n,phy_prst_n;
    wire endpoint_reset_n,perst_seen,reset_observed_n;
    pcie_perst_reference_reset reference_reset (
        .monitor_clk(monitor_clk),.pcie_reset_n(pcie_reset_n),
        .perst_seen(perst_seen),
        .core_reset_n(endpoint_reset_n),.reset_observed_n(reset_observed_n));
    lesson05d_xdma dma (
        .sys_clk(reference_fabric_clk),.sys_clk_ce_out(sys_clk_ce),.sys_clk_gt(sys_clk_gt),.sys_rst_n(endpoint_reset_n),.user_lnk_up(link_up),
        .pci_exp_txp(pcie_tx_p),.pci_exp_txn(pcie_tx_n),.pci_exp_rxp(pcie_rx_p),.pci_exp_rxn(pcie_rx_n),
        .axi_aclk(axi_clk),.axi_aresetn(axi_rst_n),.usr_irq_req(1'b0),.usr_irq_ack(),
        .msi_enable(msi_enabled),.msi_vector_width(),
        .m_axil_awaddr(awaddr),.m_axil_awprot(),.m_axil_awvalid(awvalid),.m_axil_awready(awready),
        .m_axil_wdata(wdata),.m_axil_wstrb(wstrb),.m_axil_wvalid(wvalid),.m_axil_wready(wready),
        .m_axil_bvalid(bvalid),.m_axil_bresp(bresp),.m_axil_bready(bready),
        .m_axil_araddr(araddr),.m_axil_arprot(),.m_axil_arvalid(arvalid),.m_axil_arready(arready),
        .m_axil_rdata(rdata),.m_axil_rresp(rresp),.m_axil_rvalid(rvalid),.m_axil_rready(rready),
        // Match the disabled-debug IP wrapper tie-offs exactly.
        .gt_pcieuserratedone(4'b0),
        .gt_loopback(12'b0),
        .gt_txprbsforceerr(4'b0),
        .gt_txinhibit(4'b0),
        .gt_txprbssel(16'b0),
        .gt_rxprbssel(16'b0),
        .gt_rxprbscntreset(4'b0),
        .gt_dmonfiforeset(4'b0),
        .gt_dmonitorclk(4'b0),
        .gt_txpmareset(4'b0),
        .gt_rxpmareset(4'b0),
        .gt_txpcsreset(4'b0),
        .gt_rxpcsreset(4'b0),
        .gt_rxbufreset(4'b0),
        .gt_rxcdrreset(4'b0),
        .gt_rxdfelpmreset(4'b0),
        .gt_txresetdone(gt_txresetdone),
        .gt_rxresetdone(gt_rxresetdone),
        .gt_rxpmaresetdone(gt_rxpmaresetdone),
        .gt_txpmaresetdone(gt_txpmaresetdone),
        .gt_cplllock(gt_cplllock),
        .gt_txprogdivresetdone(gt_txprogdivresetdone),
        .gt_txsyncdone(gt_txsyncdone),
        .gt_rxsyncdone(gt_rxsyncdone),
        .gt_rxcdrlock(gt_rxcdrlock),
        .gt_qpll0lock(gt_qpll0lock),
        .gt_qpll1lock(gt_qpll1lock),
        .phy_rst_idle(phy_rst_idle),
        .phy_rrst_n(phy_rrst_n),
        .phy_prst_n(phy_prst_n),
        .cfg_ltssm_state_o(training_state),.cfg_current_speed_o(training_speed),.cfg_negotiated_width_o(training_width),
        .cfg_err_cor_o(training_err_cor),.cfg_err_nonfatal_o(training_err_nonfatal),.cfg_err_fatal_o(training_err_fatal),
        .cfg_local_error_o(training_local_error),.cfg_local_error_valid_o(training_local_valid),
        .cfg_mgmt_addr(19'd0),.cfg_mgmt_write(1'b0),.cfg_mgmt_write_data(32'd0),
        .cfg_mgmt_byte_enable(4'd0),.cfg_mgmt_read(1'b0),.cfg_mgmt_read_data(),.cfg_mgmt_read_write_done(),
        .s_axis_c2h_tdata_0(c2h_data),.s_axis_c2h_tkeep_0(c2h_keep),
        .s_axis_c2h_tlast_0(c2h_last),.s_axis_c2h_tvalid_0(c2h_valid),.s_axis_c2h_tready_0(c2h_ready),
        .m_axis_h2c_tdata_0(),.m_axis_h2c_tkeep_0(h2c_keep),
        .m_axis_h2c_tlast_0(h2c_last),.m_axis_h2c_tvalid_0(h2c_valid),.m_axis_h2c_tready_0(h2c_ready)
    );
    wire [5:0] training_state;
    wire [2:0] training_speed;
    wire [3:0] training_width;
    wire training_err_cor,training_err_nonfatal,training_err_fatal,training_local_valid;
    wire [4:0] training_local_error;
    wire [127:0] training_snapshot;
    wire training_snapshot_valid;
    pcie_training_monitor training_monitor (
        .axi_clk(axi_clk),.monitor_clk(monitor_clk),.ltssm(training_state),
        .speed(training_speed),.width(training_width),
        .err_cor(training_err_cor),.err_nonfatal(training_err_nonfatal),.err_fatal(training_err_fatal),
        .local_error_valid(training_local_valid),.local_error(training_local_error),
        .link_up(link_up),.axi_reset_n(axi_rst_n),
        .snapshot(training_snapshot),.snapshot_valid(training_snapshot_valid)
    );
    wire feedback_raw,feedback,qualifier_locked,qualifier_stopped;
    MMCME4_ADV #(.CLKIN1_PERIOD(10.0),.CLKIN2_PERIOD(10.0),.CLKFBOUT_MULT_F(10.0),
        .DIVCLK_DIVIDE(1),.CLKOUT0_DIVIDE_F(10.0),.CLKOUT1_DIVIDE(10),.CLKOUT2_DIVIDE(10),
        .CLKOUT3_DIVIDE(10),.CLKOUT4_DIVIDE(10),.CLKOUT5_DIVIDE(10),.CLKOUT6_DIVIDE(10)) qualifier (
        .CLKIN1(sys_input),.CLKIN2(1'b0),.CLKINSEL(1'b1),.CLKFBOUT(feedback_raw),
        .CLKFBIN(feedback),.LOCKED(qualifier_locked),.CLKINSTOPPED(qualifier_stopped),
        .RST(1'b0),.PWRDWN(1'b0),.CDDCREQ(1'b0),.DADDR(7'b0),.DI(16'b0),
        .DCLK(1'b0),.DEN(1'b0),.DWE(1'b0),.PSCLK(1'b0),.PSEN(1'b0),.PSINCDEC(1'b0));
    BUFGCE #(.SIM_DEVICE("ULTRASCALE_PLUS")) qualifier_feedback (.I(feedback_raw),.CE(1'b1),.O(feedback));
    wire [63:0] raw_current,raw_ever_high,raw_ever_low;
    wire [127:0] clocks,metadata;
    wire [255:0] read_data;
    wire [31:0] controls;
    wire [8:0] read_address;
    wire capture_arm;
    // Bits0..56,59 and valid63 receive observer-only connections after synth.
    // QPLL control bits57/58 stay reserved; their actual values are unknown.
    pcie_boot_diagnostics diagnostics (
        .monitor_clk(monitor_clk),.ref_div_clk(ref_div_clk),.axi_clk(axi_clk),
        .raw_async({1'b0,phy_prst_n,phy_rrst_n,phy_rst_idle,60'b0}),
        .perst_seen(perst_seen),.manual_reset(1'b0),.endpoint_reset_n(reset_observed_n),
        .qualifier_locked(qualifier_locked),.qualifier_stopped(qualifier_stopped),
        .link_up(link_up),.axi_reset_n(axi_rst_n),.training_snapshot(training_snapshot),
        .training_valid(training_snapshot_valid),.capture_arm(capture_arm),.read_address(read_address),
        .raw_current(raw_current),.raw_ever_high(raw_ever_high),.raw_ever_low(raw_ever_low),
        .clocks(clocks),.metadata(metadata),.read_data(read_data),.controls(controls));
    lesson05d_vio monitor (
        .clk(monitor_clk),.probe_in0(32'h465805e6),.probe_in1(raw_current),
        .probe_in2(raw_ever_high),.probe_in3(raw_ever_low),.probe_in4({controls,clocks[95:0]}),
        .probe_in5(training_snapshot),.probe_in6(read_data),.probe_in7(metadata),
        .probe_out0(debug_pcie_reset),.probe_out1(read_address),.probe_out2(capture_arm));
    lesson05i_ila clock_trace (.clk(monitor_clk),.probe0(controls),
        .probe1(raw_current),.probe2(clocks[63:0]));
    assign LED1=metadata[26];assign LED2=!controls[15];
endmodule
