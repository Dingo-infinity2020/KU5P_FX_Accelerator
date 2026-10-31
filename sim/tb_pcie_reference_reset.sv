`timescale 1ns/1ps
module tb_pcie_reference_reset;
    reg monitor_clk=0,run_clock=1,pcie_reset_n=0,manual_reset=1;
    always #5 if(run_clock) monitor_clk=~monitor_clk;else monitor_clk=0;
    wire core_reset_n,perst_seen,reset_observed_n;
    pcie_reference_reset dut(.*);
    integer checks=0,h;
    task automatic cycles(input integer n);repeat(n) @(negedge monitor_clk);endtask
    initial begin
        cycles(30);
        if(core_reset_n || perst_seen || reset_observed_n) $fatal(1,"unsafe initial reset");checks++;
        pcie_reset_n=1;cycles(6);
        if(!perst_seen || core_reset_n || reset_observed_n) $fatal(1,"manual hold lost");checks++;
        manual_reset=0;#1;
        if(!core_reset_n || reset_observed_n) $fatal(1,"core release must not wait for monitor");checks++;
        @(posedge monitor_clk);#1;
        if(reset_observed_n) $fatal(1,"observer released without two samples");checks++;
        @(posedge monitor_clk);#1;
        if(!reset_observed_n) $fatal(1,"observer release missing");checks++;
        @(negedge monitor_clk);run_clock=0;#20;pcie_reset_n=0;#1;
        if(core_reset_n || perst_seen || reset_observed_n) $fatal(1,"assertion depended on stopped clock");checks++;
        pcie_reset_n=1;#1;
        if(!core_reset_n || perst_seen || reset_observed_n) $fatal(1,"reference reset entrance changed");checks++;
        run_clock=1;cycles(5);
        if(!perst_seen || !reset_observed_n) $fatal(1,"observer failed after clock restart");checks++;
        manual_reset=1;#1;
        if(core_reset_n || reset_observed_n || !perst_seen) $fatal(1,"manual assertion changed PERST observer");checks++;
        manual_reset=0;cycles(3);
        if(!core_reset_n || !reset_observed_n || !perst_seen) $fatal(1,"manual release observation failed");checks++;
        h=$fopen("simulation_pass.txt","w");$fdisplay(h,"PASS reference_reset_checks=%0d",checks);$fclose(h);
        $display("PASS reference_reset_checks=%0d",checks);$finish;
    end
    initial begin #10000;$fatal(1,"reference reset timeout");end
endmodule
