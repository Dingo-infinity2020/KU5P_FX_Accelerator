`timescale 1ns/1ps
module tb_two_channel_pfb_fx;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0;
    reg [31:0] cfg_window_frames=0, cfg_epoch_id=0, cfg_config_id=0;
    reg [63:0] cfg_first_frame=0;
    reg [15:0] cfg_source_a=10, cfg_source_b=11;
    reg s_frame_valid=0;
    wire s_frame_ready;
    reg [63:0] s_frame_id=0;
    reg [31:0] s_frame_epoch_id=0, s_frame_config_id=0;
    reg [15:0] s_frame_source_a=0, s_frame_source_b=0;
    reg s_frame_good_a=1, s_frame_good_b=1;
    reg s_axis_tvalid=0, s_axis_tlast=0;
    wire s_axis_tready;
    reg signed [15:0] s_axis_a_i=0,s_axis_a_q=0,s_axis_b_i=0,s_axis_b_q=0;
    wire m_axis_tvalid,m_axis_tlast;
    reg m_axis_tready=1;
    wire [8:0] m_axis_bin;
    wire [31:0] m_axis_window_id,m_axis_weight_a,m_axis_weight_b,m_axis_weight_ab;
    wire [31:0] m_axis_window_frames,m_axis_epoch_id,m_axis_config_id;
    wire [63:0] m_axis_first_frame,m_axis_last_frame;
    wire [15:0] m_axis_source_a,m_axis_source_b;
    wire [63:0] m_axis_auto_a,m_axis_auto_b;
    wire signed [63:0] m_axis_cross_real,m_axis_cross_imag;
    wire status_protocol_error,status_clip;
    two_channel_pfb_fx dut(.*);

    reg checking=0,allow_fault=0;
    integer ready_mode=1;
    reg [31:0] ready_rng=32'h6284d519,input_rng=32'h42147893;
    integer accepted_pairs=0,checked_pfb=0,checked_fft=0,checked_bins=0;
    integer output_stalls=0,pfb_stalls=0,input_stalls=0,protocol_faults=0;
    integer current_case=-1;
    wire [649:0] result_pack={m_axis_auto_a,m_axis_auto_b,m_axis_cross_real,m_axis_cross_imag,
        m_axis_bin,m_axis_tlast,m_axis_window_id,m_axis_weight_a,m_axis_weight_b,m_axis_weight_ab,
        m_axis_window_frames,m_axis_first_frame,m_axis_last_frame,m_axis_epoch_id,m_axis_config_id,
        m_axis_source_a,m_axis_source_b};
    wire [74:0] pfb_pack={dut.pfb_a_i,dut.pfb_a_q,dut.pfb_b_i,dut.pfb_b_q,
                          dut.pfb_phase,dut.good_a,dut.good_b};
    reg [649:0] held_result;
    reg [74:0] held_pfb;
    reg out_stalled=0,filter_stalled=0;
    integer pfb_file,fft_file,fx_file,scan,status;
    integer ec,ek,ega,egb,eai,eaq,ebi,ebq,rai,raq,rbi,rbq;
    reg [31:0] ew,em,ewa,ewb,ewab,ee,ev;
    reg [63:0] ef,el,pa,pb;
    reg [15:0] esa,esb;
    reg signed [63:0] vr,vi;
    always @(negedge clk) begin
        ready_rng={ready_rng[30:0],ready_rng[31]^ready_rng[21]^ready_rng[1]^ready_rng[0]};
        m_axis_tready=ready_mode==1 ? 1'b1 : ready_mode==2 ? 1'b0 : ready_rng[0]|ready_rng[3];
    end
    always @(posedge clk) begin
        if(!rst_n) begin out_stalled=0; filter_stalled=0; end
        else begin
            if(status_clip) $fatal(1,"Legal input clipped");
            if(status_protocol_error && !allow_fault) $fatal(1,"Unexpected protocol error");
            if(out_stalled && (!m_axis_tvalid || result_pack!==held_result))
                $fatal(1,"FX result/metadata changed while stalled");
            if(filter_stalled && (!dut.pfb_valid || pfb_pack!==held_pfb))
                $fatal(1,"PFB result changed while stalled");
            out_stalled=m_axis_tvalid&&!m_axis_tready; held_result=result_pack;
            filter_stalled=dut.pfb_valid&&!dut.pfb_ready; held_pfb=pfb_pack;
            if(checking) begin
                if(s_axis_tvalid&&s_axis_tready) accepted_pairs=accepted_pairs+1;
                if(s_axis_tvalid&&!s_axis_tready) input_stalls=input_stalls+1;
                if(out_stalled) output_stalls=output_stalls+1;
                if(filter_stalled) pfb_stalls=pfb_stalls+1;
                if(dut.pfb_valid&&dut.pfb_ready) begin
                    status=$fscanf(pfb_file,"%d %d %d %d %d %d %d %d\n",ec,ek,ega,egb,eai,eaq,ebi,ebq);
                    if(status!=8 || ec!=current_case || dut.pfb_phase!==ek || dut.good_a!==ega[0]
                        || dut.good_b!==egb[0] || $signed(dut.pfb_a_i)!==eai || $signed(dut.pfb_a_q)!==eaq
                        || $signed(dut.pfb_b_i)!==ebi || $signed(dut.pfb_b_q)!==ebq)
                        $fatal(1,"PFB case=%0d pair=%0d phase=%0d got (%0d,%0d,%0d,%0d), expected (%0d,%0d,%0d,%0d)",
                            current_case,checked_pfb,dut.pfb_phase,dut.pfb_a_i,dut.pfb_a_q,dut.pfb_b_i,dut.pfb_b_q,eai,eaq,ebi,ebq);
                    checked_pfb=checked_pfb+1;
                end
                if(dut.fft_valid&&dut.fft_ready) begin
                    status=$fscanf(fft_file,"%d %d %d %d %d %d %d %d %d %d\n",ec,ek,rai,raq,rbi,rbq,eai,eaq,ebi,ebq);
                    if(status!=10 || ec!=current_case || dut.fft_bin!==ek || dut.fft_last!==(ek==511)
                        || $signed(dut.fft_a_i)!==rai || $signed(dut.fft_a_q)!==raq
                        || $signed(dut.fft_b_i)!==rbi || $signed(dut.fft_b_q)!==rbq
                        || $signed(dut.quant_a_i[15:0])!==eai || $signed(dut.quant_a_q[15:0])!==eaq
                        || $signed(dut.quant_b_i[15:0])!==ebi || $signed(dut.quant_b_q[15:0])!==ebq)
                        $fatal(1,"FFT/quantization case=%0d pair=%0d bin=%0d",current_case,checked_fft,ek);
                    checked_fft=checked_fft+1;
                end
                if(m_axis_tvalid&&m_axis_tready) begin
                    status=$fscanf(fx_file,"%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",
                        ec,ew,ek,ef,el,em,ewa,ewb,ewab,pa,pb,vr,vi,ee,ev,esa,esb);
                    if(status!=17 || ec!=current_case || m_axis_window_id!==ew || m_axis_bin!==ek
                        || m_axis_tlast!==(ek==511) || m_axis_first_frame!==ef || m_axis_last_frame!==el
                        || m_axis_window_frames!==em || m_axis_weight_a!==ewa || m_axis_weight_b!==ewb
                        || m_axis_weight_ab!==ewab || m_axis_epoch_id!==ee || m_axis_config_id!==ev
                        || m_axis_source_a!==esa || m_axis_source_b!==esb
                        || m_axis_auto_a!==pa || m_axis_auto_b!==pb
                        || m_axis_cross_real!==vr || m_axis_cross_imag!==vi)
                        $fatal(1,"FX case=%0d window=%0d bin=%0d got (%0d,%0d,%0d,%0d) W=(%0d,%0d,%0d), expected (%0d,%0d,%0d,%0d) W=(%0d,%0d,%0d)",
                            current_case,ew,ek,m_axis_auto_a,m_axis_auto_b,m_axis_cross_real,m_axis_cross_imag,
                            m_axis_weight_a,m_axis_weight_b,m_axis_weight_ab,pa,pb,vr,vi,ewa,ewb,ewab);
                    checked_bins=checked_bins+1;
                end
            end
        end
    end

    reg [31:0] case_epoch,case_config;
    reg [15:0] case_a,case_b;
    task reset_core;
        begin
            @(negedge clk); rst_n=0; s_frame_valid=0; s_axis_tvalid=0;
            repeat(6) @(negedge clk);
            rst_n=1;
        end
    endtask
    task send_header(input reg [63:0] id,input reg good_a,good_b,input integer fault=0);
        begin
            @(negedge clk);
            s_frame_valid=1; s_frame_id=id; s_frame_good_a=good_a; s_frame_good_b=good_b;
            s_frame_epoch_id=case_epoch; s_frame_config_id=case_config;
            s_frame_source_a=case_a; s_frame_source_b=case_b;
            case(fault)
                1:s_frame_id=id+1;
                2:begin s_frame_source_a=case_b; s_frame_source_b=case_a; end
                3:s_frame_config_id=case_config^1;
                4:s_frame_epoch_id=case_epoch^1;
                5:s_frame_source_b=case_a;
            endcase
            @(posedge clk); while(!s_frame_ready) @(posedge clk);
            @(negedge clk); s_frame_valid=0;
        end
    endtask
    task send_pair(input integer ai,aq,bi,bq,input reg last);
        begin
            @(negedge clk);
            s_axis_tvalid=1; s_axis_tlast=last;
            s_axis_a_i=ai; s_axis_a_q=aq; s_axis_b_i=bi; s_axis_b_q=bq;
            @(posedge clk); while(!s_axis_tready) @(posedge clk);
        end
    endtask
    task idle_input;
        begin @(negedge clk); s_axis_tvalid=0; end
    endtask
    task expect_fault;
        begin
            repeat(4) @(negedge clk);
            if(!status_protocol_error || s_frame_ready || s_axis_tready || m_axis_tvalid)
                $fatal(1,"Protocol fault did not halt input");
            protocol_faults=protocol_faults+1;
        end
    endtask
    task setup_directed;
        begin
            cfg_window_frames=1; cfg_first_frame=100;
            cfg_epoch_id=1; cfg_config_id=2; cfg_source_a=10; cfg_source_b=11;
            case_epoch=1; case_config=2; case_a=10; case_b=11;
        end
    endtask
    task test_fir_round(input reg signed [35:0] v,input reg [16:0] expected);
        begin if(dut.pfb.requantize(v)!==expected) $fatal(1,"FIR ties-even/saturation at %0d",v); end
    endtask

    integer i,j,n,stimulus,case_number,M,frame_count,ga,gb,ai,aq,bi,bq,pass_file;
    integer completed_cases=0,total_windows=0;
    reg [63:0] first,id;
    initial begin
        reset_core(); setup_directed(); cfg_window_frames=0;
        @(negedge clk); s_frame_valid=1;
        repeat(20) begin @(posedge clk); if(s_frame_ready) $fatal(1,"M=0 accepted initial header"); end
        reset_core(); setup_directed();
        test_fir_round(131072,17'h00000); test_fir_round(-131072,17'h00000);
        test_fir_round(393216,17'h00002); test_fir_round(-393216,17'h0fffe);
        test_fir_round(131073,17'h00001); test_fir_round(-131073,17'h0ffff);
        test_fir_round(36'sd8589934592,17'h17fff);
        test_fir_round(-36'sd8589934593,17'h08000);
        test_fir_round(-36'sd8590196736,17'h18000);

        // Reset while an input hop and its history writes are incomplete.
        send_header(100,1,1);
        for(i=0;i<19;i=i+1) send_pair(32767,-32768,30000,-30000,0);
        reset_core(); allow_fault=1;
        for(j=1;j<=5;j=j+1) begin
            setup_directed();
            if(j==5) cfg_source_b=10;
            send_header(100,1,1,j); expect_fault(); reset_core();
        end
        setup_directed(); send_header(100,1,1);
        send_pair(123,456,789,-100,1); idle_input(); expect_fault(); reset_core();
        setup_directed(); send_header(100,1,1);
        for(i=0;i<512;i=i+1) send_pair(0,0,0,0,0);
        idle_input(); expect_fault(); reset_core();
        setup_directed(); send_header(100,1,1);
        for(i=0;i<512;i=i+1) send_pair(0,0,0,0,i==511);
        idle_input(); while(m_axis_window_id!=1) @(negedge clk);
        send_header(100,1,1); expect_fault(); reset_core(); allow_fault=0;

        // Reset while the final window spectrum is held by a blocked sink.
        setup_directed(); ready_mode=2; send_header(100,1,1);
        for(i=0;i<512;i=i+1) send_pair(30000,20000,-30000,10000,i==511);
        idle_input(); while(!m_axis_tvalid) @(negedge clk);
        repeat(12) @(negedge clk);
        reset_core(); ready_mode=0;

        stimulus=$fopen("stimulus.txt","r"); pfb_file=$fopen("expected_pfb.txt","r");
        fft_file=$fopen("expected_fft.txt","r"); fx_file=$fopen("expected_fx.txt","r");
        if(!stimulus||!pfb_file||!fft_file||!fx_file) $fatal(1,"Missing vectors");
        checking=1;
        while(!$feof(stimulus)) begin
            scan=$fscanf(stimulus,"%d %d %d %d %d %d %d %d\n",
                         case_number,M,first,case_epoch,case_config,case_a,case_b,frame_count);
            if(scan==8) begin
                reset_core(); current_case=case_number;
                cfg_window_frames=M; cfg_first_frame=first;
                cfg_epoch_id=case_epoch; cfg_config_id=case_config; cfg_source_a=case_a; cfg_source_b=case_b;
                for(j=0;j<frame_count;j=j+1) begin
                    scan=$fscanf(stimulus,"%d %d %d\n",id,ga,gb);
                    if(scan!=3) $fatal(1,"Bad hop header");
                    send_header(id,ga[0],gb[0]);
                    // Session config must remain the first accepted snapshot.
                    cfg_window_frames=0; cfg_first_frame=0; cfg_epoch_id=0;
                    cfg_config_id=0; cfg_source_a=0; cfg_source_b=0;
                    for(n=0;n<512;n=n+1) begin
                        scan=$fscanf(stimulus,"%d %d %d %d\n",ai,aq,bi,bq);
                        if(scan!=4) $fatal(1,"Bad sample row");
                        send_pair(ai,aq,bi,bq,n==511);
                        input_rng={input_rng[30:0],input_rng[31]^input_rng[21]^input_rng[1]^input_rng[0]};
                        if(input_rng[3:0]==0) begin idle_input(); @(negedge clk); end
                    end
                    idle_input();
                end
                while(m_axis_window_id!=frame_count/M) @(negedge clk);
                completed_cases=completed_cases+1; total_windows=total_windows+frame_count/M;
            end else if(!$feof(stimulus)) $fatal(1,"Bad scenario header");
        end
        repeat(12) @(negedge clk);
        if(checked_bins!=total_windows*512 || checked_pfb!=accepted_pairs || checked_fft!=accepted_pairs
            || output_stalls==0 || input_stalls==0 || pfb_stalls==0 || protocol_faults!=8)
            $fatal(1,"Incomplete coverage input=%0d pfb=%0d fft=%0d bins=%0d stalls=%0d/%0d/%0d faults=%0d",
                accepted_pairs,checked_pfb,checked_fft,checked_bins,input_stalls,pfb_stalls,output_stalls,protocol_faults);
        scan=$fscanf(pfb_file,"%d",i); if(scan==1) $fatal(1,"Unconsumed PFB rows");
        scan=$fscanf(fft_file,"%d",i); if(scan==1) $fatal(1,"Unconsumed FFT rows");
        scan=$fscanf(fx_file,"%d",i); if(scan==1) $fatal(1,"Unconsumed FX rows");
        $display("PASS windows=%0d cases=%0d input_pairs=%0d pfb_pairs=%0d fft_pairs=%0d output_bins=%0d output_stalls=%0d pfb_stalls=%0d input_stalls=%0d protocol_faults=%0d",
            total_windows,completed_cases,accepted_pairs,checked_pfb,checked_fft,checked_bins,output_stalls,pfb_stalls,input_stalls,protocol_faults);
        pass_file=$fopen("simulation_pass.txt","w");
        $fdisplay(pass_file,"PASS windows=%0d cases=%0d input_pairs=%0d pfb_pairs=%0d fft_pairs=%0d output_bins=%0d output_stalls=%0d pfb_stalls=%0d input_stalls=%0d protocol_faults=%0d",
            total_windows,completed_cases,accepted_pairs,checked_pfb,checked_fft,checked_bins,output_stalls,pfb_stalls,input_stalls,protocol_faults);
        $fclose(pass_file); $finish;
    end
    initial begin #60000000; $fatal(1,"Timeout"); end
endmodule
