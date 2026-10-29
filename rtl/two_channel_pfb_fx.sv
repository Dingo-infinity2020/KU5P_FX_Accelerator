// Lesson04: tagged replay hops -> 4-tap PFB/FFT -> planned-window weighted FX.
// A header describes ONE 512-sample hop, even if all its data is invalid.
// Session configuration is captured at the first header and immutable to reset.
module two_channel_pfb_fx (
    input wire clk, input wire rst_n,
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
    output reg [31:0] m_axis_window_id, m_axis_weight_a, m_axis_weight_b, m_axis_weight_ab,
    output wire [31:0] m_axis_window_frames, m_axis_epoch_id, m_axis_config_id,
    output wire [63:0] m_axis_first_frame, m_axis_last_frame,
    output wire [15:0] m_axis_source_a, m_axis_source_b,
    output wire [63:0] m_axis_auto_a, m_axis_auto_b,
    output wire signed [63:0] m_axis_cross_real, m_axis_cross_imag,
    output wire status_protocol_error, status_clip
);
    localparam HEADER=0, LOAD=1, WAIT_X=2;
    reg [1:0] state;
    reg configured, input_error, fft_clip;
    reg [31:0] window_frames, epoch_id, config_id, frames_in_window;
    reg [63:0] expected_frame, first_frame;
    reg [15:0] source_a, source_b;
    reg [8:0] input_index;
    wire fft_error, pfb_clip;
    assign status_protocol_error=input_error || fft_error;
    assign status_clip=pfb_clip || fft_clip;
    wire allowed=rst_n && !status_protocol_error;
    assign s_frame_ready=allowed && state==HEADER && (configured || cfg_window_frames!=0);
    wire header_fire=s_frame_valid && s_frame_ready;
    wire bad_header = s_frame_id != (configured ? expected_frame : cfg_first_frame)
        || s_frame_epoch_id != (configured ? epoch_id : cfg_epoch_id)
        || s_frame_config_id != (configured ? config_id : cfg_config_id)
        || s_frame_source_a != (configured ? source_a : cfg_source_a)
        || s_frame_source_b != (configured ? source_b : cfg_source_b)
        || (configured ? source_a==source_b : cfg_source_a==cfg_source_b);
    wire pfb_in_ready, pfb_valid, pfb_ready, good_a, good_b;
    wire signed [15:0] pfb_a_i, pfb_a_q, pfb_b_i, pfb_b_q;
    wire [8:0] pfb_phase;
    assign s_axis_tready=allowed && state==LOAD && pfb_in_ready;
    pfb_fir_pair_512 pfb (
        .clk(clk), .rst_n(rst_n), .frame_start(header_fire && !bad_header),
        .frame_valid_a(s_frame_good_a), .frame_valid_b(s_frame_good_b),
        .s_axis_tvalid(s_axis_tvalid && state==LOAD && allowed), .s_axis_tready(pfb_in_ready),
        .s_axis_a_i(s_axis_a_i), .s_axis_a_q(s_axis_a_q), .s_axis_b_i(s_axis_b_i), .s_axis_b_q(s_axis_b_q),
        .m_axis_tvalid(pfb_valid), .m_axis_tready(pfb_ready),
        .m_axis_a_i(pfb_a_i), .m_axis_a_q(pfb_a_q), .m_axis_b_i(pfb_b_i), .m_axis_b_q(pfb_b_q),
        .m_axis_phase(pfb_phase), .contribution_a(good_a), .contribution_b(good_b), .status_clip(pfb_clip)
    );
    wire fft_in_ready, fft_valid, fft_ready, fft_last;
    wire [8:0] fft_bin;
    wire signed [25:0] fft_a_i, fft_a_q, fft_b_i, fft_b_q;
    assign pfb_ready=fft_in_ready && allowed;
    fft_pair_512 fft_pair (
        .clk(clk), .rst_n(rst_n),
        .s_axis_tvalid(pfb_valid && allowed), .s_axis_tready(fft_in_ready),
        .s_axis_a_i(pfb_a_i), .s_axis_a_q(pfb_a_q), .s_axis_b_i(pfb_b_i), .s_axis_b_q(pfb_b_q),
        .m_axis_tvalid(fft_valid), .m_axis_tready(fft_ready),
        .m_axis_a_i(fft_a_i), .m_axis_a_q(fft_a_q), .m_axis_b_i(fft_b_i), .m_axis_b_q(fft_b_q),
        .m_axis_bin(fft_bin), .m_axis_tlast(fft_last), .protocol_error(fft_error)
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
    wire [16:0] quant_a_i=requantize(fft_a_i), quant_a_q=requantize(fft_a_q);
    wire [16:0] quant_b_i=requantize(fft_b_i), quant_b_q=requantize(fft_b_q);
    wire x_ready, frame_done;
    wire final_frame=(frames_in_window==window_frames-1'b1);
    assign fft_ready=x_ready && allowed && state!=HEADER;
    channelized_x_engine x_engine (
        .clk(clk), .rst_n(rst_n), .frame_first(frames_in_window==0), .frame_last(final_frame),
        .frame_count(window_frames), .s_axis_tvalid(fft_valid && allowed && state!=HEADER),
        .s_axis_tready(x_ready), .s_axis_bin(fft_bin),
        .s_axis_a_i(quant_a_i[15:0]), .s_axis_a_q(quant_a_q[15:0]),
        .s_axis_b_i(quant_b_i[15:0]), .s_axis_b_q(quant_b_q[15:0]),
        .m_axis_tvalid(m_axis_tvalid), .m_axis_tready(m_axis_tready), .m_axis_bin(m_axis_bin),
        .m_axis_auto_a(m_axis_auto_a), .m_axis_auto_b(m_axis_auto_b),
        .m_axis_cross_real(m_axis_cross_real), .m_axis_cross_imag(m_axis_cross_imag),
        .m_axis_sample_count(), .frame_done(frame_done)
    );
    assign m_axis_tlast=(m_axis_bin==511);
    assign m_axis_window_frames=window_frames;
    assign m_axis_first_frame=first_frame;
    assign m_axis_last_frame=first_frame+{32'd0,window_frames}-64'd1;
    assign m_axis_epoch_id=epoch_id;
    assign m_axis_config_id=config_id;
    assign m_axis_source_a=source_a;
    assign m_axis_source_b=source_b;
    always @(posedge clk) begin
        if(!rst_n) begin
            state<=HEADER; configured<=0; input_error<=0; fft_clip<=0; input_index<=0;
            window_frames<=0; epoch_id<=0; config_id<=0; source_a<=0; source_b<=0;
            frames_in_window<=0; expected_frame<=0; first_frame<=0;
            m_axis_window_id<=0; m_axis_weight_a<=0; m_axis_weight_b<=0; m_axis_weight_ab<=0;
        end else begin
            if(header_fire) begin
                if(bad_header) input_error<=1;
                else begin
                    state<=LOAD; input_index<=0;
                    if(!configured) begin
                        configured<=1; window_frames<=cfg_window_frames;
                        epoch_id<=cfg_epoch_id; config_id<=cfg_config_id;
                        source_a<=cfg_source_a; source_b<=cfg_source_b;
                    end
                    expected_frame<=s_frame_id;
                    if(frames_in_window==0) begin
                        first_frame<=s_frame_id;
                        m_axis_weight_a<=0; m_axis_weight_b<=0; m_axis_weight_ab<=0;
                    end
                end
            end
            if(s_axis_tvalid && s_axis_tready) begin
                if(s_axis_tlast != (input_index==511)) input_error<=1;
                input_index<=input_index+1'b1;
                if(input_index==511) state<=WAIT_X;
            end
            if(fft_valid && fft_ready) begin
                if(fft_bin==0) begin
                    m_axis_weight_a<=m_axis_weight_a+{31'd0,good_a};
                    m_axis_weight_b<=m_axis_weight_b+{31'd0,good_b};
                    m_axis_weight_ab<=m_axis_weight_ab+{31'd0,good_a && good_b};
                end
                if(quant_a_i[16] || quant_a_q[16] || quant_b_i[16] || quant_b_q[16]) fft_clip<=1;
            end
            if(frame_done) begin
                state<=HEADER; expected_frame<=expected_frame+1'b1;
                if(final_frame) begin frames_in_window<=0; m_axis_window_id<=m_axis_window_id+1'b1; end
                else frames_in_window<=frames_in_window+1'b1;
            end
        end
    end
endmodule
