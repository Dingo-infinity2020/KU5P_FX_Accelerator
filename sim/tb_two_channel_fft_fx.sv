`timescale 1ns/1ps

module tb_two_channel_fft_fx;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0;
    reg [31:0] cfg_window_frames=0;
    reg s_axis_tvalid=0;
    wire s_axis_tready;
    reg signed [15:0] s_axis_a_i=0, s_axis_a_q=0, s_axis_b_i=0, s_axis_b_q=0;
    wire m_axis_tvalid;
    reg m_axis_tready=0;
    wire [8:0] m_axis_bin;
    wire m_axis_tlast;
    wire [31:0] m_axis_window_id, m_axis_sample_count;
    wire [63:0] m_axis_auto_a, m_axis_auto_b;
    wire signed [63:0] m_axis_cross_real, m_axis_cross_imag;
    wire status_protocol_error, status_clip;
    two_channel_fft_fx dut (.*);

    reg checking=0, allow_fault=0;
    integer ready_mode=2;
    reg [31:0] ready_rng=32'h278ad511, input_rng=32'h13579bdf;
    integer accepted_pairs=0, checked_fft_pairs=0, checked_bins=0;
    integer output_stalls=0, fft_stalls=0, input_stalls=0, cycles=0;
    integer first_main_cycle=0, last_main_cycle=0;
    reg was_stalled=0;
    reg [329:0] held_result;
    integer fft_file, fx_file, status, k, raw_ai, raw_aq, raw_bi, raw_bq;
    integer quant_ai, quant_aq, quant_bi, quant_bq, expected_window, expected_bin, expected_count;
    reg [63:0] pa, pb;
    reg signed [63:0] vr, vi;

    always @(negedge clk) begin
        ready_rng={ready_rng[30:0],ready_rng[31]^ready_rng[21]^ready_rng[1]^ready_rng[0]};
        case(ready_mode)
            1: m_axis_tready=0;
            2: m_axis_tready=1;
            default: m_axis_tready=ready_rng[0]|ready_rng[3];
        endcase
    end

    always @(posedge clk) begin
        cycles=cycles+1;
        if(!rst_n) was_stalled=0;
        else begin
            if(status_clip) $fatal(1,"Unexpected legal-input requantization clipping");
            if(status_protocol_error && !allow_fault) $fatal(1,"FFT index/TLAST protocol error");
            if(was_stalled && (!m_axis_tvalid ||
                {m_axis_auto_a,m_axis_auto_b,m_axis_cross_real,m_axis_cross_imag,
                 m_axis_sample_count,m_axis_window_id,m_axis_bin,m_axis_tlast} !== held_result))
                $fatal(1,"Result or metadata changed under backpressure");
            was_stalled=m_axis_tvalid&&!m_axis_tready;
            held_result={m_axis_auto_a,m_axis_auto_b,m_axis_cross_real,m_axis_cross_imag,
                         m_axis_sample_count,m_axis_window_id,m_axis_bin,m_axis_tlast};
            if(checking) begin
                if(s_axis_tvalid&&s_axis_tready) begin
                    if(accepted_pairs==0) first_main_cycle=cycles;
                    accepted_pairs=accepted_pairs+1;
                end
                if(s_axis_tvalid&&!s_axis_tready) input_stalls=input_stalls+1;
                if(was_stalled) output_stalls=output_stalls+1;
                if(dut.fft_valid&&!dut.fft_ready) fft_stalls=fft_stalls+1;
                if(dut.fft_valid&&dut.fft_ready) begin
                    status=$fscanf(fft_file,"%d %d %d %d %d %d %d %d %d\n",
                                   k,raw_ai,raw_aq,raw_bi,raw_bq,quant_ai,quant_aq,quant_bi,quant_bq);
                    if(status!=9) $fatal(1,"Unexpected FFT output or truncated reference");
                    if(dut.fft_bin!==k || dut.fft_last!==(k==511)
                        || $signed(dut.fft_a_i)!==raw_ai || $signed(dut.fft_a_q)!==raw_aq
                        || $signed(dut.fft_b_i)!==raw_bi || $signed(dut.fft_b_q)!==raw_bq)
                        $fatal(1,"FFT pair %0d bin %0d: got (%0d,%0d,%0d,%0d), expected (%0d,%0d,%0d,%0d)",
                               checked_fft_pairs,k,dut.fft_a_i,dut.fft_a_q,dut.fft_b_i,dut.fft_b_q,
                               raw_ai,raw_aq,raw_bi,raw_bq);
                    if($signed(dut.quant_a_i[15:0])!==quant_ai || $signed(dut.quant_a_q[15:0])!==quant_aq
                        || $signed(dut.quant_b_i[15:0])!==quant_bi || $signed(dut.quant_b_q[15:0])!==quant_bq)
                        $fatal(1,"Requantization mismatch at FFT pair %0d",checked_fft_pairs);
                    checked_fft_pairs=checked_fft_pairs+1;
                end
                if(m_axis_tvalid&&m_axis_tready) begin
                    status=$fscanf(fx_file,"%d %d %d %d %d %d %d\n",
                                   expected_window,expected_bin,expected_count,pa,pb,vr,vi);
                    if(status!=7) $fatal(1,"Unexpected FX output or truncated reference");
                    if(m_axis_window_id!==expected_window || m_axis_bin!==expected_bin
                        || m_axis_sample_count!==expected_count || m_axis_tlast!==(expected_bin==511)
                        || m_axis_auto_a!==pa || m_axis_auto_b!==pb
                        || m_axis_cross_real!==vr || m_axis_cross_imag!==vi)
                        $fatal(1,"FX window/bin %0d/%0d: got (%0d,%0d,%0d,%0d) count=%0d id=%0d bin=%0d expected (%0d,%0d,%0d,%0d) count=%0d",
                               expected_window,expected_bin,m_axis_auto_a,m_axis_auto_b,
                               m_axis_cross_real,m_axis_cross_imag,m_axis_sample_count,m_axis_window_id,m_axis_bin,
                               pa,pb,vr,vi,expected_count);
                    checked_bins=checked_bins+1;
                    last_main_cycle=cycles;
                end
            end
        end
    end

    task send_pair(input integer ai,aq,bi,bq,
                   input reg change_config=0,input reg [31:0] new_config=0);
        begin
            @(negedge clk);
            if(change_config) cfg_window_frames=new_config;
            s_axis_a_i=ai; s_axis_a_q=aq; s_axis_b_i=bi; s_axis_b_q=bq;
            s_axis_tvalid=1;
            @(posedge clk);
            while(!s_axis_tready) @(posedge clk);
        end
    endtask
    task idle_input;
        begin @(negedge clk); s_axis_tvalid=0; end
    endtask
    task reset_core;
        begin
            @(negedge clk); rst_n=0; s_axis_tvalid=0;
            repeat(6) @(negedge clk);
            rst_n=1;
        end
    endtask
    task check_quantization(input reg signed [25:0] value,input reg [16:0] expected);
        begin
            if(dut.requantize(value)!==expected)
                $fatal(1,"Directed ties-even/saturation test failed at %0d",value);
        end
    endtask

    integer stimulus, count, sample, index, ai,aq,bi,bq, scan;
    integer windows=0, pass_file;
    reg [31:0] mutation;
    initial begin
        reset_core();
        check_quantization(512,17'h00000);
        check_quantization(-512,17'h00000);
        check_quantization(1536,17'h00002);
        check_quantization(-1536,17'h0fffe);
        check_quantization(513,17'h00001);
        check_quantization(-513,17'h0ffff);
        check_quantization(26'sd33554431,17'h17fff);
        check_quantization(-26'sd33554432,17'h08000);
        cfg_window_frames=0;
        @(negedge clk); s_axis_tvalid=1;
        repeat(24) begin
            @(posedge clk);
            if(s_axis_tready||m_axis_tvalid) $fatal(1,"Zero window accepted");
        end
        idle_input();

        // Cancel a partially loaded FFT frame.
        cfg_window_frames=2;
        for(index=0;index<20;index=index+1) send_pair(1234,-5678,30000,-30000);
        reset_core();

        // Fill the per-bin memories with one frame of an incomplete window.
        cfg_window_frames=3;
        for(index=0;index<512;index=index+1) send_pair(30000,-20000,-12345,23456);
        idle_input();
        while(dut.frame_busy) @(negedge clk);
        if(m_axis_tvalid||dut.frames_in_window!=1) $fatal(1,"Partial integration boundary failed");
        reset_core();

        // Cancel a held output with most of this FFT frame still in flight.
        ready_mode=1; cfg_window_frames=1;
        for(index=0;index<512;index=index+1) send_pair(8192,0,0,4096);
        idle_input();
        while(!m_axis_tvalid) @(negedge clk);
        if(m_axis_bin!=0 || m_axis_auto_a!=16777216 || m_axis_auto_b!=4194304
            || m_axis_cross_real!=0 || m_axis_cross_imag!=-8388608)
            $fatal(1,"Known DC example failed");
        repeat(8) @(negedge clk);
        reset_core();
        ready_mode=0;

        fft_file=$fopen("expected_fft.txt","r");
        fx_file=$fopen("expected_fx.txt","r");
        stimulus=$fopen("stimulus.txt","r");
        if(!fft_file||!fx_file||!stimulus) $fatal(1,"Missing generated reference files");
        checking=1;
        while(!$feof(stimulus)) begin
            scan=$fscanf(stimulus,"%d %d\n",count,mutation);
            if(scan==2) begin
                @(negedge clk); s_axis_tvalid=0; cfg_window_frames=count;
                for(sample=0;sample<count*512;sample=sample+1) begin
                    scan=$fscanf(stimulus,"%d %d %d %d\n",ai,aq,bi,bq);
                    if(scan!=4) $fatal(1,"Truncated stimulus record");
                    send_pair(ai,aq,bi,bq,sample==1,mutation);
                    input_rng={input_rng[30:0],input_rng[31]^input_rng[21]^input_rng[1]^input_rng[0]};
                    if(input_rng[2:0]==0) begin idle_input(); @(negedge clk); end
                end
                idle_input();
                windows=windows+1;
            end else if(!$feof(stimulus)) $fatal(1,"Malformed stimulus header");
        end
        while(m_axis_window_id!=windows) @(negedge clk);
        repeat(12) @(negedge clk);
        if(checked_bins!=windows*512 || checked_fft_pairs!=accepted_pairs
            || output_stalls==0 || fft_stalls==0 || input_stalls==0)
            $fatal(1,"Incomplete coverage bins=%0d fft=%0d input=%0d",checked_bins,checked_fft_pairs,accepted_pairs);
        scan=$fscanf(fft_file,"%d",k);
        if(scan==1) $fatal(1,"Unconsumed FFT references");
        scan=$fscanf(fx_file,"%d",k);
        if(scan==1) $fatal(1,"Unconsumed FX references");
        $fclose(stimulus); $fclose(fft_file); $fclose(fx_file);
        checking=0;

        // Deliberately corrupt one core's bin tag in simulation. Mismatched
        // pairs must set a sticky error, halt, and recover only after reset.
        allow_fault=1; cfg_window_frames=1; ready_mode=1;
        for(index=0;index<512;index=index+1) send_pair(1000,0,1000,0);
        idle_input();
        force dut.fft_pair.b_out_user=16'd1;
        while(!status_protocol_error) @(negedge clk);
        repeat(8) @(negedge clk);
        if(m_axis_tvalid||s_axis_tready) $fatal(1,"Tag mismatch did not halt the pipeline");
        release dut.fft_pair.b_out_user;
        reset_core();
        cfg_window_frames=0; ready_mode=2;
        repeat(24) @(negedge clk);
        if(status_protocol_error||m_axis_tvalid) $fatal(1,"Error/reset recovery failed");
        allow_fault=0;
        pass_file=$fopen("simulation_pass.txt","w");
        if(!pass_file) $fatal(1,"Cannot create pass marker");
        $fdisplay(pass_file,"PASS windows=%0d output_bins=%0d fft_pairs=%0d input_pairs=%0d output_stalls=%0d fft_stalls=%0d input_stalls=%0d main_cycles=%0d tag_faults=1",
                  windows,checked_bins,checked_fft_pairs,accepted_pairs,output_stalls,fft_stalls,input_stalls,last_main_cycle-first_main_cycle+1);
        $fclose(pass_file);
        $display("PASS windows=%0d output_bins=%0d fft_pairs=%0d input_pairs=%0d output_stalls=%0d fft_stalls=%0d input_stalls=%0d main_cycles=%0d tag_faults=1",
                 windows,checked_bins,checked_fft_pairs,accepted_pairs,output_stalls,fft_stalls,input_stalls,last_main_cycle-first_main_cycle+1);
        $finish;
    end
    initial begin
        #100000000;
        $fatal(1,"Timeout: inputs=%0d fft=%0d bins=%0d busy=%b loaded=%b state=%d frames=%d config=%d error=%b",
               accepted_pairs,checked_fft_pairs,checked_bins,dut.frame_busy,dut.frame_loaded,
               dut.x_engine.state,dut.frames_in_window,cfg_window_frames,status_protocol_error);
    end
endmodule
