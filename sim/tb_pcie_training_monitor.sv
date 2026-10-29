`timescale 1ns/1ps
module tb_pcie_training_monitor;
    reg axi_clk=0,monitor_clk=0,enabled=0;
    always #4 if(enabled) axi_clk=~axi_clk;else axi_clk=0;
    always #5 monitor_clk=~monitor_clk;
    reg [5:0] ltssm=0;
    reg [2:0] speed=0;
    reg [3:0] width=0;
    reg err_cor=0,err_nonfatal=0,err_fatal=0,local_error_valid=0;
    reg [4:0] local_error=0;
    reg link_up=0,axi_reset_n=0;
    wire [127:0] snapshot;
    wire snapshot_valid;
    pcie_training_monitor dut(.*);
    integer handle,checks=0;
    reg [127:0] stopped;
    task automatic settle;
        repeat(220) @(negedge monitor_clk);
    endtask
    task automatic check_snapshot(input [5:0] state_value,input [63:0] mask_value,
            input [31:0] transitions_value,input [7:0] errors_value);
        begin
            settle();
            if(!snapshot_valid || snapshot[101:96]!==state_value || snapshot[63:0]!==mask_value ||
                snapshot[95:64]!==transitions_value || snapshot[116:109]!==errors_value)
                $fatal(1,"snapshot mismatch %032h",snapshot);
            checks=checks+1;
        end
    endtask
    initial begin
        // Wait past glbl.GSR and prove no fictitious sample without source clocks.
        settle();if(snapshot_valid) $fatal(1,"valid without source clock");checks=checks+1;
        enabled=1;check_snapshot(0,64'h1,0,0);
        @(negedge axi_clk);ltssm=1;
        @(negedge axi_clk);ltssm=2;
        @(negedge axi_clk);ltssm=6'h10;speed=3; width=4;link_up=1;axi_reset_n=1;
        // Two one-cycle states must appear in lifetime history even between transfers.
        check_snapshot(6'h10,64'h10007,3,0);
        if(snapshot[104:102]!=3 || snapshot[108:105]!=4 || snapshot[119:118]!=3)
            $fatal(1,"metadata mismatch");checks=checks+1;
        @(negedge axi_clk);err_cor=1;err_nonfatal=1;err_fatal=1;local_error=5'h15;local_error_valid=1;
        @(negedge axi_clk);err_cor=0;err_nonfatal=0;err_fatal=0;local_error_valid=0;
        check_snapshot(6'h10,64'h10007,3,8'haf);
        // An invalid local error bus must not be latched.
        @(negedge axi_clk);local_error=5'h1f;
        check_snapshot(6'h10,64'h10007,3,8'haf);
        @(negedge axi_clk);ltssm=0;link_up=0;axi_reset_n=0;
        check_snapshot(0,64'h10007,4,8'haf);
        @(negedge axi_clk);enabled=0;settle();stopped=snapshot;settle();
        if(snapshot!==stopped || !snapshot_valid) $fatal(1,"stopped-clock snapshot changed");checks=checks+1;
        ltssm=6'h3f;enabled=1;
        check_snapshot(6'h3f,64'h8000000000010007,5,8'haf);
        handle=$fopen("simulation_pass.txt","w");
        $fdisplay(handle,"PASS training_monitor_checks=%0d",checks);$fclose(handle);
        $display("PASS training_monitor_checks=%0d",checks);$finish;
    end
    initial begin #100000;$fatal(1,"Training monitor test timed out");end
endmodule
