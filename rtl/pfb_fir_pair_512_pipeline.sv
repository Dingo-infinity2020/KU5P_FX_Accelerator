// Four parallel taps per component; globally elastic five-stage pipeline.
// A frame header precedes exactly 512 paired samples. Histories advance on
// input transfers, independently of the later output frame boundary.
module pfb_fir_pair_512_pipeline #(
    parameter COEFF_FILE = "pfb_coeffs.mem"
) (
    input wire clk, rst_n,
    input wire frame_start, frame_valid_a, frame_valid_b,
    input wire s_axis_tvalid, output wire s_axis_tready,
    input wire signed [15:0] s_axis_a_i, s_axis_a_q, s_axis_b_i, s_axis_b_q,
    output wire m_axis_tvalid, input wire m_axis_tready,
    output reg signed [15:0] m_axis_a_i, m_axis_a_q, m_axis_b_i, m_axis_b_q,
    output wire [8:0] m_axis_phase,
    output wire contribution_a, contribution_b,
    output reg status_clip
);
    reg active, valid_a, valid_b, good_a, good_b;
    reg [2:0] history_valid_a, history_valid_b;
    reg [1:0] depth;
    reg [8:0] phase;
    reg [4:0] valid_pipe;
    reg [8:0] phase_pipe [0:4];
    reg [1:0] good_pipe [0:4];
    wire advance = !valid_pipe[4] || m_axis_tready;
    assign s_axis_tready = rst_n && active && advance;
    wire accept = s_axis_tvalid && s_axis_tready;
    assign m_axis_tvalid = rst_n && valid_pipe[4];
    assign m_axis_phase = phase_pipe[4];
    assign {contribution_b,contribution_a} = good_pipe[4];

    reg signed [17:0] initialization [0:2047];
    (* rom_style="block" *) reg signed [17:0] coefficients [0:3][0:511];
    integer tap_init, phase_init;
    initial begin
        $readmemh(COEFF_FILE, initialization);
        for(tap_init=0; tap_init<4; tap_init=tap_init+1)
            for(phase_init=0; phase_init<512; phase_init=phase_init+1)
                coefficients[tap_init][phase_init]=initialization[tap_init*512+phase_init];
    end
    (* ram_style="block" *) reg [63:0] delay1 [0:511], delay2 [0:511], delay3 [0:511];
    reg [63:0] current0,history1_0,history2_0,history3_0;
    reg [1:0] depth0;
    wire [63:0] sample0 [0:3];
    assign sample0[0]=current0;
    assign sample0[1]=depth0>=1 ? history1_0 : 64'd0;
    assign sample0[2]=depth0>=2 ? history2_0 : 64'd0;
    assign sample0[3]=depth0>=3 ? history3_0 : 64'd0;
    reg signed [17:0] coeff0 [0:3];
    reg signed [33:0] product1 [0:3][0:3];
    reg signed [34:0] low2 [0:3], high2 [0:3];
    reg signed [35:0] sum3 [0:3];
    wire [63:0] input_sample = {valid_b ? s_axis_b_q : 16'd0,valid_b ? s_axis_b_i : 16'd0,
                                valid_a ? s_axis_a_q : 16'd0,valid_a ? s_axis_a_i : 16'd0};
    // Read and shift use different phases. The same address is revisited only
    // after 512 accepted samples, much later than this write stage.
    always @(posedge clk) begin
        if(accept) begin
            current0<=input_sample;depth0<=depth;
            // Keep the raw RAM read directly registered. Startup masking is
            // applied AFTER this register so Vivado can infer block RAM.
            history1_0<=delay1[phase];
            history2_0<=delay2[phase];
            history3_0<=delay3[phase];
        end
        if(rst_n && advance && valid_pipe[0]) begin
            delay1[phase_pipe[0]]<=sample0[0];
            delay2[phase_pipe[0]]<=sample0[1];
            delay3[phase_pipe[0]]<=sample0[2];
        end
    end
    genvar t,c;
    generate for(t=0;t<4;t=t+1) begin: taps
        always @(posedge clk) if(accept) coeff0[t]<=coefficients[t][phase];
        for(c=0;c<4;c=c+1) begin: components
            always @(posedge clk) if(rst_n && advance)
                product1[t][c] <= $signed(sample0[t][c*16+:16]) * coeff0[t];
        end
    end endgenerate

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
    wire [16:0] quant [0:3];
    generate for(c=0;c<4;c=c+1) begin: sums
        assign quant[c]=requantize(sum3[c]);
        always @(posedge clk) if(rst_n && advance) begin
            low2[c] <= $signed({product1[0][c][33],product1[0][c]}) + $signed({product1[1][c][33],product1[1][c]});
            high2[c] <= $signed({product1[2][c][33],product1[2][c]}) + $signed({product1[3][c][33],product1[3][c]});
            sum3[c] <= $signed({low2[c][34],low2[c]}) + $signed({high2[c][34],high2[c]});
        end
    end endgenerate
    integer p;
    always @(posedge clk) begin
        if(!rst_n) begin
            active<=0; valid_a<=0; valid_b<=0; good_a<=0; good_b<=0;
            history_valid_a<=0; history_valid_b<=0; depth<=0; phase<=0;
            valid_pipe<=0; status_clip<=0;
            for(p=0;p<5;p=p+1) begin phase_pipe[p]<=0; good_pipe[p]<=0; end
            m_axis_a_i<=0; m_axis_a_q<=0; m_axis_b_i<=0; m_axis_b_q<=0;
        end else begin
            if(frame_start) begin
                active<=1; phase<=0; valid_a<=frame_valid_a; valid_b<=frame_valid_b;
                good_a<=frame_valid_a && (&history_valid_a);
                good_b<=frame_valid_b && (&history_valid_b);
            end
            if(accept) begin
                phase<=phase+1'b1;
                if(phase==511) begin
                    active<=0;
                    history_valid_a<={history_valid_a[1:0],valid_a};
                    history_valid_b<={history_valid_b[1:0],valid_b};
                    if(depth!=3) depth<=depth+1'b1;
                end
            end
            if(advance) begin
                valid_pipe<={valid_pipe[3:0],accept};
                phase_pipe[0]<=phase; good_pipe[0]<={good_b,good_a};
                for(p=1;p<5;p=p+1) begin phase_pipe[p]<=phase_pipe[p-1]; good_pipe[p]<=good_pipe[p-1]; end
                m_axis_a_i<=good_pipe[3][0] ? quant[0][15:0] : 16'd0;
                m_axis_a_q<=good_pipe[3][0] ? quant[1][15:0] : 16'd0;
                m_axis_b_i<=good_pipe[3][1] ? quant[2][15:0] : 16'd0;
                m_axis_b_q<=good_pipe[3][1] ? quant[3][15:0] : 16'd0;
                if(valid_pipe[3] && ((good_pipe[3][0] && (quant[0][16] || quant[1][16])) ||
                                    (good_pipe[3][1] && (quant[2][16] || quant[3][16])))) status_clip<=1;
            end
        end
    end
endmodule
