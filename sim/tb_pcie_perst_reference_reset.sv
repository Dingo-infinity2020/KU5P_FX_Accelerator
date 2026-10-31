`timescale 1ns/1ps
module tb_pcie_perst_reference_reset;
    reg monitor_clk=0,run_clock=1,pcie_reset_n=0;
    always #5 if(run_clock) monitor_clk=~monitor_clk;else monitor_clk=0;
    wire core_reset_n,perst_seen,reset_observed_n;
    pcie_perst_reference_reset dut(.*);
    integer checks=0,h;
    task automatic cycles(input integer n);repeat(n) @(negedge monitor_clk);endtask
    initial begin
        cycles(30);
        if({core_reset_n,reset_observed_n,perst_seen}!==3'b000) $fatal(1,"initial assertion wrong");checks++;
        pcie_reset_n=1;#1;
        if({core_reset_n,reset_observed_n,perst_seen}!==3'b100) $fatal(1,"core waited for management clock");checks++;
        repeat(2) @(posedge monitor_clk);#1;
        if({core_reset_n,reset_observed_n,perst_seen}!==3'b110) $fatal(1,"two-cycle observation wrong");checks++;
        @(posedge monitor_clk);#1;
        if({core_reset_n,reset_observed_n,perst_seen}!==3'b111) $fatal(1,"PERST observation wrong");checks++;
        @(negedge monitor_clk);run_clock=0;#20;pcie_reset_n=0;#1;
        if({core_reset_n,reset_observed_n,perst_seen}!==3'b000) $fatal(1,"assertion waited for stopped clock");checks++;
        pcie_reset_n=1;#1;
        if({core_reset_n,reset_observed_n,perst_seen}!==3'b100) $fatal(1,"release entrance not raw PERST");checks++;
        run_clock=1;cycles(4);
        if({core_reset_n,reset_observed_n,perst_seen}!==3'b111) $fatal(1,"observer recovery failed");checks++;
        h=$fopen("simulation_pass.txt","w");$fdisplay(h,"PASS perst_reference_reset_checks=%0d",checks);$fclose(h);
        $display("PASS perst_reference_reset_checks=%0d",checks);$finish;
    end
    initial begin #10000;$fatal(1,"PERST reference timeout");end
endmodule
