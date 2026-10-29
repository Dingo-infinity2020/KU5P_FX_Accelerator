// Independent asynchronous diagnostic flags, not a coherent encoded bus.
// Sustained levels are synchronized; narrow pulses can be missed.
module pcie_phy_monitor #(parameter integer WIDTH=48) (
    input wire monitor_clk,
    input wire [WIDTH-1:0] flags_async,
    output wire [3*WIDTH-1:0] observation
);
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) reg [WIDTH-1:0] sample1=0,sample2=0;
    reg [WIDTH-1:0] ever_high=0,ever_low=0;
    reg [2:0] warmup=0;
    always @(posedge monitor_clk) begin
        sample1<=flags_async;
        sample2<=sample1;
        warmup<={warmup[1:0],1'b1};
        // Do not record initial synchronizer zeros as actual low observations.
        if(warmup[2]) begin
            ever_high<=ever_high | sample2;
            ever_low<=ever_low | ~sample2;
        end
    end
    assign observation={ever_low,ever_high,sample2};
endmodule
