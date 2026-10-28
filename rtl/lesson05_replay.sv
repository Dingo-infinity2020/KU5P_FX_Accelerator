// One-shot, 8192-sample BRAM replay through the unchanged lesson04 PFB-FX.
// A synchronous ROM read is followed by a stable valid/ready holding state.
module lesson05_replay (
    input wire clk, input wire rst_n, input wire start,
    output wire result_valid,
    output wire [649:0] result_payload,
    output wire busy, done,
    output reg error,
    output reg [31:0] input_count, result_count, run_cycles, signature,
    output wire core_clip, core_protocol_error
);
    localparam IDLE=0, HEADER=1, FETCH=2, DATA=3, DRAIN=4, DONE=5, FAILED=6;
    reg [2:0] state;
    reg [3:0] frame_index;
    reg [8:0] sample_index;
    reg [12:0] address;
    (* rom_style="block" *) reg [63:0] samples [0:8191];
    reg [1:0] good [0:15];
    reg [63:0] rom_data;
    initial begin
        $readmemh("replay_samples.mem",samples);
        $readmemh("replay_good.mem",good);
    end
    always @(posedge clk) if(state==FETCH) rom_data<=samples[address];
    assign busy=(state==HEADER || state==FETCH || state==DATA || state==DRAIN);
    assign done=(state==DONE);
    wire header_ready, data_ready;
    wire [8:0] bin;
    wire last;
    wire [31:0] wid,wa,wb,wab,M,epoch,config_id;
    wire [63:0] first_frame,last_frame,auto_a,auto_b;
    wire signed [63:0] cross_real,cross_imag;
    wire [15:0] source_a,source_b;
    two_channel_pfb_fx fx (
        .clk(clk),.rst_n(rst_n),.cfg_window_frames(32'd4),.cfg_epoch_id(32'd5005),
        .cfg_config_id(32'h00050001),.cfg_first_frame(64'd1000),.cfg_source_a(16'd0),.cfg_source_b(16'd8),
        .s_frame_valid(state==HEADER),.s_frame_ready(header_ready),.s_frame_id(64'd1000+{60'd0,frame_index}),
        .s_frame_epoch_id(32'd5005),.s_frame_config_id(32'h00050001),.s_frame_source_a(16'd0),.s_frame_source_b(16'd8),
        .s_frame_good_a(good[frame_index][0]),.s_frame_good_b(good[frame_index][1]),
        .s_axis_tvalid(state==DATA),.s_axis_tready(data_ready),.s_axis_tlast(sample_index==511),
        .s_axis_a_i(rom_data[15:0]),.s_axis_a_q(rom_data[31:16]),
        .s_axis_b_i(rom_data[47:32]),.s_axis_b_q(rom_data[63:48]),
        .m_axis_tvalid(result_valid),.m_axis_tready(1'b1),.m_axis_bin(bin),.m_axis_tlast(last),
        .m_axis_window_id(wid),.m_axis_weight_a(wa),.m_axis_weight_b(wb),.m_axis_weight_ab(wab),
        .m_axis_window_frames(M),.m_axis_epoch_id(epoch),.m_axis_config_id(config_id),
        .m_axis_first_frame(first_frame),.m_axis_last_frame(last_frame),
        .m_axis_source_a(source_a),.m_axis_source_b(source_b),
        .m_axis_auto_a(auto_a),.m_axis_auto_b(auto_b),.m_axis_cross_real(cross_real),.m_axis_cross_imag(cross_imag),
        .status_protocol_error(core_protocol_error),.status_clip(core_clip)
    );
    assign result_payload={auto_a,auto_b,cross_real,cross_imag,bin,last,wid,wa,wb,wab,M,
                           first_frame,last_frame,epoch,config_id,source_a,source_b};
    reg [31:0] folded;
    integer j;
    always @* begin
        folded={22'd0,result_payload[649:640]};
        for(j=0;j<20;j=j+1) folded=folded^result_payload[j*32+:32];
    end
    wire bad_metadata=bin!=result_count[8:0] || wid!={30'd0,result_count[10:9]}
        || last!=(bin==511) || M!=4 || epoch!=5005 || config_id!=32'h00050001
        || source_a!=0 || source_b!=8 || first_frame!=(64'd1000+{60'd0,result_count[10:9],2'b00})
        || last_frame!=first_frame+3;
    always @(posedge clk) begin
        if(!rst_n) begin
            state<=IDLE; frame_index<=0; sample_index<=0; address<=0;
            input_count<=0; result_count<=0; run_cycles<=0; signature<=0; error<=0;
        end else begin
            if(busy) run_cycles<=run_cycles+1'b1;
            case(state)
                IDLE: if(start) state<=HEADER;
                HEADER: if(header_ready) begin state<=FETCH; sample_index<=0; end
                FETCH: state<=DATA;
                DATA: if(data_ready) begin
                    input_count<=input_count+1'b1;
                    address<=address+1'b1; sample_index<=sample_index+1'b1;
                    if(sample_index==511) begin
                        if(frame_index==15) state<=DRAIN;
                        else begin frame_index<=frame_index+1'b1; state<=HEADER; end
                    end else state<=FETCH;
                end
            endcase
            if(result_valid) begin
                signature<={signature[26:0],signature[31:27]}^folded;
                result_count<=result_count+1'b1;
                if(bad_metadata || result_count>=2048) error<=1;
                if(result_count==2047) begin
                    if(state!=DRAIN || input_count!=8192) error<=1;
                    state<=DONE;
                end
            end
            if(core_clip || core_protocol_error || (busy && run_cycles>=999999)) begin
                state<=FAILED; error<=1;
            end
        end
    end
endmodule
