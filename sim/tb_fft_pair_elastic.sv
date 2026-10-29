`timescale 1ns/1ps
// Handshake-only FFT stand-in. The full pipeline suite separately uses the
// actual AMD FFT. Different A/B payloads create independent input stalls here.
module lesson03_fft512 (
    input wire aclk,aresetn,
    input wire [7:0] s_axis_config_tdata,input wire s_axis_config_tvalid,
    output wire s_axis_config_tready,
    input wire [31:0] s_axis_data_tdata,input wire s_axis_data_tvalid,
    output wire s_axis_data_tready,input wire s_axis_data_tlast,
    output wire [63:0] m_axis_data_tdata,output wire [15:0] m_axis_data_tuser,
    output wire m_axis_data_tvalid,input wire m_axis_data_tready,output wire m_axis_data_tlast,
    output wire event_tlast_unexpected,event_tlast_missing,event_frame_started,event_status_channel_halt,
    output wire event_data_in_channel_halt,event_data_out_channel_halt
);
    reg [31:0] data [0:7];reg [8:0] bin [0:7];reg last [0:7];
    reg [2:0] rd,wr;reg [3:0] count;reg [8:0] index;reg [15:0] cycles;
    assign s_axis_config_tready=aresetn;
    assign s_axis_data_tready=aresetn && count<8 && ((cycles+s_axis_data_tdata[3:0])%7!=0);
    assign m_axis_data_tvalid=aresetn && count!=0;
    assign m_axis_data_tdata={{16{data[rd][31]}},data[rd][31:16],{16{data[rd][15]}},data[rd][15:0]};
    assign m_axis_data_tuser={7'd0,bin[rd]};assign m_axis_data_tlast=last[rd];
    assign {event_tlast_unexpected,event_tlast_missing,event_frame_started,event_status_channel_halt,
        event_data_in_channel_halt,event_data_out_channel_halt}=6'd0;
    wire push=s_axis_data_tvalid && s_axis_data_tready;
    wire pop=m_axis_data_tvalid && m_axis_data_tready;
    always @(posedge aclk) begin
        if(!aresetn) begin rd<=0;wr<=0;count<=0;index<=0;cycles<=0;end
        else begin
            cycles<=cycles+1'b1;
            case({push,pop})
                2'b10:count<=count+1'b1;
                2'b01:count<=count-1'b1;
                default:count<=count;
            endcase
            if(push) begin
                data[wr]<=s_axis_data_tdata;bin[wr]<=index;last[wr]<=s_axis_data_tlast;
                index<=index+1'b1;wr<=wr+1'b1;
            end
            if(pop) rd<=rd+1'b1;
        end
    end
endmodule

module tb_fft_pair_elastic;
    reg clk=0;always #4 clk=~clk;
    reg rst_n=0,s_axis_tvalid=0,m_axis_tready=0;
    wire s_axis_tready,m_axis_tvalid,m_axis_tlast,protocol_error;
    reg signed [15:0] s_axis_a_i=0,s_axis_a_q=0,s_axis_b_i=0,s_axis_b_q=0;
    wire signed [25:0] m_axis_a_i,m_axis_a_q,m_axis_b_i,m_axis_b_q;
    wire [8:0] m_axis_bin;
    fft_pair_512_pipeline dut(.*);
    integer sent=0,received=0,independent=0,replacements=0,output_stalls=0;
    integer mode=0,i,marker;reg [31:0] rng=32'hf4b72191;
    reg stalled=0;reg [113:0] held;
    wire [113:0] result={m_axis_a_i,m_axis_a_q,m_axis_b_i,m_axis_b_q,m_axis_bin,m_axis_tlast};
    always @(negedge clk) begin
        rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
        m_axis_tready=mode==1 && (rng[0] || rng[4]);
    end
    always @(posedge clk) begin
        if(!rst_n) stalled=0;
        else begin
            if(protocol_error) $fatal(1,"Pair protocol error");
            if(stalled && (!m_axis_tvalid || result!==held)) $fatal(1,"Changed stalled FFT pair");
            stalled=m_axis_tvalid && !m_axis_tready;held=result;
            if(stalled) output_stalls=output_stalls+1;
            if(dut.pending_a!=dut.pending_b) independent=independent+1;
            if(s_axis_tvalid && s_axis_tready && dut.pending_a && dut.pending_b) replacements=replacements+1;
            if(mode==1 && m_axis_tvalid && m_axis_tready) begin
                if(m_axis_a_i!==received-2000 || m_axis_a_q!==1000-received ||
                   m_axis_b_i!==received*3-7000 || m_axis_b_q!==3000-received*2 ||
                   m_axis_bin!==(received%512) || m_axis_tlast!==(received%512==511))
                    $fatal(1,"Lost/repeated/mixed pair %0d",received);
                received=received+1;
            end
        end
    end
    task reset_pair;
        begin @(negedge clk);rst_n=0;s_axis_tvalid=0;repeat(6) @(negedge clk);rst_n=1;end
    endtask
    task send(input integer n);
        begin
            @(negedge clk);s_axis_tvalid=1;
            s_axis_a_i=n-2000;s_axis_a_q=1000-n;s_axis_b_i=n*3-7000;s_axis_b_q=3000-n*2;
            @(posedge clk);while(!s_axis_tready) @(posedge clk);
        end
    endtask
    initial begin
        reset_pair();
        // Reset with both an output and independent per-lane input pending.
        for(i=0;i<7;i=i+1) send(i);
        @(negedge clk);s_axis_tvalid=0;repeat(30) @(negedge clk);
        reset_pair();mode=1;
        for(i=0;i<4096;i=i+1) send(i);
        @(negedge clk);s_axis_tvalid=0;
        while(received!=4096) @(negedge clk);
        repeat(20) @(negedge clk);
        if(independent==0 || replacements==0 || output_stalls==0) $fatal(1,"Incomplete elastic coverage");
        marker=$fopen("elastic_pass.txt","w");
        $fdisplay(marker,"PASS pairs=%0d independent=%0d replacements=%0d output_stalls=%0d",received,independent,replacements,output_stalls);
        $fclose(marker);$display("PASS elastic pairs=%0d independent=%0d replacements=%0d",received,independent,replacements);$finish;
    end
    initial begin #2000000;$fatal(1,"Elastic timeout");end
endmodule
