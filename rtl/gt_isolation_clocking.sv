// Qualifies SYS_CLK without driving functional logic from the MMCM output.
module gt_isolation_clocking (
    input wire SYS_CLK,manual_reset,
    output wire monitor_clk,qualifier_locked,qualifier_stopped
);
    wire sys_input,feedback_raw,feedback;
    IBUF sys_input_buffer (.I(SYS_CLK),.O(sys_input));
    BUFG monitor_buffer (.I(sys_input),.O(monitor_clk));
    MMCME4_ADV #(.CLKIN1_PERIOD(10.0),.CLKIN2_PERIOD(10.0),.CLKFBOUT_MULT_F(10.0),
        .DIVCLK_DIVIDE(1),.CLKOUT0_DIVIDE_F(10.0),.CLKOUT1_DIVIDE(10),.CLKOUT2_DIVIDE(10),
        .CLKOUT3_DIVIDE(10),.CLKOUT4_DIVIDE(10),.CLKOUT5_DIVIDE(10),.CLKOUT6_DIVIDE(10)) qualifier (
        .CLKIN1(sys_input),.CLKIN2(1'b0),.CLKINSEL(1'b1),.CLKFBOUT(feedback_raw),
        .CLKFBIN(feedback),.LOCKED(qualifier_locked),.CLKINSTOPPED(qualifier_stopped),
        .RST(manual_reset),.PWRDWN(1'b0),.CDDCREQ(1'b0),.DADDR(7'b0),.DI(16'b0),
        .DCLK(1'b0),.DEN(1'b0),.DWE(1'b0),.PSCLK(1'b0),.PSEN(1'b0),.PSINCDEC(1'b0));
    BUFGCE #(.SIM_DEVICE("ULTRASCALE_PLUS")) qualifier_feedback (.I(feedback_raw),.CE(1'b1),.O(feedback));
endmodule
