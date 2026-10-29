`timescale 1ns/1ps
module tb_gt_isolation_reset;
    reg clk=0,manual_reset=0,qualifier_locked_async=0;
    always #5 clk=~clk;
    wire reset_all;
    gt_isolation_reset #(.HOLD_BITS(4)) dut (.*);
    integer checks=0,h;
    task automatic expect_held(input integer clocks);
        repeat(clocks) begin @(negedge clk);if(reset_all!==1) $fatal(1,"Premature reset release");end
    endtask
    task automatic allow_release(input integer cycles);
        begin
            // Deassert on cycle16 after a synchronized lock, or cycle18 when
            // the two-stage lock synchronizer must first observe a rising lock.
            expect_held(cycles-1);
            @(negedge clk);
            if(reset_all!==0) $fatal(1,"Reset failed to release");
        end
    endtask
    initial begin
        expect_held(40);checks++;
        qualifier_locked_async=1;allow_release(18);checks++;
        manual_reset=1;expect_held(4);manual_reset=0;allow_release(16);checks++;
        qualifier_locked_async=0;repeat(4) @(negedge clk);expect_held(10);
        qualifier_locked_async=1;allow_release(18);checks++;
        h=$fopen("reset_simulation_pass.txt","w");$fdisplay(h,"PASS gt_reset_checks=%0d",checks);$fclose(h);
        $display("PASS gt_reset_checks=%0d",checks);$finish;
    end
    initial begin #20000;$fatal(1,"Reset test timeout");end
endmodule
