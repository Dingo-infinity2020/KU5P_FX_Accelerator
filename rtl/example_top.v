// example_top.v -- minimal zero-IO design used to smoke-test the build flow.
// Uses STARTUPE3's CFGMCLK as a free-running clock so the design has real
// placement without needing board pinout. Not a functional accelerator.
module example_top;
    wire clk;

    STARTUPE3 u_startup (
        .CFGMCLK    (clk),
        .CFGCLK     (),
        .DI         (1'b0),
        .DO         (),
        .DTS        (),
        .FCSBO      (1'b0),
        .FCSBTS     (1'b1),
        .GSR        (1'b0),
        .KEYCLEARB  (1'b1),
        .PACK       (1'b0),
        .PREQ       (1'b0),
        .USRDONEO   (1'b1),
        .USRDONETS  (1'b1)
    );

    (* keep = "true" *) reg [15:0] cnt = 16'h0000;
    always @(posedge clk) cnt <= cnt + 1'b1;
endmodule
