`timescale 1ns/1ps
module tb_gt_isolation_body;
    reg SYS_CLK=0,pcie_refclk_p=0,manual_reset=1,qualifier_locked=0;
    wire pcie_refclk_n=~pcie_refclk_p;
    always #5 SYS_CLK=~SYS_CLK;
    always #5 pcie_refclk_p=~pcie_refclk_p;
    wire [3:0] pcie_tx_p,pcie_tx_n;
    wire monitor_clk=SYS_CLK;
    wire reset_all;
    wire [95:0] observation;
    wire [31:0] heartbeat;
    wire [1:0] clock_samples;
    // One real GTYE4 model with an externally supplied qualification stimulus.
    // The real SYS_CLK/MMCM wrapper is tested separately to limit model size.
    gt_isolation_body #(.SIM_SINGLE_CHANNEL(1)) dut (.pcie_reset_n(1'b1),
        .qualifier_stopped(1'b0),.pcie_rx_p(4'b0),.pcie_rx_n(4'hf),.*);
    integer checks=0,h;
    task automatic await_tx_ready;
        integer cycles;
        begin
            cycles=0;
            while((observation[4]!==1'b1 || observation[21]!==1'b1 || dut.txdone[0]!==1'b1) && cycles<70000) begin
                @(negedge SYS_CLK);cycles++;
            end
            if(cycles==70000) $fatal(1,"GT timeout flags=%08x",observation[31:0]);
            if(observation[3:0]!==4'h1 || observation[25]!==1'b1 || observation[27]!==1'b0)
                $fatal(1,"GT prerequisites missing flags=%08x",observation[31:0]);
        end
    endtask
    initial begin
        repeat(100) @(negedge SYS_CLK);
        if(reset_all!==1'b1 || observation[25]!==1'b0) $fatal(1,"Initial reset not held");checks++;
        manual_reset=0;qualifier_locked=1;await_tx_ready();checks++;
        manual_reset=1;qualifier_locked=0;repeat(1000) @(negedge SYS_CLK);
        if(reset_all!==1'b1 || observation[4]!==1'b0) $fatal(1,"Manual reset did not reset QPLL");checks++;
        manual_reset=0;qualifier_locked=1;await_tx_ready();checks++;
        h=$fopen("gt_single_simulation_pass.txt","w");$fdisplay(h,"PASS gt_single_model_checks=%0d",checks);$fclose(h);
        $display("PASS gt_single_model_checks=%0d flags=%08x",checks,observation[31:0]);$finish;
    end
    initial begin #1600000;$fatal(1,"GT simulation timeout");end
endmodule
