// SYS_CLK-domain reset request for the independent Wizard helper controller.
module gt_isolation_reset #(parameter integer HOLD_BITS=14) (
    input wire clk, manual_reset, qualifier_locked_async,
    output reg reset_all=1'b1
);
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) reg lock_meta=0,lock_sync=0;
    reg [HOLD_BITS-1:0] settle=0;
    always @(posedge clk) begin
        lock_meta<=qualifier_locked_async;
        lock_sync<=lock_meta;
        if(manual_reset || !lock_sync) begin
            settle<=0;
            reset_all<=1;
        end else if(!(&settle)) begin
            settle<=settle+1'b1;
            reset_all<=1;
        end else reset_all<=0;
    end
endmodule
