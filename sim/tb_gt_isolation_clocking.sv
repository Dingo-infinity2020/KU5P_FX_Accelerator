`timescale 1ns/1ps
module tb_gt_isolation_clocking;
    reg SYS_CLK=0,manual_reset=1,enabled=1;
    real half_period=5.0;
    always begin #(half_period);if(enabled) SYS_CLK=~SYS_CLK;else SYS_CLK=0;end
    wire monitor_clk,qualifier_locked,qualifier_stopped;
    gt_isolation_clocking dut (.*);
    integer checks=0,h;
    task automatic check(input bit locked,stopped);
        begin
            #20000;
            if(qualifier_locked!==locked || qualifier_stopped!==stopped) $fatal(1,"Clock qualifier mismatch");
            checks++;
        end
    endtask
    initial begin
        #500;manual_reset=0;check(1,0);
        enabled=0;check(0,1);
        manual_reset=1;enabled=1;#500;manual_reset=0;check(1,0);
        manual_reset=1;half_period=4.0;#500;manual_reset=0;check(1,0);
        h=$fopen("clocking_simulation_pass.txt","w");$fdisplay(h,"PASS gt_clocking_checks=%0d",checks);$fclose(h);
        $display("PASS gt_clocking_checks=%0d",checks);$finish;
    end
    initial begin #200000;$fatal(1,"Clocking test timeout");end
endmodule
