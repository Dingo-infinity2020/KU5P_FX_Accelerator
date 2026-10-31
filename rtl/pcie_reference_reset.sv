// Reference-style asynchronous XDMA reset entrance. Unlike e4, release is
// not delayed by SYS_CLK. The vendor IP owns its internal reset sequencing.
// Independent observer pipes are for diagnostics only and do not drive XDMA.
module pcie_reference_reset (
    input wire monitor_clk,pcie_reset_n,manual_reset,
    output wire core_reset_n,perst_seen,reset_observed_n
);
    LUT2 #(.INIT(4'h2)) core_reset_gate (
        .I0(pcie_reset_n),.I1(manual_reset),.O(core_reset_n));
    (* ASYNC_REG="TRUE",SHREG_EXTRACT="NO" *) reg [2:0] perst_pipe=0;
    (* ASYNC_REG="TRUE",SHREG_EXTRACT="NO" *) reg [1:0] reset_observer_pipe=0;
    always @(posedge monitor_clk or negedge pcie_reset_n) begin
        if(!pcie_reset_n) perst_pipe<=0;
        else perst_pipe<={perst_pipe[1:0],1'b1};
    end
    always @(posedge monitor_clk or negedge core_reset_n) begin
        if(!core_reset_n) reset_observer_pipe<=0;
        else reset_observer_pipe<={reset_observer_pipe[0],1'b1};
    end
    assign perst_seen=perst_pipe[2];
    assign reset_observed_n=reset_observer_pipe[1];
endmodule
