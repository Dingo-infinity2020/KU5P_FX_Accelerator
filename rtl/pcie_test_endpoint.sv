// AXI-Lite test register bank plus an independently backpressurable C2H source.
// AW and W are buffered independently; read/write responses remain stable.
module pcie_test_endpoint (
    input wire clk,rst_n,link_up,
    input wire [31:0] s_axil_awaddr,input wire s_axil_awvalid,output wire s_axil_awready,
    input wire [31:0] s_axil_wdata,input wire [3:0] s_axil_wstrb,
    input wire s_axil_wvalid,output wire s_axil_wready,
    output reg [1:0] s_axil_bresp,output reg s_axil_bvalid,input wire s_axil_bready,
    input wire [31:0] s_axil_araddr,input wire s_axil_arvalid,output wire s_axil_arready,
    output reg [31:0] s_axil_rdata,output reg [1:0] s_axil_rresp,
    output reg s_axil_rvalid,input wire s_axil_rready,
    output wire [255:0] c2h_data,output wire [31:0] c2h_keep,
    output wire c2h_last,c2h_valid,input wire c2h_ready,
    input wire h2c_valid,h2c_last,input wire [31:0] h2c_keep,output wire h2c_ready,
    output wire busy,done,output wire [31:0] accepted_beats,completed_packets,signature
);
    reg aw_pending,w_pending;
    reg [31:0] write_address,write_data;
    reg [3:0] write_strobe;
    reg [31:0] cfg_packets,cfg_run_id,cfg_seed,h2c_beats,h2c_packets,h2c_bytes,bad_writes;
    reg start,clear_done;
    assign s_axil_awready=rst_n && !aw_pending && !s_axil_bvalid;
    assign s_axil_wready=rst_n && !w_pending && !s_axil_bvalid;
    assign s_axil_arready=rst_n && (!s_axil_rvalid || s_axil_rready);
    assign h2c_ready=rst_n;
    function automatic [31:0] merge_bytes(input reg [31:0] old_value,new_value,input reg [3:0] strobes);
        integer k;
        begin for(k=0;k<4;k=k+1) merge_bytes[k*8+:8]=strobes[k] ? new_value[k*8+:8] : old_value[k*8+:8];end
    endfunction
    function automatic [5:0] byte_count(input reg [31:0] keep);
        integer k;begin byte_count=0;for(k=0;k<32;k=k+1) byte_count=byte_count+keep[k];end
    endfunction
    dma_pattern_source source (
        .clk(clk),.rst_n(rst_n),.start(start),.clear_done(clear_done),
        .cfg_packets(cfg_packets),.cfg_run_id(cfg_run_id),.cfg_seed(cfg_seed),
        .m_axis_tvalid(c2h_valid),.m_axis_tready(c2h_ready),.m_axis_tdata(c2h_data),
        .m_axis_tkeep(c2h_keep),.m_axis_tlast(c2h_last),.busy(busy),.done(done),
        .accepted_beats(accepted_beats),.completed_packets(completed_packets),.signature(signature)
    );
    wire write_fire=aw_pending && w_pending && !s_axil_bvalid;
    wire control_start=write_strobe[0] && write_data[0];
    wire control_clear=write_strobe[0] && write_data[1];
    wire legal_address=(write_address==32'h8 || write_address==32'h10 || write_address==32'h14 || write_address==32'h18);
    wire bad_control=write_address==8 && ((control_start && (busy || start || cfg_packets==0 || cfg_packets>4096)) ||
                                        (control_clear && (busy || start)) || (control_clear && control_start));
    always @(posedge clk) begin
        if(!rst_n) begin
            aw_pending<=0;w_pending<=0;write_address<=0;write_data<=0;write_strobe<=0;
            s_axil_bvalid<=0;s_axil_bresp<=0;s_axil_rvalid<=0;s_axil_rresp<=0;s_axil_rdata<=0;
            cfg_packets<=2;cfg_run_id<=1;cfg_seed<=32'h10203040;start<=0;clear_done<=0;
            h2c_beats<=0;h2c_packets<=0;h2c_bytes<=0;bad_writes<=0;
        end else begin
            start<=0;clear_done<=0;
            if(s_axil_awvalid && s_axil_awready) begin write_address<=s_axil_awaddr;aw_pending<=1;end
            if(s_axil_wvalid && s_axil_wready) begin write_data<=s_axil_wdata;write_strobe<=s_axil_wstrb;w_pending<=1;end
            if(s_axil_bvalid && s_axil_bready) s_axil_bvalid<=0;
            if(write_fire) begin
                aw_pending<=0;w_pending<=0;s_axil_bvalid<=1;s_axil_bresp<=0;
                if(!legal_address || bad_control) begin s_axil_bresp<=2'b10;bad_writes<=bad_writes+1'b1;end
                else case(write_address)
                    32'h8:begin start<=control_start;clear_done<=control_clear;end
                    32'h10:cfg_packets<=merge_bytes(cfg_packets,write_data,write_strobe);
                    32'h14:cfg_run_id<=merge_bytes(cfg_run_id,write_data,write_strobe);
                    32'h18:cfg_seed<=merge_bytes(cfg_seed,write_data,write_strobe);
                    default:begin end
                endcase
            end
            if(s_axil_rvalid && s_axil_rready) s_axil_rvalid<=0;
            if(s_axil_arvalid && s_axil_arready) begin
                s_axil_rvalid<=1;s_axil_rresp<=0;
                case(s_axil_araddr)
                    32'h00:s_axil_rdata<=32'h35445846;
                    32'h04:s_axil_rdata<=1;
                    32'h08:s_axil_rdata<=0;
                    32'h0c:s_axil_rdata<={27'd0,link_up,2'd0,done,busy};
                    32'h10:s_axil_rdata<=cfg_packets;
                    32'h14:s_axil_rdata<=cfg_run_id;
                    32'h18:s_axil_rdata<=cfg_seed;
                    32'h1c:s_axil_rdata<=accepted_beats;
                    32'h20:s_axil_rdata<=completed_packets;
                    32'h24:s_axil_rdata<=signature;
                    32'h28:s_axil_rdata<=h2c_beats;
                    32'h2c:s_axil_rdata<=h2c_packets;
                    32'h30:s_axil_rdata<=32'h465805d1;
                    32'h34:s_axil_rdata<=4096;
                    32'h38:s_axil_rdata<=bad_writes;
                    32'h3c:s_axil_rdata<=h2c_bytes;
                    default:begin s_axil_rdata<=0;s_axil_rresp<=2'b10;end
                endcase
            end
            if(h2c_valid && h2c_ready) begin
                h2c_beats<=h2c_beats+1'b1;h2c_bytes<=h2c_bytes+{26'd0,byte_count(h2c_keep)};
                if(h2c_last) h2c_packets<=h2c_packets+1'b1;
            end
        end
    end
endmodule
