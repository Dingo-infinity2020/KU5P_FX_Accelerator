// Deterministic 4 KiB packets, 256-bit stream, handshake-safe under stalls.
// Configuration is snapshotted on start. No host address or DMA descriptor is
// generated here; XDMA only transfers after a host driver supplies descriptors.
module dma_pattern_source (
    input wire clk,rst_n,start,clear_done,
    input wire [31:0] cfg_packets,cfg_run_id,cfg_seed,
    output wire m_axis_tvalid,input wire m_axis_tready,
    output reg [255:0] m_axis_tdata,
    output wire [31:0] m_axis_tkeep,output wire m_axis_tlast,
    output reg busy,done,
    output reg [31:0] accepted_beats,completed_packets,signature
);
    reg [31:0] packets,run_id,seed,packet_index;
    reg [6:0] beat_index;
    assign m_axis_tvalid=rst_n && busy;
    assign m_axis_tkeep=32'hffffffff;
    assign m_axis_tlast=(beat_index==127);
    function automatic [255:0] beat(input reg [31:0] p,input reg [6:0] b,
        input reg [31:0] count,rid,salt);
        integer k;reg [255:0] value;
        begin
            if(b==0) value={32'd0,salt,32'd4096,count,p,rid,32'd1,32'h35445846};
            else for(k=0;k<8;k=k+1) value[k*32+:32]=salt+(p<<10)+({25'd0,b}<<3)+k;
            beat=value;
        end
    endfunction
    function automatic [31:0] fold(input reg [255:0] value);
        integer k;reg [31:0] result,word_value;
        begin
            result=0;
            for(k=0;k<8;k=k+1) begin
                word_value=value[k*32+:32];
                result=result ^ ((word_value<<(k+1)) | (word_value>>(31-k)));
            end
            fold=result;
        end
    endfunction
    always @(posedge clk) begin
        if(!rst_n) begin
            packets<=0;run_id<=0;seed<=0;packet_index<=0;beat_index<=0;
            busy<=0;done<=0;accepted_beats<=0;completed_packets<=0;signature<=0;m_axis_tdata<=0;
        end else begin
            if(clear_done && !busy) done<=0;
            if(start && !busy && cfg_packets!=0 && cfg_packets<=4096) begin
                packets<=cfg_packets;run_id<=cfg_run_id;seed<=cfg_seed;packet_index<=0;beat_index<=0;
                busy<=1;done<=0;accepted_beats<=0;completed_packets<=0;signature<=0;
                m_axis_tdata<=beat(0,0,cfg_packets,cfg_run_id,cfg_seed);
            end else if(m_axis_tvalid && m_axis_tready) begin
                accepted_beats<=accepted_beats+1'b1;
                signature<={signature[30:0],signature[31]} ^ fold(m_axis_tdata);
                if(beat_index==127) begin
                    completed_packets<=completed_packets+1'b1;
                    if(packet_index==packets-1'b1) begin busy<=0;done<=1;end
                    else begin
                        packet_index<=packet_index+1'b1;beat_index<=0;
                        m_axis_tdata<=beat(packet_index+1'b1,0,packets,run_id,seed);
                    end
                end else begin
                    beat_index<=beat_index+1'b1;
                    m_axis_tdata<=beat(packet_index,beat_index+1'b1,packets,run_id,seed);
                end
            end
        end
    end
endmodule
