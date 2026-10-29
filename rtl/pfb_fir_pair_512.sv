// Four taps per phase, 512 phases, hop=512. One shared coefficient ROM and
// four real MACs serve two complex inputs. Replay interface: may backpressure.
module pfb_fir_pair_512 #(
    parameter COEFF_FILE = "pfb_coeffs.mem"
) (
    input wire clk, input wire rst_n,
    input wire frame_start, frame_valid_a, frame_valid_b,
    input wire s_axis_tvalid, output wire s_axis_tready,
    input wire signed [15:0] s_axis_a_i, s_axis_a_q, s_axis_b_i, s_axis_b_q,
    output reg m_axis_tvalid, input wire m_axis_tready,
    output reg signed [15:0] m_axis_a_i, m_axis_a_q, m_axis_b_i, m_axis_b_q,
    output wire [8:0] m_axis_phase,
    output reg contribution_a, contribution_b,
    output reg status_clip
);
    localparam IDLE=0, MAC=1, HOLD=2;
    reg [1:0] state, tap;
    reg active, valid_a, valid_b;
    reg [2:0] history_valid_a, history_valid_b;
    reg [1:0] depth;
    reg [8:0] phase;
    assign m_axis_phase = phase;
    assign s_axis_tready = rst_n && active && state==IDLE;

    // Signed Q17 coefficients; FIR output has a further factor 1/2 of headroom.
    (* rom_style="block" *) reg signed [17:0] coeffs [0:2047];
    initial $readmemh(COEFF_FILE, coeffs);
    reg signed [17:0] coefficient;
    (* ram_style="block" *) reg [63:0] delay1 [0:511], delay2 [0:511], delay3 [0:511];
    reg [63:0] current_sample, previous1, previous2, previous3;
    wire [63:0] input_sample = {valid_b ? s_axis_b_q : 16'd0, valid_b ? s_axis_b_i : 16'd0,
                                valid_a ? s_axis_a_q : 16'd0, valid_a ? s_axis_a_i : 16'd0};
    wire accept = s_axis_tvalid && s_axis_tready;
    wire write_history = state==MAC && tap==3 && rst_n;
    // No reset on memories: depth masks all unread history after reset.
    always @(posedge clk) begin
        if (accept) begin
            previous1 <= depth>=1 ? delay1[phase] : 64'd0;
            previous2 <= depth>=2 ? delay2[phase] : 64'd0;
            previous3 <= depth>=3 ? delay3[phase] : 64'd0;
        end
        if (write_history) begin
            delay1[phase] <= current_sample;
            delay2[phase] <= previous1;
            delay3[phase] <= previous2;
        end
    end
    // A synchronous ROM read for each tap. All four components share it.
    always @(posedge clk) begin
        if (accept) coefficient <= coeffs[{2'd0,phase}];
        else if (state==MAC && tap!=3) coefficient <= coeffs[{tap+2'd1,phase}];
    end
    wire [63:0] tap_sample = tap==0 ? current_sample : tap==1 ? previous1 : tap==2 ? previous2 : previous3;
    wire signed [15:0] ai=$signed(tap_sample[15:0]), aq=$signed(tap_sample[31:16]);
    wire signed [15:0] bi=$signed(tap_sample[47:32]), bq=$signed(tap_sample[63:48]);
    (* use_dsp="yes" *) wire signed [33:0] product_ai=ai*coefficient, product_aq=aq*coefficient;
    (* use_dsp="yes" *) wire signed [33:0] product_bi=bi*coefficient, product_bq=bq*coefficient;
    reg signed [35:0] accumulator_ai, accumulator_aq, accumulator_bi, accumulator_bq;
    wire signed [35:0] sum_ai=accumulator_ai+{{2{product_ai[33]}},product_ai};
    wire signed [35:0] sum_aq=accumulator_aq+{{2{product_aq[33]}},product_aq};
    wire signed [35:0] sum_bi=accumulator_bi+{{2{product_bi[33]}},product_bi};
    wire signed [35:0] sum_bq=accumulator_bq+{{2{product_bq[33]}},product_bq};

    function automatic [16:0] requantize(input reg signed [35:0] value);
        reg signed [36:0] rounded;
        begin
            rounded=$signed({value[35],value}) >>> 18;
            if(value[17:0]>131072 || (value[17:0]==131072 && rounded[0])) rounded=rounded+1'b1;
            if(rounded>32767) requantize={1'b1,16'h7fff};
            else if(rounded < -32768) requantize={1'b1,16'h8000};
            else requantize={1'b0,rounded[15:0]};
        end
    endfunction
    wire [16:0] quant_ai=requantize(sum_ai), quant_aq=requantize(sum_aq);
    wire [16:0] quant_bi=requantize(sum_bi), quant_bq=requantize(sum_bq);

    always @(posedge clk) begin
        if(!rst_n) begin
            state<=IDLE; active<=0; phase<=0; tap<=0; depth<=0;
            valid_a<=0; valid_b<=0; history_valid_a<=0; history_valid_b<=0;
            contribution_a<=0; contribution_b<=0; status_clip<=0;
            current_sample<=0; accumulator_ai<=0; accumulator_aq<=0;
            accumulator_bi<=0; accumulator_bq<=0;
            m_axis_tvalid<=0; m_axis_a_i<=0; m_axis_a_q<=0; m_axis_b_i<=0; m_axis_b_q<=0;
        end else begin
            if(frame_start) begin
                active<=1; phase<=0; valid_a<=frame_valid_a; valid_b<=frame_valid_b;
                contribution_a<=frame_valid_a && (&history_valid_a);
                contribution_b<=frame_valid_b && (&history_valid_b);
            end
            if(accept) begin
                current_sample<=input_sample; tap<=0; state<=MAC;
                accumulator_ai<=0; accumulator_aq<=0; accumulator_bi<=0; accumulator_bq<=0;
            end
            if(state==MAC) begin
                accumulator_ai<=sum_ai; accumulator_aq<=sum_aq;
                accumulator_bi<=sum_bi; accumulator_bq<=sum_bq;
                if(tap==3) begin
                    m_axis_a_i<=contribution_a ? quant_ai[15:0] : 16'd0;
                    m_axis_a_q<=contribution_a ? quant_aq[15:0] : 16'd0;
                    m_axis_b_i<=contribution_b ? quant_bi[15:0] : 16'd0;
                    m_axis_b_q<=contribution_b ? quant_bq[15:0] : 16'd0;
                    if((contribution_a && (quant_ai[16] || quant_aq[16])) ||
                       (contribution_b && (quant_bi[16] || quant_bq[16]))) status_clip<=1;
                    m_axis_tvalid<=1; state<=HOLD;
                end else tap<=tap+1'b1;
            end
            if(m_axis_tvalid && m_axis_tready) begin
                m_axis_tvalid<=0; state<=IDLE; phase<=phase+1'b1;
                if(phase==511) begin
                    active<=0;
                    history_valid_a<={history_valid_a[1:0],valid_a};
                    history_valid_b<={history_valid_b[1:0],valid_b};
                    if(depth!=3) depth<=depth+1'b1;
                end
            end
        end
    end
endmodule
