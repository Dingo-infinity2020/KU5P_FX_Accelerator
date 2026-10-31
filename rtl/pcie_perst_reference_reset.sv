// e6: standard external PERST-only entrance. VIO cannot reset the PHY.
// One independent observation chain; it never drives the vendor reset input.
module pcie_perst_reference_reset (
    input wire monitor_clk,pcie_reset_n,
    output wire core_reset_n,perst_seen,reset_observed_n
);
    assign core_reset_n=pcie_reset_n;
    (* ASYNC_REG="TRUE",SHREG_EXTRACT="NO" *) reg [2:0] observer_pipe=0;
    always @(posedge monitor_clk or negedge pcie_reset_n) begin
        if(!pcie_reset_n) observer_pipe<=0;
        else observer_pipe<={observer_pipe[1:0],1'b1};
    end
    assign reset_observed_n=observer_pipe[1];
    assign perst_seen=observer_pipe[2];
endmodule
