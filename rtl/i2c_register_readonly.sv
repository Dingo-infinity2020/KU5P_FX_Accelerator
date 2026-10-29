// Fixed-address random byte reads. No configuration-data write state exists.
// Wire sequence: S E0 A pointer A P, S E1 A data N P (7-bit address0x70).
module i2c_register_readonly #(
    parameter integer QUARTER_CYCLES=250,
    parameter integer TIMEOUT_CYCLES=200000
) (
    input wire clk,reset,start,
    input wire [7:0] register_address,
    input wire scl_i,sda_i,
    output reg scl_low=0,sda_low=0,busy=0,done=0,
    output reg [7:0] read_data=0,
    output reg [3:0] error_code=0,
    output wire [1:0] observed_lines,
    output wire [4:0] state_debug
);
    localparam integer W=$clog2(TIMEOUT_CYCLES+2*QUARTER_CYCLES+1);
    localparam [4:0] IDLE=0,FREE=1,START_HOLD=2,BIT_SETUP=3,BIT_LOW=4,
        BIT_RISE=5,BIT_SAMPLE=6,BIT_HIGH=7,ACK_SETUP=8,ACK_LOW=9,
        ACK_RISE=10,ACK_SAMPLE=11,ACK_HIGH=12,STOP_SETUP=13,
        STOP_LOW=14,STOP_RISE=15,STOP_HOLD=16,STOP_RELEASE=17;
    reg [4:0] state=IDLE;
    reg [W-1:0] delay_count=0,watchdog=0;
    reg [1:0] byte_index=0;
    reg [2:0] bit_index=7;
    reg [7:0] pointer=0,tx_byte=8'he0;
    (* ASYNC_REG="TRUE",SHREG_EXTRACT="NO" *) reg scl_meta=1,scl_sync=1,sda_meta=1,sda_sync=1;
    always @(posedge clk) begin
        scl_meta<=scl_i;scl_sync<=scl_meta;sda_meta<=sda_i;sda_sync<=sda_meta;
    end
    assign observed_lines={sda_sync,scl_sync};
    assign state_debug=state;
    always @(posedge clk) begin
        done<=0;
        if(reset) begin
            state<=IDLE;busy<=0;scl_low<=0;sda_low<=0;error_code<=0;
            delay_count<=0;watchdog<=0;read_data<=0;
        end else if(busy && watchdog==TIMEOUT_CYCLES-1) begin
            // Release both wires; never issue a bus-clear or clock-chip reset.
            state<=IDLE;busy<=0;done<=1;scl_low<=0;sda_low<=0;
            error_code<=(state==FREE)?4'd1:4'd5;
        end else begin
            if(busy) watchdog<=watchdog+1'b1;
            if(delay_count!=0) delay_count<=delay_count-1'b1;
            case(state)
                IDLE: if(start) begin
                    busy<=1;error_code<=0;read_data<=0;watchdog<=0;
                    pointer<=register_address;tx_byte<=8'he0;byte_index<=0;bit_index<=7;
                    scl_low<=0;sda_low<=0;delay_count<=2*QUARTER_CYCLES-1;state<=FREE;
                end
                FREE: if(!scl_sync || !sda_sync) delay_count<=2*QUARTER_CYCLES-1;
                    else if(delay_count==0) begin
                        sda_low<=1;delay_count<=2*QUARTER_CYCLES-1;state<=START_HOLD;
                    end
                START_HOLD: if(delay_count==0) begin
                    scl_low<=1;delay_count<=QUARTER_CYCLES-1;state<=BIT_SETUP;
                end
                BIT_SETUP: if(delay_count==0) begin
                    sda_low<=(byte_index==3)?1'b0:~tx_byte[bit_index];
                    delay_count<=QUARTER_CYCLES-1;state<=BIT_LOW;
                end
                BIT_LOW: if(delay_count==0) begin scl_low<=0;state<=BIT_RISE;end
                BIT_RISE: if(scl_sync) begin delay_count<=QUARTER_CYCLES-1;state<=BIT_SAMPLE;end
                BIT_SAMPLE: if(delay_count==0) begin
                    if(byte_index==3) read_data[bit_index]<=sda_sync;
                    if(byte_index!=3 && tx_byte[bit_index] && !sda_sync) begin
                        error_code<=6;state<=IDLE;busy<=0;done<=1;scl_low<=0;sda_low<=0;
                    end else begin delay_count<=QUARTER_CYCLES-1;state<=BIT_HIGH;end
                end
                BIT_HIGH: if(delay_count==0) begin
                    scl_low<=1;delay_count<=QUARTER_CYCLES-1;
                    if(bit_index==0) state<=ACK_SETUP;
                    else begin bit_index<=bit_index-1'b1;state<=BIT_SETUP;end
                end
                ACK_SETUP: if(delay_count==0) begin
                    sda_low<=0;delay_count<=QUARTER_CYCLES-1;state<=ACK_LOW;
                end
                ACK_LOW: if(delay_count==0) begin scl_low<=0;state<=ACK_RISE;end
                ACK_RISE: if(scl_sync) begin delay_count<=QUARTER_CYCLES-1;state<=ACK_SAMPLE;end
                ACK_SAMPLE: if(delay_count==0) begin
                    if(byte_index!=3 && sda_sync) error_code<=4'd2+byte_index;
                    delay_count<=QUARTER_CYCLES-1;state<=ACK_HIGH;
                end
                ACK_HIGH: if(delay_count==0) begin
                    scl_low<=1;delay_count<=QUARTER_CYCLES-1;
                    if(error_code!=0 || byte_index==1 || byte_index==3) state<=STOP_SETUP;
                    else begin
                        byte_index<=byte_index+1'b1;bit_index<=7;
                        tx_byte<=pointer;state<=BIT_SETUP;
                    end
                end
                STOP_SETUP: if(delay_count==0) begin
                    sda_low<=1;delay_count<=QUARTER_CYCLES-1;state<=STOP_LOW;
                end
                STOP_LOW: if(delay_count==0) begin scl_low<=0;state<=STOP_RISE;end
                STOP_RISE: if(scl_sync) begin delay_count<=QUARTER_CYCLES-1;state<=STOP_HOLD;end
                STOP_HOLD: if(delay_count==0) begin
                    sda_low<=0;delay_count<=2*QUARTER_CYCLES-1;state<=STOP_RELEASE;
                end
                STOP_RELEASE: if(delay_count==0) begin
                    if(byte_index==1 && error_code==0) begin
                        byte_index<=2;tx_byte<=8'he1;bit_index<=7;
                        delay_count<=2*QUARTER_CYCLES-1;state<=FREE;
                    end else begin state<=IDLE;busy<=0;done<=1;end
                end
                default: begin state<=IDLE;busy<=0;scl_low<=0;sda_low<=0;error_code<=7;end
            endcase
        end
    end
endmodule
