// Lesson03: replay-oriented, two-antenna 512-point FFT-FX, rectangular window.
// No PFB, wall-clock integration, packet parser, cross-board alignment or CDC.
module two_channel_fft_fx (
    input wire clk, input wire rst_n,
    input wire [31:0] cfg_window_frames,
    input wire s_axis_tvalid, output wire s_axis_tready,
    input wire signed [15:0] s_axis_a_i, s_axis_a_q, s_axis_b_i, s_axis_b_q,
    output wire m_axis_tvalid, input wire m_axis_tready,
    output wire [8:0] m_axis_bin,
    output wire m_axis_tlast,
    output wire [31:0] m_axis_window_id, m_axis_sample_count,
    output wire [63:0] m_axis_auto_a, m_axis_auto_b,
    output wire signed [63:0] m_axis_cross_real, m_axis_cross_imag,
    output wire status_protocol_error,
    output reg status_clip
);
    reg frame_busy, frame_loaded;
    reg [8:0] input_index;
    reg [31:0] window_target, frames_in_window, window_id;
    wire frame_done;
    wire fft_in_ready, fft_valid, fft_ready, fft_last;
    wire [8:0] fft_bin;
    wire signed [25:0] fft_a_i, fft_a_q, fft_b_i, fft_b_q;
    wire allow_input = rst_n && !frame_loaded && !status_protocol_error
                       && (frame_busy || (frames_in_window != 0) || (cfg_window_frames != 0));
    assign s_axis_tready = allow_input && fft_in_ready;
    assign m_axis_window_id = window_id;
    assign m_axis_tlast = (m_axis_bin == 511);
    wire final_frame = (frames_in_window == window_target - 1'b1);

    fft_pair_512 fft_pair (
        .clk(clk), .rst_n(rst_n),
        .s_axis_tvalid(s_axis_tvalid && allow_input), .s_axis_tready(fft_in_ready),
        .s_axis_a_i(s_axis_a_i), .s_axis_a_q(s_axis_a_q), .s_axis_b_i(s_axis_b_i), .s_axis_b_q(s_axis_b_q),
        .m_axis_tvalid(fft_valid), .m_axis_tready(fft_ready),
        .m_axis_a_i(fft_a_i), .m_axis_a_q(fft_a_q), .m_axis_b_i(fft_b_i), .m_axis_b_q(fft_b_q),
        .m_axis_bin(fft_bin), .m_axis_tlast(fft_last), .protocol_error(status_protocol_error)
    );

    // Divide each raw FFT voltage by 1024, round ties to even, saturate.
    // Return {clip, signed16}. Negative remainders use floor division implicitly.
    function automatic [16:0] requantize(input reg signed [25:0] value);
        reg signed [26:0] rounded;
        begin
            rounded = $signed({value[25], value}) >>> 10;
            if (value[9:0] > 512 || (value[9:0] == 512 && rounded[0]))
                rounded = rounded + 1'b1;
            if (rounded > 32767) requantize = {1'b1, 16'h7fff};
            else if (rounded < -32768) requantize = {1'b1, 16'h8000};
            else requantize = {1'b0, rounded[15:0]};
        end
    endfunction
    wire [16:0] quant_a_i = requantize(fft_a_i), quant_a_q = requantize(fft_a_q);
    wire [16:0] quant_b_i = requantize(fft_b_i), quant_b_q = requantize(fft_b_q);
    wire x_input_ready;
    assign fft_ready = frame_busy && x_input_ready;
    channelized_x_engine x_engine (
        .clk(clk), .rst_n(rst_n), .frame_first(frames_in_window == 0),
        .frame_last(final_frame), .frame_count(window_target),
        .s_axis_tvalid(fft_valid && frame_busy), .s_axis_tready(x_input_ready), .s_axis_bin(fft_bin),
        .s_axis_a_i(quant_a_i[15:0]), .s_axis_a_q(quant_a_q[15:0]),
        .s_axis_b_i(quant_b_i[15:0]), .s_axis_b_q(quant_b_q[15:0]),
        .m_axis_tvalid(m_axis_tvalid), .m_axis_tready(m_axis_tready), .m_axis_bin(m_axis_bin),
        .m_axis_auto_a(m_axis_auto_a), .m_axis_auto_b(m_axis_auto_b),
        .m_axis_cross_real(m_axis_cross_real), .m_axis_cross_imag(m_axis_cross_imag),
        .m_axis_sample_count(m_axis_sample_count), .frame_done(frame_done)
    );
    always @(posedge clk) begin
        if (!rst_n) begin
            frame_busy <= 0; frame_loaded <= 0; input_index <= 0;
            window_target <= 0; frames_in_window <= 0; window_id <= 0; status_clip <= 0;
        end else begin
            if (s_axis_tvalid && s_axis_tready) begin
                if (!frame_busy) begin
                    frame_busy <= 1;
                    if (frames_in_window == 0) window_target <= cfg_window_frames;
                end
                input_index <= input_index + 1'b1;
                if (input_index == 511) frame_loaded <= 1;
            end
            if (fft_valid && fft_ready && (quant_a_i[16] || quant_a_q[16] || quant_b_i[16] || quant_b_q[16]))
                status_clip <= 1;
            if (frame_done) begin
                frame_busy <= 0; frame_loaded <= 0;
                if (final_frame) begin
                    frames_in_window <= 0; window_id <= window_id + 1'b1;
                end else frames_in_window <= frames_in_window + 1'b1;
            end
        end
    end
endmodule
