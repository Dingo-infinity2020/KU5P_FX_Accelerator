// Sequential bins 0..511, one accepted pair per clock. Metadata travels with
// the products and RAM sums, so windows may overlap the result drain.
module channelized_x_pipeline #(
    parameter META_WIDTH=394
) (
    input wire clk, rst_n,
    input wire frame_first, frame_last,
    input wire [META_WIDTH-1:0] s_axis_meta,
    input wire s_axis_tvalid, output wire s_axis_tready,
    input wire [8:0] s_axis_bin,
    input wire signed [15:0] s_axis_a_i, s_axis_a_q, s_axis_b_i, s_axis_b_q,
    output reg m_axis_tvalid, input wire m_axis_tready,
    output reg [META_WIDTH-1:0] m_axis_meta,
    output reg [63:0] m_axis_auto_a, m_axis_auto_b,
    output reg signed [63:0] m_axis_cross_real, m_axis_cross_imag
);
    wire advance = !m_axis_tvalid || m_axis_tready;
    assign s_axis_tready = rst_n && advance;
    wire accept = s_axis_tvalid && s_axis_tready;
    reg [2:0] valid_pipe, last_pipe;
    reg first0, first1;
    reg [8:0] bin0,bin1,bin2;
    reg [META_WIDTH-1:0] meta0,meta1,meta2;
    (* ram_style="block" *) reg [63:0] bank_a [0:511],bank_b [0:511],bank_r [0:511],bank_i [0:511];
    reg [63:0] old_a0,old_b0,old_r0,old_i0,old_a1,old_b1,old_r1,old_i1;
    reg [63:0] sum_a2,sum_b2,sum_r2,sum_i2;
    reg signed [31:0] aa_ii,aa_qq,bb_ii,bb_qq,ab_ii,ab_qq,ab_qi,ab_iq;
    reg [32:0] power_a1,power_b1;
    reg signed [32:0] cross_r1,cross_i1;
    always @(posedge clk) begin
        if(accept) begin
            old_a0<=bank_a[s_axis_bin]; old_b0<=bank_b[s_axis_bin];
            old_r0<=bank_r[s_axis_bin]; old_i0<=bank_i[s_axis_bin];
        end
        if(rst_n && advance && valid_pipe[2] && !last_pipe[2]) begin
            bank_a[bin2]<=sum_a2; bank_b[bin2]<=sum_b2;
            bank_r[bin2]<=sum_r2; bank_i[bin2]<=sum_i2;
        end
    end
    always @(posedge clk) begin
        if(!rst_n) begin
            valid_pipe<=0; last_pipe<=0; first0<=0; first1<=0;
            bin0<=0;bin1<=0;bin2<=0;meta0<=0;meta1<=0;meta2<=0;
            m_axis_tvalid<=0; m_axis_meta<=0;
            m_axis_auto_a<=0;m_axis_auto_b<=0;m_axis_cross_real<=0;m_axis_cross_imag<=0;
        end else if(advance) begin
            valid_pipe<={valid_pipe[1:0],accept};
            last_pipe<={last_pipe[1:0],frame_last};
            first0<=frame_first;first1<=first0;
            bin0<=s_axis_bin;bin1<=bin0;bin2<=bin1;
            meta0<=s_axis_meta;meta1<=meta0;meta2<=meta1;
            aa_ii<=s_axis_a_i*s_axis_a_i;aa_qq<=s_axis_a_q*s_axis_a_q;
            bb_ii<=s_axis_b_i*s_axis_b_i;bb_qq<=s_axis_b_q*s_axis_b_q;
            ab_ii<=s_axis_a_i*s_axis_b_i;ab_qq<=s_axis_a_q*s_axis_b_q;
            ab_qi<=s_axis_a_q*s_axis_b_i;ab_iq<=s_axis_a_i*s_axis_b_q;
            power_a1<={1'b0,aa_ii}+{1'b0,aa_qq};power_b1<={1'b0,bb_ii}+{1'b0,bb_qq};
            cross_r1<=$signed({ab_ii[31],ab_ii})+$signed({ab_qq[31],ab_qq});
            cross_i1<=$signed({ab_qi[31],ab_qi})-$signed({ab_iq[31],ab_iq});
            old_a1<=old_a0;old_b1<=old_b0;old_r1<=old_r0;old_i1<=old_i0;
            sum_a2<=(first1 ? 64'd0 : old_a1)+{31'd0,power_a1};
            sum_b2<=(first1 ? 64'd0 : old_b1)+{31'd0,power_b1};
            sum_r2<=(first1 ? 64'd0 : old_r1)+{{31{cross_r1[32]}},cross_r1};
            sum_i2<=(first1 ? 64'd0 : old_i1)+{{31{cross_i1[32]}},cross_i1};
            m_axis_tvalid<=valid_pipe[2] && last_pipe[2];
            m_axis_meta<=meta2;
            m_axis_auto_a<=sum_a2;m_axis_auto_b<=sum_b2;
            m_axis_cross_real<=sum_r2;m_axis_cross_imag<=sum_i2;
        end
    end
endmodule
