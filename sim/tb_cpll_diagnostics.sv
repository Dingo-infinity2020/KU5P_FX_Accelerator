`timescale 1ns/1ps
// Tests the diagnostic contract with mock status inputs. It does not cover
// the hardware-only connections to the GT primitive's RESET/PD inputs.
module tb_cpll_diagnostics;
    reg clk=0;
    always #5 clk=~clk;
    reg [7:0] flags=0;
    reg [2:0] controls=0;
    reg manual=1,reset_all=1,ref_qualified=0,perst_n=0,progress=0;
    reg [31:0] ref_counter=0,heartbeat=0;
    wire [95:0] observation;
    wire [127:0] events;
    integer checks=0,h;
    always @(posedge clk) begin
        heartbeat<=heartbeat+1'b1;
        if(progress && heartbeat[2:0]==0) ref_counter<=ref_counter+1'b1;
    end
    cpll_diagnostics dut (.monitor_clk(clk),.asynchronous_flags(flags),
        .control_observe(controls),.manual_reset(manual),.reset_all(reset_all),
        .ref_qualified(ref_qualified),.pcie_reset_n(perst_n),
        .ref_counter(ref_counter),.heartbeat(heartbeat),
        .observation(observation),.event_counters(events));
    initial begin
        repeat(12) @(negedge clk);
        if(observation[16] || observation[13] || events!=0) $fatal(1,"Unqualified startup falsely active");checks++;
        flags=8'h53;perst_n=1;
        repeat(12) @(negedge clk);
        if(events[31:0]!=1 || events[95:64]!=1 || !observation[14]) $fatal(1,"Rising events/status map failed");checks++;
        repeat(40) @(negedge clk);
        if(events[31:0]!=1 || events[95:64]!=1) $fatal(1,"Sustained high recounted as edges");checks++;
        flags=8'h41;
        repeat(12) @(negedge clk);
        if(events[63:32]!=1 || events[127:96]!=1 || !observation[33] || !observation[65])
            $fatal(1,"Falling events or high/low history failed");checks++;
        manual=0;reset_all=0;ref_qualified=1;progress=1;
        repeat(40) @(negedge clk);
        if(!observation[13] || observation[31:24]!=1 || events[31:0]!=1)
            $fatal(1,"Qualified activity/release event failed");checks++;
        progress=0;repeat(4200) @(negedge clk);
        if(observation[13] || !observation[12]) $fatal(1,"Stopped source not detected");checks++;
        manual=1;reset_all=1;ref_qualified=0;
        repeat(12) @(negedge clk);
        if(events[31:0]!=1 || events[63:32]!=1 || observation[31:24]!=1)
            $fatal(1,"Manual reset erased lifetime history");checks++;
        controls=3'b111;
        repeat(12) @(negedge clk);
        if(!observation[16] || observation[9:8]!=2'b11) $fatal(1,"Mock control packing/valid failed");checks++;
        h=$fopen("cpll_diagnostics_pass.txt","w");$fdisplay(h,"PASS cpll_diagnostics_checks=%0d",checks);$fclose(h);
        $display("PASS cpll_diagnostics_checks=%0d",checks);$finish;
    end
    initial begin #100000;$fatal(1,"Diagnostic unit timeout");end
endmodule
