`timescale 1ns/1ps
module tb_pcie_clock_monitor;
    reg monitor_clk=0,ref_clk=0,axi_clk=0,ref_enabled=0,axi_enabled=0;
    always #5 monitor_clk=~monitor_clk;
    always #4 if(ref_enabled) ref_clk=~ref_clk;else ref_clk=0;
    always #2 if(axi_enabled) axi_clk=~axi_clk;else axi_clk=0;
    wire ref_recent,axi_recent;
    pcie_clock_monitor #(.SOURCE_BIT(2),.TIMEOUT_BITS(8)) dut(.*);
    integer checks=0,handle;
    task automatic check(input bit expect_ref,expect_axi);
        begin
            repeat(300) @(negedge monitor_clk);
            if({ref_recent,axi_recent}!=={expect_ref,expect_axi})
                $fatal(1,"clock watchdog ref=%b axi=%b expected=%b%b",ref_recent,axi_recent,expect_ref,expect_axi);
            checks=checks+1;
        end
    endtask
    initial begin
        check(0,0);
        ref_enabled=1;check(1,0);
        axi_enabled=1;check(1,1);
        ref_enabled=0;check(0,1);
        axi_enabled=0;check(0,0);
        ref_enabled=1;axi_enabled=1;check(1,1);
        axi_enabled=0;check(1,0);
        handle=$fopen("simulation_pass.txt","w");
        $fdisplay(handle,"PASS clock_monitor_checks=%0d",checks);$fclose(handle);
        $display("PASS clock_monitor_checks=%0d",checks);$finish;
    end
    initial begin #30000;$fatal(1,"Watchdog test timed out");end
endmodule
