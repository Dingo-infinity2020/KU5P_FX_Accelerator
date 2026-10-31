`timescale 1ns/1ps
// Late-capture regression for the unchanged e4 diagnostic RTL. Timestamp
// deposits are simulation-only acceleration, never a hardware clock/PLL control.
module tb_pcie_boot_provenance;
    reg monitor_clk=0,ref_div_clk=0,axi_clk=0;
    always #5 monitor_clk=~monitor_clk;
    always #40 ref_div_clk=~ref_div_clk;
    always #4 axi_clk=~axi_clk;
    reg [63:0] raw_async=64'h800000000000000f;
    reg perst_seen=1,manual_reset=0,endpoint_reset_n=1;
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
    reg [63:0] golden_time=0,expected_start,release_time;
    reg [255:0] first_word;
    reg [15:0] prior_epoch;
    integer checks=0,h,i;
    always @(posedge monitor_clk) golden_time<=golden_time+1'b1;
    task automatic cycles(input integer n);
        repeat(n) @(negedge monitor_clk);
    endtask
    task automatic arm_at(input reg [63:0] seed);
        begin
            @(negedge monitor_clk);
            // Set both the independent reference and DUT once; clocks then run.
            dut.timestamp=seed;golden_time=seed;expected_start=seed;
            prior_epoch=metadata[79:64];read_address=0;capture_arm=1;
            @(posedge monitor_clk);#1;
            if(metadata[79:64]!==prior_epoch+16'd1 || metadata[89:80]!==10'd1 || metadata[91])
                $fatal(1,"new capture must invalidate simultaneous RAM read");
            checks++;
            @(negedge monitor_clk);capture_arm=0;
            @(posedge monitor_clk);#1;
            if(!metadata[91] || read_data[63:0]!==seed || read_data[191:128]!==raw_async)
                $fatal(1,"fresh capture lost high timestamp bits or payload");
            checks++;first_word=read_data;
        end
    endtask
    task automatic fill;
        begin
            repeat(12) begin
                @(negedge monitor_clk);link_up=~link_up;cycles(7);
            end
            if(metadata[89:80]!=8 || !metadata[90] || metadata[127:96]==0)
                $fatal(1,"expected full recorder and explicit dropped events");
            checks++;
        end
    endtask
    initial begin
        cycles(100);
        arm_at(64'h12345678fffffff0);fill();
        read_address=0;cycles(3);
        if(read_data!==first_word || metadata[63:0]<64'h1234567900000000)
            $fatal(1,"32-bit carry or full-history retention failed");
        checks++;
        arm_at(64'h1234567900010000);
        @(negedge monitor_clk);read_address=7;
        @(posedge monitor_clk);#1;
        if(metadata[91]) $fatal(1,"old full-capture address accepted in new epoch");checks++;
        @(negedge monitor_clk);read_address=0;
        @(posedge monitor_clk);#1;
        if(!metadata[91] || read_data[63:0]!==expected_start)
            $fatal(1,"synchronous indexed-read latency/provenance failed");checks++;
        fill();
        // PERST after a full RAM must replace address0, including all64 bits.
        @(negedge monitor_clk);
        prior_epoch=metadata[79:64];expected_start=golden_time;
        perst_seen=0;endpoint_reset_n=0;read_address=0;
        @(posedge monitor_clk);#1;
        if(metadata[91] || metadata[79:64]!==prior_epoch+16'd1)
            $fatal(1,"PERST capture/read epoch transition invalid");checks++;
        cycles(4);
        if(!metadata[91] || read_data[63:0]!==expected_start || read_data[64])
            $fatal(1,"PERST first timestamp not fresh");checks++;
        first_word=read_data;cycles(150);
        if(metadata[89:80]!=1 || metadata[127:96]!=0 || read_data!==first_word)
            $fatal(1,"held PERST rewrote first record or periodic logging continued");checks++;
        @(negedge monitor_clk);release_time=golden_time;perst_seen=1;endpoint_reset_n=1;
        cycles(4);read_address=1;cycles(3);
        if(!metadata[91] || read_data[63:0]!==release_time || !read_data[64])
            $fatal(1,"PERST release record timestamp/control wrong");checks++;
        fill();
        h=$fopen("provenance_events_0.tsv","w");
        $fdisplay(h,"index\tepoch\tevent_hex\tmetadata_hex");
        for(i=0;i<8;i=i+1) begin
            @(negedge monitor_clk);read_address=i;
            @(posedge monitor_clk);#1;
            if(!metadata[91] || read_data[63:0]<expected_start || read_data[63:0]>golden_time)
                $fatal(1,"exported event outside capture/observation bound");
            $fdisplay(h,"%0d\t%0d\t%064h\t%032h",i,metadata[79:64],read_data,metadata);
        end
        $fclose(h);checks++;
        h=$fopen("expected_start.txt","w");$fdisplay(h,"%0d",expected_start);$fclose(h);
        h=$fopen("simulation_pass.txt","w");
        $fdisplay(h,"PASS boot_provenance_checks=%0d events=8",checks);$fclose(h);
        $display("PASS boot_provenance_checks=%0d events=8",checks);$finish;
    end
    initial begin #100000;$fatal(1,"provenance regression timeout");end
endmodule
