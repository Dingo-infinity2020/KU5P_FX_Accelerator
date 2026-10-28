// Independent diagnostic watchdogs. Each source only exports one divided bit;
// two ASYNC_REG stages sample it in the always-running board clock domain.
// "recent" means an edge was seen within 2**TIMEOUT_BITS monitor cycles.
module pcie_clock_monitor #(
    parameter integer SOURCE_BIT=7,
    parameter integer TIMEOUT_BITS=16
) (
    input wire monitor_clk,ref_clk,axi_clk,
    output wire ref_recent,axi_recent
);
    reg [SOURCE_BIT:0] ref_counter=0,axi_counter=0;
    always @(posedge ref_clk) ref_counter<=ref_counter+1'b1;
    always @(posedge axi_clk) axi_counter<=axi_counter+1'b1;
    (* ASYNC_REG="TRUE" *) reg [1:0] sample1=0,sample2=0;
    reg [1:0] previous=0;
    reg [TIMEOUT_BITS-1:0] ref_age={TIMEOUT_BITS{1'b1}};
    reg [TIMEOUT_BITS-1:0] axi_age={TIMEOUT_BITS{1'b1}};
    always @(posedge monitor_clk) begin
        sample1<={axi_counter[SOURCE_BIT],ref_counter[SOURCE_BIT]};
        sample2<=sample1;
        previous<=sample2;
        if(sample2[0]!=previous[0]) ref_age<=0;
        else if(!(&ref_age)) ref_age<=ref_age+1'b1;
        if(sample2[1]!=previous[1]) axi_age<=0;
        else if(!(&axi_age)) axi_age<=axi_age+1'b1;
    end
    assign ref_recent=!(&ref_age);
    assign axi_recent=!(&axi_age);
endmodule
