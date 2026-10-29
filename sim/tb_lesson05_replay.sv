`timescale 1ns/1ps
module tb_lesson05_replay;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0,start=0;
    wire result_valid,busy,done,error,core_clip,core_protocol_error;
    wire [649:0] result_payload;
    wire [31:0] input_count,result_count,run_cycles,signature;
    lesson05_replay dut(.*);
    reg [649:0] expected [0:2047];
    reg [63:0] source_samples [0:8191];
    reg checking=0,stalled=0;
    reg [63:0] held_data;
    reg held_last;
    integer checked=0,accepted=0,input_stalls=0,pass_file,i;
    always @(posedge clk) begin
        if(!rst_n) stalled=0;
        else begin
            if(error||core_clip||core_protocol_error) $fatal(1,"Replay error");
            if(stalled && (dut.state!=3 || dut.rom_data!==held_data ||
                (dut.sample_index==511)!==held_last)) $fatal(1,"ROM source changed while blocked");
            stalled=dut.state==3&&!dut.data_ready;
            held_data=dut.rom_data; held_last=(dut.sample_index==511);
            if(checking) begin
                if(stalled) input_stalls=input_stalls+1;
                if(dut.state==3&&dut.data_ready) begin
                    if(dut.rom_data!==source_samples[accepted]) $fatal(1,"ROM sample index %0d",accepted);
                    accepted=accepted+1;
                end
                if(result_valid) begin
                    if(checked>=2048 || result_payload!==expected[checked])
                        $fatal(1,"Replay result row %0d differs from integer reference",checked);
                    checked=checked+1;
                end
            end
        end
    end
    task reset_replay;
        begin
            @(negedge clk); rst_n=0; start=0;
            repeat(8) @(negedge clk);
            rst_n=1;
        end
    endtask
    initial begin
        $readmemh("expected_replay.mem",expected);
        $readmemh("replay_samples.mem",source_samples);
        reset_replay();
        repeat(30) begin
            @(negedge clk);
            if(busy||done||result_valid||input_count!=0) $fatal(1,"Replay auto-started");
        end
        // Cancel a partially filled hop, then check a clean replay against all rows.
        start=1;
        while(input_count<21) @(negedge clk);
        reset_replay(); checking=1; start=1;
        while(!done) @(negedge clk);
        if(accepted!=8192 || input_count!=8192 || checked!=2048 || result_count!=2048
            || signature!=32'h930aa3d5 || input_stalls==0)
            $fatal(1,"Incomplete replay: samples=%0d results=%0d signature=%h",accepted,checked,signature);
        // Holding start high must not silently begin another observation.
        repeat(60) begin
            @(negedge clk);
            if(busy||!done||result_valid||input_count!=8192||result_count!=2048)
                $fatal(1,"Replay repeated without reset");
        end
        $display("PASS replay_samples=%0d result_rows=%0d signature=%h cycles=%0d input_stalls=%0d",
                 accepted,checked,signature,run_cycles,input_stalls);
        pass_file=$fopen("simulation_pass.txt","w");
        $fdisplay(pass_file,"PASS replay_samples=%0d result_rows=%0d signature=%h cycles=%0d input_stalls=%0d",
                  accepted,checked,signature,run_cycles,input_stalls);
        $fclose(pass_file); $finish;
    end
    initial begin #12000000; $fatal(1,"Replay timeout"); end
endmodule
