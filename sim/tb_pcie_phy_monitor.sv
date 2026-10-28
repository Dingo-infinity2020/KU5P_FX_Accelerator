`timescale 1ns/1ps
module tb_pcie_phy_monitor;
    reg monitor_clk=0;
    always #5 monitor_clk=~monitor_clk;
    reg [7:0] flags_async=8'hff;
    wire [23:0] observation;
    pcie_phy_monitor #(.WIDTH(8)) dut(.*);
    integer checks=0,h;
    task automatic check(input [7:0] current_value,high_value,low_value);
        begin
            repeat(8) @(negedge monitor_clk);
            if(observation!=={low_value,high_value,current_value})
                $fatal(1,"PHY flag mismatch %06h expected %02h%02h%02h",observation,low_value,high_value,current_value);
            checks=checks+1;
        end
    endtask
    initial begin
        repeat(2) @(negedge monitor_clk);
        if(observation[23:8]!==0) $fatal(1,"Invented startup history");checks=checks+1;
        check(8'hff,8'hff,0);
        #2;flags_async=8'h5a;check(8'h5a,8'hff,8'ha5);
        #2;flags_async=0;check(0,8'hff,8'hff);
        #2;flags_async=8'hff;check(8'hff,8'hff,8'hff);
        h=$fopen("simulation_pass.txt","w");
        $fdisplay(h,"PASS phy_monitor_checks=%0d",checks);$fclose(h);
        $display("PASS phy_monitor_checks=%0d",checks);$finish;
    end
    initial begin #5000;$fatal(1,"PHY monitor timeout");end
endmodule
