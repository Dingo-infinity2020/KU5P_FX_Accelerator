// FNIC-KU5P: fixed 100 MHz oscillator, VIO controls and ILA result capture.
// VIO reset/start are synchronous to this clock; power-on reset uses FF INIT.
module lesson05_board_top (
    input wire SYS_CLK,
    output wire LED1, LED2
);
    wire clock_input,clk;
    IBUF u_clock_input(.I(SYS_CLK),.O(clock_input));
    BUFG u_clock_buffer(.I(clock_input),.O(clk));
    reg [7:0] power_on=0;
    always @(posedge clk) power_on<={power_on[6:0],1'b1};
    wire control_reset,control_start;
    wire rst_n=power_on[7]&&!control_reset;
    wire result_valid,busy,done,error,core_clip,core_protocol_error;
    wire [649:0] result_payload;
    wire [31:0] input_count,result_count,run_cycles,signature;
    lesson05_replay replay(.*,.start(control_start));
    reg [26:0] heartbeat=0;
    always @(posedge clk) heartbeat<=heartbeat+1'b1;
    // Board LEDs are active low. LED1 blinks; LED2 lights only after clean completion.
    assign LED1=heartbeat[26];
    assign LED2=!(done&&!error);
    wire [7:0] debug_status={2'b00,power_on[7],core_protocol_error,core_clip,error,done,busy};
    lesson05_vio controls (
        .clk(clk),.probe_in0(debug_status),.probe_in1(input_count),.probe_in2(result_count),
        .probe_in3(signature),.probe_in4(run_cycles),.probe_in5(32'h46580501),
        .probe_out0(control_reset),.probe_out1(control_start)
    );
    (* keep="true" *) wire debug_valid=result_valid;
    (* keep="true" *) wire [393:0] debug_meta=result_payload[393:0];
    (* keep="true" *) wire [63:0] debug_auto_a=result_payload[649:586];
    (* keep="true" *) wire [63:0] debug_auto_b=result_payload[585:522];
    // BASIC permits five ILA probes: pack the complex cross product together.
    (* keep="true" *) wire [127:0] debug_cross=result_payload[521:394];
    lesson05_ila capture (
        .clk(clk),.probe0(debug_valid),.probe1(debug_meta),.probe2(debug_auto_a),
        .probe3(debug_auto_b),.probe4(debug_cross)
    );
endmodule
