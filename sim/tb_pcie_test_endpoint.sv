`timescale 1ns/1ps
module tb_pcie_test_endpoint;
    reg clk=0;always #2 clk=~clk;
    reg rst_n=0,link_up=1;
    reg [31:0] s_axil_awaddr=0,s_axil_wdata=0,s_axil_araddr=0;
    reg [3:0] s_axil_wstrb=0;
    reg s_axil_awvalid=0,s_axil_wvalid=0,s_axil_bready=0,s_axil_arvalid=0,s_axil_rready=0;
    wire s_axil_awready,s_axil_wready,s_axil_bvalid,s_axil_arready,s_axil_rvalid;
    wire [1:0] s_axil_bresp,s_axil_rresp;wire [31:0] s_axil_rdata;
    wire [255:0] c2h_data;wire [31:0] c2h_keep;wire c2h_valid,c2h_last;
    reg c2h_ready=0,h2c_valid=0,h2c_last=0;reg [31:0] h2c_keep=0;wire h2c_ready;
    wire busy,done;wire [31:0] accepted_beats,completed_packets,signature;
    pcie_test_endpoint dut(.*);
    reg [255:0] expected [0:3711];reg checking=0;integer checked=0,stalls=0,burst=0,max_burst=0;
    integer mode=0,write_errors=0,read_errors=0,aw_first=0,w_first=0;
    reg [31:0] rng=32'h9234abcd;
    reg stream_stalled=0,b_stalled=0,r_stalled=0;
    reg [288:0] held_stream;reg [1:0] held_b;reg [33:0] held_r;
    integer capture_file;
    always @(negedge clk) begin
        rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
        c2h_ready=mode==1 ? 1'b1 : mode==2 ? 1'b0 : rng[0]|rng[2];
    end
    always @(posedge clk) begin
        if(!rst_n) begin stream_stalled=0;b_stalled=0;r_stalled=0;burst=0;end
        else begin
            if(stream_stalled && (!c2h_valid || {c2h_last,c2h_keep,c2h_data}!==held_stream)) $fatal(1,"C2H changed while stalled");
            if(b_stalled && (!s_axil_bvalid || s_axil_bresp!==held_b)) $fatal(1,"Write response changed");
            if(r_stalled && (!s_axil_rvalid || {s_axil_rresp,s_axil_rdata}!==held_r)) $fatal(1,"Read response changed");
            stream_stalled=c2h_valid&&!c2h_ready;held_stream={c2h_last,c2h_keep,c2h_data};
            b_stalled=s_axil_bvalid&&!s_axil_bready;held_b=s_axil_bresp;
            r_stalled=s_axil_rvalid&&!s_axil_rready;held_r={s_axil_rresp,s_axil_rdata};
            if(checking && stream_stalled) stalls=stalls+1;
            if(checking && c2h_valid && c2h_ready) begin
                if(checked>=3712 || c2h_data!==expected[checked] || c2h_keep!==32'hffffffff || c2h_last!==(checked%128==127))
                    $fatal(1,"C2H mismatch beat=%0d",checked);
                $fdisplay(capture_file,"%064h",c2h_data);checked=checked+1;burst=burst+1;
                if(burst>max_burst) max_burst=burst;
            end else burst=0;
        end
    end
    task reset_endpoint;
        begin
            @(negedge clk);rst_n=0;s_axil_awvalid=0;s_axil_wvalid=0;s_axil_arvalid=0;
            s_axil_bready=0;s_axil_rready=0;h2c_valid=0;
            repeat(6) @(negedge clk);rst_n=1;
        end
    endtask
    task write_reg(input reg [31:0] address,data,input reg [3:0] strobes,input integer order,input reg [1:0] response=0);
        begin
            fork
                begin
                    if(order==1) begin repeat(4) @(negedge clk);w_first=w_first+1;end
                    @(negedge clk);s_axil_awaddr=address;s_axil_awvalid=1;
                    @(posedge clk);while(!s_axil_awready) @(posedge clk);
                    @(negedge clk);s_axil_awvalid=0;
                end
                begin
                    if(order==0) begin repeat(4) @(negedge clk);aw_first=aw_first+1;end
                    @(negedge clk);s_axil_wdata=data;s_axil_wstrb=strobes;s_axil_wvalid=1;
                    @(posedge clk);while(!s_axil_wready) @(posedge clk);
                    @(negedge clk);s_axil_wvalid=0;
                end
            join
            while(!s_axil_bvalid) @(negedge clk);
            repeat(5) @(negedge clk);
            if(s_axil_bresp!==response) $fatal(1,"Write response address=%h",address);
            if(response!=0) write_errors=write_errors+1;
            s_axil_bready=1;@(posedge clk);@(negedge clk);s_axil_bready=0;
        end
    endtask
    task read_reg(input reg [31:0] address,expected_data,input reg [1:0] response=0);
        begin
            @(negedge clk);s_axil_araddr=address;s_axil_arvalid=1;
            @(posedge clk);while(!s_axil_arready) @(posedge clk);
            @(negedge clk);s_axil_arvalid=0;
            while(!s_axil_rvalid) @(negedge clk);
            repeat(4) @(negedge clk);
            if(s_axil_rresp!==response || s_axil_rdata!==expected_data) $fatal(1,"Read address=%h got=%h expected=%h",address,s_axil_rdata,expected_data);
            if(response!=0) read_errors=read_errors+1;
            s_axil_rready=1;@(posedge clk);@(negedge clk);s_axil_rready=0;
        end
    endtask
    integer case_file,scan,case_id,packets,i,target,pass_file;
    reg [31:0] rid,salt,expected_signature;
    initial begin
        $readmemh("expected.mem",expected);capture_file=$fopen("captured.mem","w");
        reset_endpoint();read_reg(0,32'h35445846);read_reg(4,1);
        // Reset a stream mid-packet and with an unmatched AXI write address.
        mode=1;write_reg(8,1,15,0);while(accepted_beats<13) @(negedge clk);
        mode=2;@(negedge clk);s_axil_awvalid=1;s_axil_awaddr=16;
        @(posedge clk);@(negedge clk);s_axil_awvalid=0;reset_endpoint();
        read_reg(12,16);read_reg(16,2);
        write_reg(16,0,15,1);write_reg(8,1,15,0,2); // zero packets rejected
        write_reg(16,4097,15,0);write_reg(8,1,15,1,2);
        write_reg(0,0,15,0,2);write_reg(17,2,15,1,2);read_reg(1,0,2);read_reg(4096,0,2);
        write_reg(24,32'hdeadbeef,5,1);read_reg(24,32'h10ad30ef);
        // Byte enables on H2C are counted; the channel is a sink, not loopback.
        for(i=0;i<5;i=i+1) begin
            @(negedge clk);h2c_valid=1;h2c_keep=32'h0000ffff;h2c_last=(i==4);
        end
        @(negedge clk);h2c_valid=0;read_reg(40,5);read_reg(44,1);read_reg(60,80);
        case_file=$fopen("cases.txt","r");checking=1;
        while(!$feof(case_file)) begin
            scan=$fscanf(case_file,"%d %d %h %h %h\n",case_id,packets,rid,salt,expected_signature);
            if(scan==5) begin
                write_reg(16,packets,15,case_id%2);write_reg(20,rid,15,1);write_reg(24,salt,15,0);
                mode=2;write_reg(8,1,15,1);
                // Future configuration changes must not alter the active run.
                write_reg(20,32'h11223344,15,0);write_reg(24,32'h55667788,15,1);
                write_reg(8,1,15,0,2);write_reg(8,2,15,1,2);
                target=checked+packets*128;mode=(case_id==1 || case_id==3) ? 1 : 0;
                while(!done) @(negedge clk);
                if(checked!=target || accepted_beats!=packets*128 || completed_packets!=packets || signature!==expected_signature)
                    $fatal(1,"Run counters or signature case=%0d",case_id);
                read_reg(12,18);read_reg(28,packets*128);read_reg(32,packets);read_reg(36,expected_signature);
                write_reg(8,2,15,0);read_reg(12,16);
            end else if(!$feof(case_file)) $fatal(1,"Invalid case row");
        end
        repeat(20) @(negedge clk);
        if(checked!=3712 || stalls==0 || max_burst<256 || aw_first==0 || w_first==0 || write_errors!=12 || read_errors!=2)
            $fatal(1,"Incomplete coverage %0d/%0d/%0d/%0d/%0d",checked,stalls,max_burst,write_errors,read_errors);
        $fclose(capture_file);pass_file=$fopen("simulation_pass.txt","w");
        $fdisplay(pass_file,"PASS packets=29 beats=%0d stalls=%0d max_burst=%0d write_errors=%0d read_errors=%0d aw_first=%0d w_first=%0d",checked,stalls,max_burst,write_errors,read_errors,aw_first,w_first);
        $fclose(pass_file);$display("PASS PCIe application beats=%0d",checked);$finish;
    end
    initial begin #1000000;$fatal(1,"Application timeout");end
endmodule
