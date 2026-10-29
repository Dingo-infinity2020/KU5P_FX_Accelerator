// d5: adds independent GT/PHY diagnostic flags to the d4 training profile.
// Monitor clock is independent of PCIe, so VIO remains usable before link-up.
module lesson05d_pcie_phy_top (
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
    wire reference_fabric_clk,ref_recent,axi_recent,sys_clk_ce,sync_sc_ce,sync_sc_clr;
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
    wire [143:0] phy_observation;
    pcie_phy_monitor phy_monitor (
        .monitor_clk(monitor_clk),
        .flags_async({gt_rxcdrlock,gt_rxsyncdone,gt_txsyncdone,gt_txprogdivresetdone,
            1'b0,phy_prst_n,phy_rrst_n,phy_rst_idle,2'b0,gt_qpll0lock,gt_qpll1lock,
            gt_cplllock,3'b0,sys_clk_ce,gt_txpmaresetdone,gt_rxpmaresetdone,gt_rxresetdone,gt_txresetdone}),
        .observation(phy_observation)
    );
    lesson05d_xdma dma (
        .sys_clk(reference_fabric_clk),.sys_clk_ce_out(sys_clk_ce),.sys_clk_gt(sys_clk_gt),.sys_rst_n(pcie_reset_n && !debug_pcie_reset),.user_lnk_up(link_up),
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
    reg [26:0] heartbeat=0;
    always @(posedge monitor_clk) heartbeat<=heartbeat+1'b1;
    pcie_clock_monitor clock_monitor (
        .monitor_clk(monitor_clk),.ref_clk(reference_fabric_clk),.axi_clk(axi_clk),
        .ref_recent(ref_recent),.axi_recent(axi_recent)
    );
    // Every crossing is an independent one-bit diagnostic, not a coherent bus.
    (* ASYNC_REG="TRUE" *) reg [5:0] monitor_sync1=0,monitor_sync2=0;
    always @(posedge monitor_clk) begin
        // The IP exports copies of one !rst_txpisopd flag, not four raw GT flags.
        // Reuse its one synchronized observation in this destination domain.
        monitor_sync1<={phy_observation[16],pcie_reset_n,msi_enabled,axi_rst_n,done,link_up};
        monitor_sync2<=monitor_sync1;
    end
    assign LED1=heartbeat[26];assign LED2=!monitor_sync2[0];
    lesson05d_vio monitor (
        .clk(monitor_clk),.probe_in0({axi_recent,ref_recent,monitor_sync2}),.probe_in1(32'h465805d5),
        .probe_in4(phy_observation),.probe_in2(training_snapshot),.probe_in3(training_snapshot_valid),.probe_out0(debug_pcie_reset)
    );
endmodule
