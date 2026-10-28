// Serialized 512-bin X stage. Reuse lesson02 at M=1 for each pair, then
// integrate the products in four independent 512x64 memories across frames.
module channelized_x_engine (
    input wire clk, input wire rst_n,
    input wire frame_first, frame_last,
    input wire [31:0] frame_count,
    input wire s_axis_tvalid, output wire s_axis_tready,
    input wire [8:0] s_axis_bin,
    input wire signed [15:0] s_axis_a_i, s_axis_a_q, s_axis_b_i, s_axis_b_q,
    output reg m_axis_tvalid, input wire m_axis_tready,
    output reg [8:0] m_axis_bin,
    output reg [63:0] m_axis_auto_a, m_axis_auto_b,
    output reg signed [63:0] m_axis_cross_real, m_axis_cross_imag,
    output reg [31:0] m_axis_sample_count,
    output reg frame_done
);
    localparam ACCEPT_BIN = 0, WAIT_PRODUCT = 1, HOLD_OUTPUT = 2;
    reg [1:0] state;
    reg [8:0] saved_bin;
    reg saved_first, saved_last;
    reg [31:0] saved_count;
    wire product_in_ready, product_valid;
    wire product_ready = rst_n && (state == WAIT_PRODUCT);
    wire [63:0] product_a, product_b;
    wire signed [63:0] product_real, product_imag;
    assign s_axis_tready = rst_n && (state == ACCEPT_BIN) && product_in_ready;
    wire accept = s_axis_tvalid && s_axis_tready;
    wire write_sum = product_valid && product_ready && !saved_last;

    (* ram_style = "block" *) reg [63:0] bank_a [0:511], bank_b [0:511];
    (* ram_style = "block" *) reg signed [63:0] bank_real [0:511], bank_imag [0:511];
    reg [63:0] previous_a, previous_b;
    reg signed [63:0] previous_real, previous_imag;
    wire [63:0] sum_a = (saved_first ? 64'd0 : previous_a) + product_a;
    wire [63:0] sum_b = (saved_first ? 64'd0 : previous_b) + product_b;
    wire signed [63:0] sum_real = (saved_first ? 64'sd0 : previous_real) + product_real;
    wire signed [63:0] sum_imag = (saved_first ? 64'sd0 : previous_imag) + product_imag;

    // No RAM reset loop. First-frame bypass makes old RAM contents irrelevant
    // after reset and at every new window. Read/write addresses never collide.
    always @(posedge clk) begin
        if (accept) begin
            previous_a <= bank_a[s_axis_bin]; previous_b <= bank_b[s_axis_bin];
            previous_real <= bank_real[s_axis_bin]; previous_imag <= bank_imag[s_axis_bin];
        end
        if (write_sum) begin
            bank_a[saved_bin] <= sum_a; bank_b[saved_bin] <= sum_b;
            bank_real[saved_bin] <= sum_real; bank_imag[saved_bin] <= sum_imag;
        end
    end

    two_channel_correlator product_core (
        .clk(clk), .rst_n(rst_n), .cfg_window_samples(32'd1),
        .s_axis_tvalid(s_axis_tvalid && (state == ACCEPT_BIN)), .s_axis_tready(product_in_ready),
        .s_axis_a_i(s_axis_a_i), .s_axis_a_q(s_axis_a_q),
        .s_axis_b_i(s_axis_b_i), .s_axis_b_q(s_axis_b_q),
        .m_axis_tvalid(product_valid), .m_axis_tready(product_ready),
        .m_axis_auto_a(product_a), .m_axis_auto_b(product_b),
        .m_axis_cross_real(product_real), .m_axis_cross_imag(product_imag), .m_axis_sample_count()
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= ACCEPT_BIN; saved_bin <= 0; saved_first <= 0; saved_last <= 0; saved_count <= 0;
            m_axis_tvalid <= 0; m_axis_bin <= 0; m_axis_sample_count <= 0;
            m_axis_auto_a <= 0; m_axis_auto_b <= 0;
            m_axis_cross_real <= 0; m_axis_cross_imag <= 0; frame_done <= 0;
        end else begin
            frame_done <= 0;
            if (accept) begin
                saved_bin <= s_axis_bin; saved_first <= frame_first;
                saved_last <= frame_last; saved_count <= frame_count;
                state <= WAIT_PRODUCT;
            end
            if (product_valid && product_ready) begin
                if (saved_last) begin
                    m_axis_auto_a <= sum_a; m_axis_auto_b <= sum_b;
                    m_axis_cross_real <= sum_real; m_axis_cross_imag <= sum_imag;
                    m_axis_bin <= saved_bin; m_axis_sample_count <= saved_count;
                    m_axis_tvalid <= 1; state <= HOLD_OUTPUT;
                end else begin
                    state <= ACCEPT_BIN;
                    if (saved_bin == 511) frame_done <= 1;
                end
            end
            if (m_axis_tvalid && m_axis_tready) begin
                m_axis_tvalid <= 0; state <= ACCEPT_BIN;
                if (m_axis_bin == 511) frame_done <= 1;
            end
        end
    end
endmodule
