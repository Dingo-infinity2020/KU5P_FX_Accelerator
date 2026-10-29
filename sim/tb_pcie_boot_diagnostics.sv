`timescale 1ns/1ps
module tb_pcie_boot_diagnostics;
    reg monitor_clk=0,ref_div_clk=0,axi_clk=0;
    reg monitor_enable=1,ref_enable=0,axi_enable=0;
    always #5 if(monitor_enable) monitor_clk=~monitor_clk;else monitor_clk=0;
    always #40 if(ref_enable) ref_div_clk=~ref_div_clk;else ref_div_clk=0;
    always #4 if(axi_enable) axi_clk=~axi_clk;else axi_clk=0;
    reg pcie_reset_n=0,manual_reset=1;
    wire perst_seen,endpoint_reset_n;
    pcie_boot_reset_bridge bridge(.*);
    reg [63:0] raw_async=0;
    reg qualifier_locked=1,qualifier_stopped=0,link_up=0,axi_reset_n=0;
    reg [127:0] training_snapshot=0;
    reg training_valid=0,capture_arm=0;
    reg [2:0] read_address=0;
    wire [63:0] raw_current,raw_ever_high,raw_ever_low;
    wire [127:0] clocks,metadata;
    wire [255:0] read_data;
    wire [31:0] controls;
    pcie_boot_diagnostics #(.WINDOW_CYCLES(64),.ACTIVE_TIMEOUT(32),
        .ADDR_WIDTH(3),.REF_MIN(6),.REF_MAX(10)) dut(.*);
    integer checks=0,h,i;
    reg [255:0] first_record;
    reg [15:0] old_epoch;
    reg [31:0] ref_before;
    task automatic cycles(input integer count);
        repeat(count) @(negedge monitor_clk);
    endtask
    task automatic arm;
        begin capture_arm=1;cycles(2);capture_arm=0;cycles(3);end
    endtask
    initial begin
        cycles(30);
        if(endpoint_reset_n || perst_seen || raw_ever_high) $fatal(1,"unsafe initial state");checks++;
        pcie_reset_n=1;cycles(8);
        if(!perst_seen || endpoint_reset_n) $fatal(1,"manual hold missing");checks++;
        manual_reset=0;cycles(4);
        if(!endpoint_reset_n) $fatal(1,"release depended on stopped PCIe clock");checks++;
        // Physical assertion must work while the independent clock is stopped.
        monitor_enable=0;#30;pcie_reset_n=0;#2;
        if(endpoint_reset_n || perst_seen) $fatal(1,"PERST assertion not asynchronous");checks++;
        monitor_enable=1;cycles(3);pcie_reset_n=1;cycles(8);
        raw_async=64'h8000000000000f0f;ref_enable=1;axi_enable=1;cycles(160);
        if(raw_current!==raw_async || raw_ever_high!==raw_async ||
           !controls[3] || !controls[4] || !controls[5]) $fatal(1,"running observations invalid");checks++;
        arm();read_address=0;cycles(4);first_record=read_data;
        if(!metadata[91] || first_record[63:0]>metadata[63:0] || first_record[127:96]<6 || first_record[127:96]>10)
            $fatal(1,"event layout or indexed read invalid");checks++;
        old_epoch=metadata[79:64];
        // Saturate the short test RAM and preserve the first record.
        repeat(12) begin link_up=~link_up;cycles(8);end
        if(metadata[89:80]!=8 || !metadata[90] || metadata[127:96]==0)
            $fatal(1,"overflow was not explicit");
        read_address=0;cycles(3);if(read_data!==first_record) $fatal(1,"full recorder overwrote history");checks++;
        ref_before=clocks[31:0];manual_reset=1;cycles(40);
        if(endpoint_reset_n || clocks[31:0]<=ref_before || metadata[79:64]!=old_epoch)
            $fatal(1,"manual reset erased independent evidence");
        manual_reset=0;cycles(5);if(!endpoint_reset_n) $fatal(1,"manual recovery failed");checks++;
        arm();read_address=7;cycles(3);
        if(metadata[91] || metadata[79:64]!=old_epoch+1) $fatal(1,"stale indexed entry accepted");checks++;
        training_valid=1;
        repeat(8) begin training_snapshot[127:120]++;training_snapshot[101:96]=3;cycles(4);end
        if(!controls[24]) $fatal(1,"fresh training not recognized");checks++;
        axi_enable=0;ref_enable=0;cycles(100);
        if(controls[3] || controls[4] || controls[5] || controls[24] || !training_valid)
            $fatal(1,"stopped clocks/frozen snapshot looked live");checks++;
        // PERST starts a new epoch and parks periodic logging while asserted.
        old_epoch=metadata[79:64];pcie_reset_n=0;cycles(150);
        if(metadata[89:80]!=1 || metadata[79:64]!=old_epoch+1)
            $fatal(1,"PERST epoch or held-reset parking failed");checks++;
        pcie_reset_n=1;ref_enable=1;axi_enable=1;cycles(100);
        if(!endpoint_reset_n || !controls[3] || !controls[4] || !controls[5] || metadata[89:80]<2)
            $fatal(1,"new startup not captured");checks++;
        read_address=0;cycles(3);
        if(read_data[64] || !metadata[91]) $fatal(1,"assertion record missing");checks++;
        h=$fopen("simulation_pass.txt","w");$fdisplay(h,"PASS boot_diagnostics_checks=%0d",checks);$fclose(h);
        $display("PASS boot_diagnostics_checks=%0d",checks);$finish;
    end
    initial begin #100000;$fatal(1,"startup diagnostic timeout");end
endmodule
