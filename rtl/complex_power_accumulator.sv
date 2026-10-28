// Lesson 01: integrate the power of one logical complex stream.
// Transfers happen only on valid && ready. Configuration is captured on
// the first accepted sample of each window. This module does not mix bins
// or antennas, normalize the sum, or supply an absolute time coordinate.
module complex_power_accumulator (
    input  wire               clk,
    input  wire               rst_n,
    input  wire [31:0]        cfg_window_samples,

    input  wire               s_axis_tvalid,
    output wire               s_axis_tready,
    input  wire signed [15:0] s_axis_i,
    input  wire signed [15:0] s_axis_q,

    output reg                m_axis_tvalid,
    input  wire               m_axis_tready,
    output reg  [63:0]        m_axis_power_sum,
    output reg  [31:0]        m_axis_sample_count
);
    reg [63:0] accumulator;
    reg [31:0] samples_accepted;
    reg [31:0] window_target;

    // The signed products are nonnegative, including (-32768)^2.
    wire signed [31:0] i_squared = s_axis_i * s_axis_i;
    wire signed [31:0] q_squared = s_axis_q * s_axis_q;
    wire [32:0] sample_power = {1'b0, i_squared} + {1'b0, q_squared};
    wire [63:0] power_extended = {31'd0, sample_power};

    // A pending result owns the output register until accepted. The next
    // input may be accepted on the same cycle that this result is consumed.
    assign s_axis_tready = rst_n
                         && (!m_axis_tvalid || m_axis_tready)
                         && ((samples_accepted != 0) || (cfg_window_samples != 0));

    always @(posedge clk) begin
        if (!rst_n) begin
            accumulator         <= 64'd0;
            samples_accepted    <= 32'd0;
            window_target       <= 32'd0;
            m_axis_tvalid       <= 1'b0;
            m_axis_power_sum    <= 64'd0;
            m_axis_sample_count <= 32'd0;
        end else begin
            if (m_axis_tvalid && m_axis_tready)
                m_axis_tvalid <= 1'b0;

            if (s_axis_tvalid && s_axis_tready) begin
                if (samples_accepted == 0) begin
                    window_target <= cfg_window_samples;
                    if (cfg_window_samples == 1) begin
                        m_axis_power_sum    <= power_extended;
                        m_axis_sample_count <= 32'd1;
                        m_axis_tvalid       <= 1'b1;
                        accumulator         <= 64'd0;
                        samples_accepted    <= 32'd0;
                    end else begin
                        accumulator      <= power_extended;
                        samples_accepted <= 32'd1;
                    end
                end else if (samples_accepted == window_target - 1'b1) begin
                    m_axis_power_sum    <= accumulator + power_extended;
                    m_axis_sample_count <= window_target;
                    m_axis_tvalid       <= 1'b1;
                    accumulator         <= 64'd0;
                    samples_accepted    <= 32'd0;
                end else begin
                    accumulator      <= accumulator + power_extended;
                    samples_accepted <= samples_accepted + 1'b1;
                end
            end
        end
    end
endmodule
