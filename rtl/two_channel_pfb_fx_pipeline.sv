// Overlapped PFB/FFT/X frames with a bounded 16-entry descriptor FIFO.
// The lesson04 numerical and tagged planned-window contract is unchanged.
module two_channel_pfb_fx_pipeline (
    input wire clk, rst_n,
    input wire [31:0] cfg_window_frames, cfg_epoch_id, cfg_config_id,
    input wire [63:0] cfg_first_frame,
    input wire [15:0] cfg_source_a, cfg_source_b,
    input wire s_frame_valid, output wire s_frame_ready,
    input wire [63:0] s_frame_id,
    input wire [31:0] s_frame_epoch_id, s_frame_config_id,
    input wire [15:0] s_frame_source_a, s_frame_source_b,
    input wire s_frame_good_a, s_frame_good_b,
    input wire s_axis_tvalid, output wire s_axis_tready,
    input wire s_axis_tlast,
    input wire signed [15:0] s_axis_a_i, s_axis_a_q, s_axis_b_i, s_axis_b_q,
    output wire m_axis_tvalid, input wire m_axis_tready,
    output wire [8:0] m_axis_bin, output wire m_axis_tlast,
    output wire [31:0] m_axis_window_id,m_axis_weight_a,m_axis_weight_b,m_axis_weight_ab,
    output wire [31:0] m_axis_window_frames,m_axis_epoch_id,m_axis_config_id,
    output wire [63:0] m_axis_first_frame,m_axis_last_frame,
    output wire [15:0] m_axis_source_a,m_axis_source_b,
    output wire [63:0] m_axis_auto_a,m_axis_auto_b,
    output wire signed [63:0] m_axis_cross_real,m_axis_cross_imag,
    output wire status_protocol_error,status_clip
);
    reg loading,configured,input_error,fft_clip;
    reg [31:0] window_frames,epoch_id,config_id,frames_in_window,window_id;
    reg [31:0] weight_a,weight_b,weight_ab;
    reg [63:0] expected_frame,window_start;
    reg [15:0] source_a,source_b;
    reg [8:0] input_index;
    reg [2:0] history_a,history_b;
    wire fft_error,pfb_clip;
    assign status_protocol_error=input_error || fft_error;
    assign status_clip=pfb_clip || fft_clip;
    wire allowed=rst_n && !status_protocol_error;
    wire [31:0] M=configured ? window_frames : cfg_window_frames;
    wire [31:0] E=configured ? epoch_id : cfg_epoch_id;
    wire [31:0] C=configured ? config_id : cfg_config_id;
    wire [15:0] A=configured ? source_a : cfg_source_a;
    wire [15:0] B=configured ? source_b : cfg_source_b;
    wire bad_header=s_frame_id!=(configured ? expected_frame : cfg_first_frame)
        || s_frame_epoch_id!=E || s_frame_config_id!=C
        || s_frame_source_a!=A || s_frame_source_b!=B || A==B;
    wire effective_a=s_frame_good_a && (&history_a);
    wire effective_b=s_frame_good_b && (&history_b);
    wire first=(frames_in_window==0),last=(frames_in_window==M-1'b1);
    wire [31:0] next_wa=(first ? 32'd0 : weight_a)+{31'd0,effective_a};
    wire [31:0] next_wb=(first ? 32'd0 : weight_b)+{31'd0,effective_b};
    wire [31:0] next_wab=(first ? 32'd0 : weight_ab)+{31'd0,effective_a && effective_b};
    wire [63:0] wf=first ? s_frame_id : window_start;
    wire [383:0] header_info={window_id,next_wa,next_wb,next_wab,M,wf,wf+{32'd0,M}-64'd1,E,C,A,B};
    (* ram_style="distributed" *) reg [385:0] tags [0:15];
    reg [3:0] tag_write,tag_read;
    reg [4:0] tag_count;
    wire [385:0] head=tags[tag_read];
    assign s_frame_ready=allowed && !loading && tag_count<16 && M!=0;
    wire header_fire=s_frame_valid && s_frame_ready;
    wire push=header_fire && !bad_header;

    wire pfb_in_ready,pfb_valid,pfb_ready,good_a,good_b;
    wire signed [15:0] pfb_a_i,pfb_a_q,pfb_b_i,pfb_b_q;
    wire [8:0] pfb_phase;
    assign s_axis_tready=allowed && loading && pfb_in_ready;
    pfb_fir_pair_512_pipeline pfb (
        .clk(clk),.rst_n(rst_n),.frame_start(push),
        .frame_valid_a(s_frame_good_a),.frame_valid_b(s_frame_good_b),
        .s_axis_tvalid(s_axis_tvalid && loading && allowed),.s_axis_tready(pfb_in_ready),
        .s_axis_a_i(s_axis_a_i),.s_axis_a_q(s_axis_a_q),.s_axis_b_i(s_axis_b_i),.s_axis_b_q(s_axis_b_q),
        .m_axis_tvalid(pfb_valid),.m_axis_tready(pfb_ready),
        .m_axis_a_i(pfb_a_i),.m_axis_a_q(pfb_a_q),.m_axis_b_i(pfb_b_i),.m_axis_b_q(pfb_b_q),
        .m_axis_phase(pfb_phase),.contribution_a(good_a),.contribution_b(good_b),.status_clip(pfb_clip)
    );
    wire fft_in_ready,fft_valid,fft_ready,fft_last;
    wire [8:0] fft_bin;
    wire signed [25:0] fft_a_i,fft_a_q,fft_b_i,fft_b_q;
    assign pfb_ready=fft_in_ready && allowed;
    fft_pair_512_pipeline fft_pair (
        .clk(clk),.rst_n(rst_n),.s_axis_tvalid(pfb_valid && allowed),.s_axis_tready(fft_in_ready),
        .s_axis_a_i(pfb_a_i),.s_axis_a_q(pfb_a_q),.s_axis_b_i(pfb_b_i),.s_axis_b_q(pfb_b_q),
        .m_axis_tvalid(fft_valid),.m_axis_tready(fft_ready),
        .m_axis_a_i(fft_a_i),.m_axis_a_q(fft_a_q),.m_axis_b_i(fft_b_i),.m_axis_b_q(fft_b_q),
        .m_axis_bin(fft_bin),.m_axis_tlast(fft_last),.protocol_error(fft_error)
    );
    function automatic [16:0] requantize(input reg signed [25:0] value);
        reg signed [26:0] rounded;
        begin
            rounded=$signed({value[25],value}) >>> 10;
            if(value[9:0]>512 || (value[9:0]==512 && rounded[0])) rounded=rounded+1'b1;
            if(rounded>32767) requantize={1'b1,16'h7fff};
            else if(rounded < -32768) requantize={1'b1,16'h8000};
            else requantize={1'b0,rounded[15:0]};
        end
    endfunction
    wire [16:0] quant_a_i=requantize(fft_a_i),quant_a_q=requantize(fft_a_q);
    wire [16:0] quant_b_i=requantize(fft_b_i),quant_b_q=requantize(fft_b_q);
    wire x_ready,x_valid;
    wire [393:0] output_meta;
    assign fft_ready=allowed && tag_count!=0 && x_ready;
    wire pop=fft_valid && fft_ready && fft_last;
    channelized_x_pipeline x_engine (
        .clk(clk),.rst_n(rst_n),.frame_first(head[385]),.frame_last(head[384]),
        .s_axis_meta({fft_bin,fft_last,head[383:0]}),
        .s_axis_tvalid(fft_valid && allowed && tag_count!=0),.s_axis_tready(x_ready),.s_axis_bin(fft_bin),
        .s_axis_a_i(quant_a_i[15:0]),.s_axis_a_q(quant_a_q[15:0]),
        .s_axis_b_i(quant_b_i[15:0]),.s_axis_b_q(quant_b_q[15:0]),
        .m_axis_tvalid(x_valid),.m_axis_tready(m_axis_tready && allowed),.m_axis_meta(output_meta),
        .m_axis_auto_a(m_axis_auto_a),.m_axis_auto_b(m_axis_auto_b),
        .m_axis_cross_real(m_axis_cross_real),.m_axis_cross_imag(m_axis_cross_imag)
    );
    assign m_axis_tvalid=x_valid && allowed;
    assign {m_axis_bin,m_axis_tlast,m_axis_window_id,m_axis_weight_a,m_axis_weight_b,m_axis_weight_ab,
            m_axis_window_frames,m_axis_first_frame,m_axis_last_frame,m_axis_epoch_id,m_axis_config_id,
            m_axis_source_a,m_axis_source_b}=output_meta;
    always @(posedge clk) begin
        if(!rst_n) begin
            loading<=0;configured<=0;input_error<=0;fft_clip<=0;input_index<=0;
            window_frames<=0;epoch_id<=0;config_id<=0;source_a<=0;source_b<=0;
            expected_frame<=0;window_start<=0;frames_in_window<=0;window_id<=0;
            weight_a<=0;weight_b<=0;weight_ab<=0;history_a<=0;history_b<=0;
            tag_write<=0;tag_read<=0;tag_count<=0;
        end else begin
            case({push,pop})
                2'b10:tag_count<=tag_count+1'b1;
                2'b01:tag_count<=tag_count-1'b1;
                default:tag_count<=tag_count;
            endcase
            if(pop) tag_read<=tag_read+1'b1;
            if(header_fire) begin
                if(bad_header) input_error<=1;
                else begin
                    loading<=1;input_index<=0;
                    tags[tag_write]<={first,last,header_info};tag_write<=tag_write+1'b1;
                    if(!configured) begin
                        configured<=1;window_frames<=M;epoch_id<=E;config_id<=C;source_a<=A;source_b<=B;
                    end
                    expected_frame<=s_frame_id+1'b1;
                    if(first) window_start<=s_frame_id;
                    weight_a<=next_wa;weight_b<=next_wb;weight_ab<=next_wab;
                    history_a<={history_a[1:0],s_frame_good_a};history_b<={history_b[1:0],s_frame_good_b};
                    if(last) begin frames_in_window<=0;window_id<=window_id+1'b1;end
                    else frames_in_window<=frames_in_window+1'b1;
                end
            end
            if(s_axis_tvalid && s_axis_tready) begin
                if(s_axis_tlast!=(input_index==511)) input_error<=1;
                input_index<=input_index+1'b1;
                if(input_index==511) loading<=0;
            end
            if(fft_valid && fft_ready && (quant_a_i[16] || quant_a_q[16] || quant_b_i[16] || quant_b_q[16])) fft_clip<=1;
        end
    end
endmodule
