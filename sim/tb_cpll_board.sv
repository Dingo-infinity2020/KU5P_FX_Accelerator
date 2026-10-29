`timescale 1ns/1ps
module tb_cpll_board;
    reg monitor_clk=0,pcie_refclk_p=0,manual_reset=1;
    always #5 monitor_clk=~monitor_clk;
    always #5 pcie_refclk_p=~pcie_refclk_p;
    wire reset_all;
    wire [95:0] observation;
    wire [31:0] heartbeat,ref_counter;
    wire [127:0] event_counters;
    lesson05g_cpll_body dut (
        .monitor_clk(monitor_clk),.qualifier_locked(1'b1),.qualifier_stopped(1'b0),
        .pcie_refclk_p(pcie_refclk_p),.pcie_refclk_n(~pcie_refclk_p),.pcie_reset_n(1'b1),
        .pcie_rx_p(1'b0),.pcie_rx_n(1'b1),.pcie_tx_p(),.pcie_tx_n(),
        .manual_reset(manual_reset),.reset_all(reset_all),.observation(observation),
        .heartbeat(heartbeat),.ref_counter(ref_counter),.event_counters(event_counters));
    integer checks=0,h,cycles,attempt;
    reg [31:0] saved_ref;
    reg [127:0] saved_events;
    reg saw_unlock,saw_notdone;
    initial begin
        repeat(100) @(negedge monitor_clk);
        for(attempt=0;attempt<3;attempt++) begin
            if(reset_all!==1'b1 || observation[12]!==1'b0 || observation[16]!==1'b0)
                $fatal(1,"Reset/qualification or observer simulation-valid contract failed");
            checks++;
            saved_events=event_counters;manual_reset=0;cycles=0;saw_unlock=0;saw_notdone=0;
            while(cycles<400000) begin
                @(negedge monitor_clk);cycles++;
                if(observation[1]===1'b0) saw_unlock=1;
                if(observation[4]===1'b0) saw_notdone=1;
                if(saw_unlock && saw_notdone && observation[1]===1'b1 && observation[4]===1'b1
                    && observation[2]===1'b1 && observation[0]===1'b1 && reset_all===1'b0) break;
            end
            if(cycles==400000) $fatal(1,"CPLL board init timeout attempt=%0d status=%h",attempt,observation[31:0]);
            if(observation[31:24]!==attempt+1) $fatal(1,"Initialization release count mismatch");
            checks++;
            saved_ref=ref_counter;
            repeat(1000) @(negedge monitor_clk);
            if(ref_counter-saved_ref<120 || ref_counter-saved_ref>130 || !observation[13])
                $fatal(1,"Qualified Gray counter failed delta=%0d status=%h",ref_counter-saved_ref,observation[31:0]);
            checks++;
            if(event_counters[31:0]<=saved_events[31:0] || event_counters[95:64]<=saved_events[95:64])
                $fatal(1,"Real lock/TXdone rising events not recorded");
            if(attempt>0 && (event_counters[63:32]<=saved_events[63:32] || event_counters[127:96]<=saved_events[127:96]))
                $fatal(1,"Real lock/TXdone falling events not recorded");
            checks++;
            manual_reset=1;repeat(1000) @(negedge monitor_clk);
        end
        h=$fopen("cpll_board_pass.txt","w");$fdisplay(h,"PASS cpll_board_checks=%0d",checks);$fclose(h);
        $display("PASS cpll_board_checks=%0d",checks);$finish;
    end
    initial begin #20000000;$fatal(1,"CPLL board timeout");end
endmodule
