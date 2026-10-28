// Lifetime training history, captured coherently across the two clock domains.
// No AXI reset: PCIe training must remain observable while axi_aresetn is low.
// FPGA configuration initializes this diagnostic; endpoint reset does not clear it.
module pcie_training_monitor (
    input wire axi_clk,monitor_clk,
    input wire [5:0] ltssm,
    input wire [2:0] speed,
    input wire [3:0] width,
    input wire err_cor,err_nonfatal,err_fatal,local_error_valid,
    input wire [4:0] local_error,
    input wire link_up,axi_reset_n,
    output wire [127:0] snapshot,
    output reg snapshot_valid=0
);
    reg [63:0] seen=0;
    reg [31:0] transitions=0;
    reg [5:0] previous=0;
    reg have_previous=0;
    reg [7:0] errors=0,sequence_number=0;
    reg [127:0] transfer=0;
    reg send=0;
    reg [1:0] phase=0;
    wire received,available;
    always @(posedge axi_clk) begin
        seen<=seen | (64'b1<<ltssm);
        previous<=ltssm;
        have_previous<=1;
        if(have_previous && previous!=ltssm && transitions!=32'hffffffff)
            transitions<=transitions+1'b1;
        errors<=errors | {(local_error_valid ? local_error : 5'b0),err_fatal,err_nonfatal,err_cor};
        case(phase)
            0: if(!received) begin
                // Include this cycle's state/error in the coherent history.
                transfer<={sequence_number,axi_reset_n,link_up,1'b0,
                    (errors | {(local_error_valid ? local_error : 5'b0),err_fatal,err_nonfatal,err_cor}),
                    width,speed,ltssm,transitions,(seen | (64'b1<<ltssm))};
                sequence_number<=sequence_number+1'b1;
                send<=1;
                phase<=1;
            end
            1: if(received) begin send<=0;phase<=2;end
            2: if(!received) phase<=0;
            default: begin send<=0;phase<=0;end
        endcase
    end
    xpm_cdc_handshake #(
        .WIDTH(128),.DEST_EXT_HSK(0),.DEST_SYNC_FF(4),.SRC_SYNC_FF(4),
        .INIT_SYNC_FF(1),.SIM_ASSERT_CHK(1)
    ) coherent_snapshot (
        .src_clk(axi_clk),.src_in(transfer),.src_send(send),.src_rcv(received),
        .dest_clk(monitor_clk),.dest_out(snapshot),.dest_req(available),.dest_ack(1'b0)
    );
    // Sticky validity. A stopped source leaves an old snapshot, not a new sample;
    // interpret with the independent AXI-clock watchdog and sequence field.
    always @(posedge monitor_clk) if(available) snapshot_valid<=1;
endmodule
