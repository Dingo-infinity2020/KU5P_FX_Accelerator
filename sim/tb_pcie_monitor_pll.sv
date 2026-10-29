`timescale 1ns/1ps
module tb_pcie_monitor_pll;
    reg clk=0,enabled=1,reset=1;
    real half_period=5.0;
    always begin #(half_period);if(enabled) clk=~clk;else clk=0;end
    wire raw_feedback,feedback,locked,stopped;
    BUFGCE #(.SIM_DEVICE("ULTRASCALE_PLUS")) feedback_buffer (.I(raw_feedback),.CE(1'b1),.O(feedback));
    MMCME4_ADV #(.CLKIN1_PERIOD(10.0),.CLKIN2_PERIOD(10.0),.CLKFBOUT_MULT_F(10.0),.DIVCLK_DIVIDE(1),
        .CLKOUT0_DIVIDE_F(10.0),.CLKOUT1_DIVIDE(10),.CLKOUT2_DIVIDE(10),.CLKOUT3_DIVIDE(10),
        .CLKOUT4_DIVIDE(10),.CLKOUT5_DIVIDE(10),.CLKOUT6_DIVIDE(10)) qualifier (
        .CLKIN1(clk),.CLKIN2(1'b0),.CLKINSEL(1'b1),.CLKFBOUT(raw_feedback),.CLKFBIN(feedback),
        .LOCKED(locked),.CLKINSTOPPED(stopped),.RST(reset),.PWRDWN(1'b0),.CDDCREQ(1'b0),
        .DADDR(7'b0),.DI(16'b0),.DCLK(1'b0),.DEN(1'b0),.DWE(1'b0),.PSCLK(1'b0),.PSEN(1'b0),.PSINCDEC(1'b0));
    integer checks=0,handle;
    task automatic check(input bit expected_locked,expected_stopped);
        begin
            #20000;
            if(locked!==expected_locked || stopped!==expected_stopped)
                $fatal(1,"MMCM locked=%b stopped=%b expected=%b%b",locked,stopped,expected_locked,expected_stopped);
            checks=checks+1;
        end
    endtask
    initial begin
        #500;reset=0;check(1,0);
        enabled=0;check(0,1);
        reset=1;enabled=1;#500;reset=0;check(1,0);
        reset=1;half_period=4.0;#500;reset=0;check(1,0); // lock is not absolute 100MHz proof
        handle=$fopen("simulation_pass.txt","w");$fdisplay(handle,"PASS monitor_pll_checks=%0d",checks);$fclose(handle);
        $display("PASS monitor_pll_checks=%0d",checks);$finish;
    end
    initial begin #200000;$fatal(1,"MMCM qualifier timeout");end
endmodule
