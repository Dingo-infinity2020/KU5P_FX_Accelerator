// Read-only clock-chip inventory. CLK_SEL, address strap and INTR are inputs.
module lesson05f_si5338_top (
    input wire SYS_CLK,SI5338_INTR,SI5338_I2C_LSB,CLK_SEL,
    inout wire SI5338_SCL,SI5338_SDA,
    output wire LED1,LED2
);
    wire sys_input,clk,capture_clk;
    IBUF clock_input (.I(SYS_CLK),.O(sys_input));
    BUFG system_buffer (.I(sys_input),.O(clk));
    BUFGCE_DIV #(.BUFGCE_DIVIDE(8),.SIM_DEVICE("ULTRASCALE_PLUS")) capture_buffer (
        .I(sys_input),.CE(1'b1),.CLR(1'b0),.O(capture_clk));
    wire scl_i,sda_i,scl_low,sda_low,busy,done,manual_reset;
    IOBUF scl_buffer (.I(1'b0),.T(~scl_low),.O(scl_i),.IO(SI5338_SCL));
    IOBUF sda_buffer (.I(1'b0),.T(~sda_low),.O(sda_i),.IO(SI5338_SDA));
    (* ASYNC_REG="TRUE",SHREG_EXTRACT="NO" *) reg [2:0] strap_meta=0,strap_sync=0;
    reg [31:0] heartbeat=0;
    reg [15:0] completion_count=0;
    wire [8:0] command;
    reg seen_toggle=0,start=0;
    reg [7:0] last_register=0;
    wire [7:0] read_data;
    wire [3:0] error_code;
    wire [1:0] observed_lines;
    wire [4:0] phase;
    always @(posedge clk) begin
        heartbeat<=heartbeat+1'b1;
        strap_meta<={CLK_SEL,SI5338_I2C_LSB,SI5338_INTR};strap_sync<=strap_meta;
        start<=0;
        if(manual_reset) seen_toggle<=command[0];
        else if(!busy && command[0]!=seen_toggle) begin
            seen_toggle<=command[0];last_register<=command[8:1];start<=1;
        end
        if(done) completion_count<=completion_count+1'b1;
    end
    i2c_register_readonly reader (.clk(clk),.reset(manual_reset),.start(start),
        .register_address(last_register),.scl_i(scl_i),.sda_i(sda_i),
        .scl_low(scl_low),.sda_low(sda_low),.busy(busy),.done(done),
        .read_data(read_data),.error_code(error_code),.observed_lines(observed_lines),.state_debug(phase));
    wire [7:0] status={seen_toggle,manual_reset,sda_low,scl_low,observed_lines,done,busy};
    wire [63:0] result={5'b0,strap_sync,3'b0,phase,completion_count,4'b0,error_code,status,last_register,read_data};
    lesson05f_si5338_vio monitor (.clk(clk),.probe_in0(32'h465805f1),.probe_in1(result),
        .probe_in2(heartbeat),.probe_out0(command),.probe_out1(manual_reset));
    wire [7:0] diagnostics={heartbeat[7],2'b0,busy,sda_low,scl_low,observed_lines};
    lesson05f_si5338_ila capture (.clk(capture_clk),.probe0(diagnostics),.probe1(busy));
    assign LED1=heartbeat[25];
    assign LED2=(error_code!=0);
endmodule
