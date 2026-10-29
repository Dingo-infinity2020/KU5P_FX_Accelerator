`timescale 1ns/1ps
module tb_pcie_ref_prescale;
    reg monitor_clk=0,ref_clk=0,enabled=1;
    real half_period=5.0;
    always #5 monitor_clk=~monitor_clk;
    always begin #(half_period);if(enabled) ref_clk=~ref_clk;else ref_clk=0;end
    wire divided;
    BUFG_GT #(.SIM_DEVICE("ULTRASCALE_PLUS")) prescale (
        .I(ref_clk),.CE(1'b1),.CEMASK(1'b0),.CLR(1'b0),.CLRMASK(1'b0),.DIV(3'b111),.O(divided));
    reg [7:0] counter=0;
    always @(posedge divided) counter<=counter+1'b1;
    reg sample1=0,sample2=0;
    always @(posedge monitor_clk) begin sample1<=counter[4];sample2<=sample1;end
    integer checks=0,handle;
    task automatic check_rate(input real half,input real expected_period);
        integer tick,last_tick,edges,total;
        reg previous;
        real average;
        begin
            half_period=half;
            repeat(2000) @(negedge monitor_clk);
            tick=0;last_tick=-1;edges=0;total=0;previous=sample2;
            while(edges<13 && tick<8192) begin
                @(negedge monitor_clk);tick=tick+1;
                if(sample2 && !previous) begin
                    if(last_tick>=0) begin
                        if((tick-last_tick)<expected_period-1.01 || (tick-last_tick)>expected_period+1.01)
                            $fatal(1,"Unexpected period %0d expected %0f",tick-last_tick,expected_period);
                        total=total+tick-last_tick;
                    end
                    last_tick=tick;edges=edges+1;
                end
                previous=sample2;
            end
            if(edges!=13) $fatal(1,"Missing clock edges");
            average=total/12.0;
            if(average<expected_period-0.1 || average>expected_period+0.1) $fatal(1,"Bad average %0f",average);
            $display("PRESCALE half_ns=%0f average_monitor_period=%0f",half,average);
            checks=checks+1;
        end
    endtask
    initial begin
        check_rate(5.0,256.0); // 100 MHz raw, 12.5 MHz counter clock
        check_rate(1.0,51.2);  // 500 MHz raw, 62.5 MHz counter clock
        check_rate(4.0,204.8);// 125 MHz raw, 15.625 MHz counter clock
        enabled=0;repeat(100) @(negedge monitor_clk);
        begin: stopped
            reg held;held=sample2;
            repeat(300) begin @(negedge monitor_clk);if(sample2!==held) $fatal(1,"Stopped clock changed");end
        end
        checks=checks+1;
        handle=$fopen("simulation_pass.txt","w");
        $fdisplay(handle,"PASS ref_prescale_checks=%0d",checks);$fclose(handle);
        $display("PASS ref_prescale_checks=%0d",checks);$finish;
    end
    initial begin #500000;$fatal(1,"Prescale test timeout");end
endmodule
