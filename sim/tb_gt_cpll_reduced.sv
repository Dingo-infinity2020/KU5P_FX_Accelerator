`timescale 1ns/1ps
// A distinct one-channel CPLL/5Gbps model test, not the QPLL1/8Gbps design.
module tb_gt_cpll_reduced;
    reg clk=0,refclk=0,manual_reset=1;
    always #5 clk=~clk;
    always #5 refclk=~refclk;
    wire reset_all,powergood,locked,txpma,rxpma,txdone,rxdone;
    gt_isolation_reset controller (.clk(clk),.manual_reset(manual_reset),
        .qualifier_locked_async(1'b1),.reset_all(reset_all));
    lesson05e_gt_cpll_sim dut (
        .gtwiz_userclk_tx_reset_in(~txpma),.gtwiz_userclk_rx_reset_in(~rxpma),
        .gtwiz_reset_clk_freerun_in(clk),.drpclk_in(clk),.gtrefclk0_in(refclk),
        .gtwiz_reset_all_in(reset_all),.gtwiz_reset_tx_pll_and_datapath_in(1'b0),
        .gtwiz_reset_tx_datapath_in(1'b0),.gtwiz_reset_rx_pll_and_datapath_in(1'b0),
        .gtwiz_reset_rx_datapath_in(1'b0),.gtwiz_reset_tx_done_out(txdone),
        .gtwiz_reset_rx_done_out(rxdone),.gtwiz_userdata_tx_in(32'b0),
        .gtyrxp_in(1'b0),.gtyrxn_in(1'b1),.rx8b10ben_in(1'b1),.tx8b10ben_in(1'b1),
        .txctrl0_in(16'b0),.txctrl1_in(16'b0),.txctrl2_in(8'b0),
        .txelecidle_in(1'b1),.txinhibit_in(1'b1),.cplllock_out(locked),
        .gtpowergood_out(powergood),.txpmaresetdone_out(txpma),.rxpmaresetdone_out(rxpma));
    integer checks=0,h,cycles;
    reg seen_unlocked=0,seen_notdone=0;
    task automatic await_ready;
        integer cycles;
        begin
            cycles=0;
            while((locked!==1'b1 || txdone!==1'b1) && cycles<100000) begin @(negedge clk);cycles++;end
            if(cycles==100000 || powergood!==1'b1 || txpma!==1'b1 || reset_all!==1'b0)
                $fatal(1,"CPLL test timeout lock=%b txdone=%b pma=%b power=%b",locked,txdone,txpma,powergood);
        end
    endtask
    initial begin
        repeat(100) @(negedge clk);
        if(reset_all!==1'b1 || txdone!==1'b0) $fatal(1,"Initial reset not held");checks++;
        manual_reset=0;await_ready();checks++;
        manual_reset=1;repeat(1000) @(negedge clk);
        // PG182: reset-all starts the sequence on the request's falling edge.
        // Holding the request high need not hold the actual CPLL reset high.
        if(reset_all!==1'b1) $fatal(1,"Reset request not held");checks++;
        manual_reset=0;cycles=0;
        while(cycles<100000) begin
            @(negedge clk);cycles++;
            if(locked===1'b0) seen_unlocked=1;
            if(txdone===1'b0) seen_notdone=1;
            if(seen_unlocked && seen_notdone && locked===1'b1 && txdone===1'b1 && reset_all===1'b0) break;
        end
        if(cycles==100000) $fatal(1,"Reset/recovery not observed unlock=%b notdone=%b",seen_unlocked,seen_notdone);
        checks++;
        h=$fopen("cpll_simulation_pass.txt","w");$fdisplay(h,"PASS gt_cpll_reduced_checks=%0d",checks);$fclose(h);
        $display("PASS gt_cpll_reduced_checks=%0d",checks);$finish;
    end
    initial begin #2500000;$fatal(1,"CPLL reduced simulation timeout");end
endmodule
