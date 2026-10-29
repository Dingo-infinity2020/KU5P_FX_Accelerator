`timescale 1ns/1ps
module tb_i2c_register_readonly;
    reg clk=0,reset=0,start=0;
    always #5 clk=~clk;
    reg [7:0] register_address=0;
    tri1 scl,sda;
    wire scl_low,sda_low,busy,done;
    wire [7:0] read_data;
    wire [3:0] error_code;
    wire [1:0] observed_lines;
    wire [4:0] state_debug;
    reg slave_sda_low=0,slave_scl_low=0,fault_sda_low=0;
    reg slave_enable=1,stretch=0,long_stretch=0;
    integer nack_stage=0,completed=0,checks=0,stop_edges=0;
    assign scl=(scl_low || slave_scl_low)?1'b0:1'bz;
    assign sda=(sda_low || slave_sda_low || fault_sda_low)?1'b0:1'bz;
    i2c_register_readonly dut (.scl_i(scl),.sda_i(sda),.*);
    task automatic wait_start;
        begin: waiting
            forever begin @(negedge sda);if(scl===1'b1) disable waiting;end
        end
    endtask
    task automatic wait_stop;
        begin: waiting
            stop_edges=0;
            fork: stop_monitor
                begin
                    forever begin @(posedge scl);stop_edges++;if(stop_edges>1) $fatal(1,"Unexpected configuration-data clocks after pointer/ACK");end
                end
                begin
                    forever begin @(posedge sda);if(scl===1'b1) disable waiting;end
                end
            join
        end
    endtask
    task automatic receive_byte(output reg [7:0] value);
        begin for(integer bitn=7;bitn>=0;bitn--) begin @(posedge scl);value[bitn]=sda;end end
    endtask
    task automatic send_ack(input bit accept,input bit first);
        begin
            @(negedge scl);slave_sda_low=accept;
            if(first && (stretch || long_stretch)) begin
                slave_scl_low=1;
                if(long_stretch) #2200000;else #20000;
                slave_scl_low=0;
            end
            @(posedge scl);@(negedge scl);slave_sda_low=0;
        end
    endtask
    initial forever begin: slave
        reg [7:0] address,pointer,value;
        wait_start();
        if(slave_enable) begin
            receive_byte(address);if(address!==8'he0) $fatal(1,"Unexpected device write address %02x",address);
            send_ack(nack_stage!=1,1);
            if(nack_stage==1) wait_stop();else begin
                receive_byte(pointer);send_ack(nack_stage!=2,0);wait_stop();
                if(nack_stage!=2) begin
                    wait_start();receive_byte(address);
                    if(address!==8'he1) $fatal(1,"Unexpected device read address %02x",address);
                    send_ack(nack_stage!=3,0);
                    if(nack_stage==3) wait_stop();else begin
                        value=pointer^8'ha5;
                        for(integer bitn=7;bitn>=0;bitn--) begin
                            slave_sda_low=~value[bitn];@(posedge scl);@(negedge scl);
                        end
                        slave_sda_low=0;@(posedge scl);
                        if(sda!==1'b1) $fatal(1,"Master must NACK the only read byte");
                        @(negedge scl);wait_stop();
                    end
                end
            end
            completed++;
        end
    end
    task automatic request(input [7:0] address,input [3:0] expected_error);
        integer cycles;
        begin
            @(negedge clk);register_address=address;start=1;
            @(negedge clk);start=0;cycles=0;
            while(!done && cycles<250000) begin @(negedge clk);cycles++;end
            if(!done || busy || error_code!==expected_error) $fatal(1,"Bad completion err=%d expected=%d state=%d",error_code,expected_error,state_debug);
            if(expected_error==0 && read_data!==(address^8'ha5)) $fatal(1,"Bad register read %02x",read_data);
            if(scl_low || sda_low) $fatal(1,"Master did not release bus");
            repeat(1000) @(negedge clk);checks++;
        end
    endtask
    integer h;
    initial begin
        repeat(20) @(negedge clk);
        request(8'h00,0);request(8'hff,0);stretch=1;request(8'hda,0);stretch=0;
        nack_stage=1;request(8'h02,2);nack_stage=2;request(8'h1b,3);nack_stage=3;request(8'he6,4);nack_stage=0;
        slave_enable=0;fault_sda_low=1;request(8'h00,1);fault_sda_low=0;slave_enable=1;
        request(8'h03,0); // a failed busy transaction must not wedge the master
        slave_enable=0;
        fork
            request(8'h00,6);
            begin @(negedge scl);@(posedge scl);fault_sda_low=1;wait(done);fault_sda_low=0;end
        join
        slave_enable=1;long_stretch=1;request(8'h00,5);
        h=$fopen("simulation_pass.txt","w");$fdisplay(h,"PASS i2c_readonly_checks=%0d",checks);$fclose(h);
        $display("PASS i2c_readonly_checks=%0d completed_slave_transactions=%0d",checks,completed);$finish;
    end
    initial begin #20000000;$fatal(1,"I2C test timeout");end
endmodule
