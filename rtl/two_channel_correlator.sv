// Lesson 02: one aligned pair of complex voltages -> two autos and one cross.
// Vab = sum(A * conj(B)); input I/Q is signed 16-bit. One input transfer
// contains BOTH voltages for the same frequency/frame. Alignment is external.
// Single clock domain, synchronous active-low reset, no normalization or FFT.
module two_channel_correlator (
    input  wire               clk,
    input  wire               rst_n,
    input  wire [31:0]        cfg_window_samples,

    input  wire               s_axis_tvalid,
    output wire               s_axis_tready,
    input  wire signed [15:0] s_axis_a_i,
    input  wire signed [15:0] s_axis_a_q,
    input  wire signed [15:0] s_axis_b_i,
    input  wire signed [15:0] s_axis_b_q,

    output reg                m_axis_tvalid,
    input  wire               m_axis_tready,
    output reg  [63:0]        m_axis_auto_a,
    output reg  [63:0]        m_axis_auto_b,
    output reg signed [63:0]  m_axis_cross_real,
    output reg signed [63:0]  m_axis_cross_imag,
    output reg  [31:0]        m_axis_sample_count
);
    // A blocked output freezes the entire pipeline. A product already in
    // flight is retained; no unbounded queue or hidden sample discard exists.
    wire advance = !m_axis_tvalid || m_axis_tready;
    reg [31:0] samples_accepted;
    reg [31:0] window_target;
    assign s_axis_tready = rst_n && advance
                         && ((samples_accepted != 0) || (cfg_window_samples != 0));

    // Stage 1: registered full-width products. All metadata travels with them.
    reg product_valid, product_last;
    reg [31:0] product_count;
    reg signed [31:0] aa_ii, aa_qq, bb_ii, bb_qq;
    reg signed [31:0] ab_ii, ab_qq, ab_qi, ab_iq;

    wire [32:0] power_a = {1'b0, aa_ii} + {1'b0, aa_qq};
    wire [32:0] power_b = {1'b0, bb_ii} + {1'b0, bb_qq};
    // Sign-extend BEFORE add/subtract: the positive real part may equal 2^31.
    wire signed [32:0] cross_real = $signed({ab_ii[31], ab_ii})
                                 + $signed({ab_qq[31], ab_qq});
    wire signed [32:0] cross_imag = $signed({ab_qi[31], ab_qi})
                                 - $signed({ab_iq[31], ab_iq});
    wire signed [63:0] real_extended = {{31{cross_real[32]}}, cross_real};
    wire signed [63:0] imag_extended = {{31{cross_imag[32]}}, cross_imag};

    // Stage 2: accumulate the preceding cycle's products, including the last
    // sample in each emitted sum. M is accepted pairs, not elapsed time.
    reg [63:0] accumulator_auto_a, accumulator_auto_b;
    reg signed [63:0] accumulator_real, accumulator_imag;

    always @(posedge clk) begin
        if (!rst_n) begin
            samples_accepted    <= 32'd0;
            window_target       <= 32'd0;
            product_valid       <= 1'b0;
            product_last        <= 1'b0;
            product_count       <= 32'd0;
            aa_ii <= 32'sd0; aa_qq <= 32'sd0;
            bb_ii <= 32'sd0; bb_qq <= 32'sd0;
            ab_ii <= 32'sd0; ab_qq <= 32'sd0;
            ab_qi <= 32'sd0; ab_iq <= 32'sd0;
            accumulator_auto_a  <= 64'd0;
            accumulator_auto_b  <= 64'd0;
            accumulator_real    <= 64'sd0;
            accumulator_imag    <= 64'sd0;
            m_axis_tvalid       <= 1'b0;
            m_axis_auto_a       <= 64'd0;
            m_axis_auto_b       <= 64'd0;
            m_axis_cross_real   <= 64'sd0;
            m_axis_cross_imag   <= 64'sd0;
            m_axis_sample_count <= 32'd0;
        end else if (advance) begin
            m_axis_tvalid <= 1'b0;
            product_valid <= s_axis_tvalid && s_axis_tready;

            if (s_axis_tvalid && s_axis_tready) begin
                aa_ii <= s_axis_a_i * s_axis_a_i;
                aa_qq <= s_axis_a_q * s_axis_a_q;
                bb_ii <= s_axis_b_i * s_axis_b_i;
                bb_qq <= s_axis_b_q * s_axis_b_q;
                ab_ii <= s_axis_a_i * s_axis_b_i;
                ab_qq <= s_axis_a_q * s_axis_b_q;
                ab_qi <= s_axis_a_q * s_axis_b_i;
                ab_iq <= s_axis_a_i * s_axis_b_q;
                if (samples_accepted == 0) begin
                    window_target <= cfg_window_samples;
                    product_count <= 32'd1;
                    product_last  <= (cfg_window_samples == 1);
                    samples_accepted <= (cfg_window_samples == 1) ? 32'd0 : 32'd1;
                end else begin
                    product_count <= samples_accepted + 1'b1;
                    product_last  <= (samples_accepted == window_target - 1'b1);
                    samples_accepted <= (samples_accepted == window_target - 1'b1)
                                        ? 32'd0 : samples_accepted + 1'b1;
                end
            end

            if (product_valid) begin
                if (product_last) begin
                    m_axis_auto_a       <= accumulator_auto_a + {31'd0, power_a};
                    m_axis_auto_b       <= accumulator_auto_b + {31'd0, power_b};
                    m_axis_cross_real   <= accumulator_real + real_extended;
                    m_axis_cross_imag   <= accumulator_imag + imag_extended;
                    m_axis_sample_count <= product_count;
                    m_axis_tvalid       <= 1'b1;
                    accumulator_auto_a  <= 64'd0;
                    accumulator_auto_b  <= 64'd0;
                    accumulator_real    <= 64'sd0;
                    accumulator_imag    <= 64'sd0;
                end else begin
                    accumulator_auto_a <= accumulator_auto_a + {31'd0, power_a};
                    accumulator_auto_b <= accumulator_auto_b + {31'd0, power_b};
                    accumulator_real   <= accumulator_real + real_extended;
                    accumulator_imag   <= accumulator_imag + imag_extended;
                end
            end
        end
    end
endmodule
