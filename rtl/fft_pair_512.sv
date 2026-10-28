// Two locally generated AMD FFT v9.1 instances. Fixed 512, forward, natural
// order, unscaled 16 -> 26 bits, 24-bit twiddles, convergent butterfly rounding.
module fft_pair_512 (
    input wire clk, input wire rst_n,
    input wire s_axis_tvalid, output wire s_axis_tready,
    input wire signed [15:0] s_axis_a_i, s_axis_a_q, s_axis_b_i, s_axis_b_q,
    output wire m_axis_tvalid, input wire m_axis_tready,
    output wire signed [25:0] m_axis_a_i, m_axis_a_q, m_axis_b_i, m_axis_b_q,
    output wire [8:0] m_axis_bin,
    output wire m_axis_tlast,
    output reg protocol_error
);
    reg [2:0] reset_count;
    wire core_rst_n = rst_n && (reset_count == 4);
    always @(posedge clk) begin
        if (!rst_n) reset_count <= 0;
        else if (reset_count != 4) reset_count <= reset_count + 1'b1;
    end
    reg a_configured, b_configured;
    reg [2:0] config_guard;
    wire a_cfg_ready, b_cfg_ready;
    wire configured = core_rst_n && (config_guard == 4);

    // Independent pending flags give each FFT a valid that does not depend on
    // ready. A pair is not overwritten until BOTH input transfers have occurred.
    reg pending_a, pending_b, held_last;
    reg [31:0] held_a, held_b;
    reg [8:0] load_index, expected_bin;
    wire a_in_ready, b_in_ready;
    wire [63:0] a_out_data, b_out_data;
    wire [15:0] a_out_user, b_out_user;
    wire a_out_valid, b_out_valid, a_out_last, b_out_last;
    wire a_out_ready, b_out_ready;
    wire a_last_missing, a_last_unexpected, b_last_missing, b_last_unexpected;
    wire mismatch = a_out_valid && b_out_valid
                   && ((a_out_user != b_out_user) || (a_out_user != {7'd0, expected_bin})
                       || (a_out_last != (expected_bin == 511))
                       || (b_out_last != (expected_bin == 511)));

    assign s_axis_tready = configured && !protocol_error && !pending_a && !pending_b;
    assign m_axis_tvalid = a_out_valid && b_out_valid && !protocol_error && !mismatch && core_rst_n;
    assign a_out_ready = m_axis_tready && b_out_valid && !protocol_error && !mismatch && core_rst_n;
    assign b_out_ready = m_axis_tready && a_out_valid && !protocol_error && !mismatch && core_rst_n;
    assign m_axis_a_i = a_out_data[25:0];
    assign m_axis_a_q = a_out_data[57:32];
    assign m_axis_b_i = b_out_data[25:0];
    assign m_axis_b_q = b_out_data[57:32];
    assign m_axis_bin = a_out_user[8:0];
    assign m_axis_tlast = a_out_last;

    always @(posedge clk) begin
        if (!core_rst_n) begin
            a_configured <= 0; b_configured <= 0; config_guard <= 0;
            pending_a <= 0; pending_b <= 0;
            held_a <= 0; held_b <= 0; held_last <= 0;
            load_index <= 0; expected_bin <= 0; protocol_error <= 0;
        end else begin
            if (!a_configured && a_cfg_ready) a_configured <= 1;
            if (!b_configured && b_cfg_ready) b_configured <= 1;
            if (a_configured && b_configured && config_guard != 4)
                config_guard <= config_guard + 1'b1;
            if (pending_a && a_in_ready) pending_a <= 0;
            if (pending_b && b_in_ready) pending_b <= 0;
            if (s_axis_tvalid && s_axis_tready) begin
                held_a <= {s_axis_a_q, s_axis_a_i};
                held_b <= {s_axis_b_q, s_axis_b_i};
                held_last <= (load_index == 511);
                load_index <= load_index + 1'b1;
                pending_a <= 1; pending_b <= 1;
            end
            if (m_axis_tvalid && m_axis_tready) expected_bin <= expected_bin + 1'b1;
            if (mismatch || a_last_missing || a_last_unexpected || b_last_missing || b_last_unexpected)
                protocol_error <= 1;
        end
    end

    lesson03_fft512 fft_a (
        .aclk(clk), .aresetn(core_rst_n),
        .s_axis_config_tdata(8'h01), .s_axis_config_tvalid(core_rst_n && !a_configured),
        .s_axis_config_tready(a_cfg_ready),
        .s_axis_data_tdata(held_a), .s_axis_data_tvalid(pending_a),
        .s_axis_data_tready(a_in_ready), .s_axis_data_tlast(held_last),
        .m_axis_data_tdata(a_out_data), .m_axis_data_tuser(a_out_user),
        .m_axis_data_tvalid(a_out_valid), .m_axis_data_tready(a_out_ready), .m_axis_data_tlast(a_out_last),
        .event_tlast_unexpected(a_last_unexpected), .event_tlast_missing(a_last_missing),
        .event_frame_started(), .event_status_channel_halt(),
        .event_data_in_channel_halt(), .event_data_out_channel_halt()
    );
    lesson03_fft512 fft_b (
        .aclk(clk), .aresetn(core_rst_n),
        .s_axis_config_tdata(8'h01), .s_axis_config_tvalid(core_rst_n && !b_configured),
        .s_axis_config_tready(b_cfg_ready),
        .s_axis_data_tdata(held_b), .s_axis_data_tvalid(pending_b),
        .s_axis_data_tready(b_in_ready), .s_axis_data_tlast(held_last),
        .m_axis_data_tdata(b_out_data), .m_axis_data_tuser(b_out_user),
        .m_axis_data_tvalid(b_out_valid), .m_axis_data_tready(b_out_ready), .m_axis_data_tlast(b_out_last),
        .event_tlast_unexpected(b_last_unexpected), .event_tlast_missing(b_last_missing),
        .event_frame_started(), .event_status_channel_halt(),
        .event_data_in_channel_halt(), .event_data_out_channel_halt()
    );
endmodule
