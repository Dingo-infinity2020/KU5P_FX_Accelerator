// Independent-clock startup evidence. It never clears on endpoint reset.
// raw_async[59:0]/[63] are tied low in RTL; synthesis adds read-only GT
// observer loads and a valid bit. That hookup is audited, not RTL-simulated.
module pcie_boot_diagnostics #(
    parameter integer WINDOW_CYCLES=1000000,
    parameter integer ACTIVE_TIMEOUT=4096,
    parameter integer ADDR_WIDTH=9,
    parameter integer REF_MIN=117187,
    parameter integer REF_MAX=132813
) (
    input wire monitor_clk,ref_div_clk,axi_clk,
    input wire [63:0] raw_async,
    input wire perst_seen,manual_reset,endpoint_reset_n,
    input wire qualifier_locked,qualifier_stopped,link_up,axi_reset_n,
    input wire [127:0] training_snapshot,
    input wire training_valid,capture_arm,
    input wire [ADDR_WIDTH-1:0] read_address,
    output wire [63:0] raw_current,
    output reg [63:0] raw_ever_high=0,raw_ever_low=0,
    output wire [127:0] clocks,
    output wire [127:0] metadata,
    output reg [255:0] read_data=0,
    output wire [31:0] controls
);
    localparam integer DEPTH=1<<ADDR_WIDTH;
    // Each bit is an independent status level, not a coherent encoded bus.
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO", DONT_TOUCH="TRUE" *)
    reg [63:0] raw_meta=0,raw_sync=0;
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *)
    reg [3:0] auxiliary_meta=0,auxiliary_sync=0;
    reg [4:0] warmup=0;
    always @(posedge monitor_clk) begin
        raw_meta<=raw_async;raw_sync<=raw_meta;
        auxiliary_meta<={axi_reset_n,link_up,qualifier_stopped,qualifier_locked};
        auxiliary_sync<=auxiliary_meta;
        warmup<={warmup[3:0],1'b1};
        if(warmup[4] && raw_sync[63]) begin
            raw_ever_high<=raw_ever_high|raw_sync;
            raw_ever_low<=raw_ever_low|~raw_sync;
        end
    end
    assign raw_current=raw_sync;
    reg [31:0] ref_binary=0,axi_binary=0;
    reg [2:0] axi_prescaler=0;
    always @(posedge ref_div_clk) ref_binary<=ref_binary+1'b1;
    // Keep every Gray input value stable for >=8 AXI cycles. This satisfies
    // the destination sampling contract even with a 125/250 MHz user clock.
    always @(posedge axi_clk) begin
        axi_prescaler<=axi_prescaler+1'b1;
        if(&axi_prescaler) axi_binary<=axi_binary+1'b1;
    end
    wire [31:0] ref_count,axi_count;
    xpm_cdc_gray #(.DEST_SYNC_FF(4),.INIT_SYNC_FF(1),.REG_OUTPUT(1),
        .SIM_ASSERT_CHK(1),.SIM_LOSSLESS_GRAY_CHK(0),.WIDTH(32)) ref_cdc (
        .src_clk(ref_div_clk),.src_in_bin(ref_binary),
        .dest_clk(monitor_clk),.dest_out_bin(ref_count));
    xpm_cdc_gray #(.DEST_SYNC_FF(4),.INIT_SYNC_FF(1),.REG_OUTPUT(1),
        .SIM_ASSERT_CHK(1),.SIM_LOSSLESS_GRAY_CHK(0),.WIDTH(32)) axi_cdc (
        .src_clk(axi_clk),.src_in_bin(axi_binary),
        .dest_clk(monitor_clk),.dest_out_bin(axi_count));
    reg [31:0] previous_ref=0,previous_axi=0,window_ref=0;
    reg [31:0] ref_idle=ACTIVE_TIMEOUT,axi_idle=ACTIVE_TIMEOUT;
    reg [31:0] window_count=0,window_delta=0,window_sequence=0;
    reg window_tick=0,window_good=0;
    always @(posedge monitor_clk) begin
        previous_ref<=ref_count;previous_axi<=axi_count;window_tick<=0;
        if(ref_count!=previous_ref) ref_idle<=0;
        else if(ref_idle<ACTIVE_TIMEOUT) ref_idle<=ref_idle+1'b1;
        if(axi_count!=previous_axi) axi_idle<=0;
        else if(axi_idle<ACTIVE_TIMEOUT) axi_idle<=axi_idle+1'b1;
        if(!warmup[4]) begin
            window_count<=0;window_ref<=ref_count;
        end else if(window_count==WINDOW_CYCLES-1) begin
            window_delta<=ref_count-window_ref;window_ref<=ref_count;
            window_good<=((ref_count-window_ref)>=REF_MIN && (ref_count-window_ref)<=REF_MAX);
            window_count<=0;window_tick<=1;window_sequence<=window_sequence+1'b1;
        end else window_count<=window_count+1'b1;
    end
    reg [7:0] previous_sequence=0;
    reg [31:0] training_idle=ACTIVE_TIMEOUT;
    always @(posedge monitor_clk) begin
        previous_sequence<=training_snapshot[127:120];
        if(training_valid && training_snapshot[127:120]!=previous_sequence) training_idle<=0;
        else if(training_idle<ACTIVE_TIMEOUT) training_idle<=training_idle+1'b1;
    end
    wire training_recent=training_valid && training_idle<ACTIVE_TIMEOUT;
    reg [63:0] timestamp=0;
    always @(posedge monitor_clk) timestamp<=timestamp+1'b1;
    // Heartbeat is for ILA sample-spacing validation only, excluded from events.
    assign controls={timestamp[7],5'b0,(&raw_sync[3:0]),training_recent,
        training_snapshot[101:96],raw_sync[63],auxiliary_sync[3:2],
        raw_sync[62:60],(&raw_sync[15:12]),(&raw_sync[11:8]),
        raw_sync[56],(|raw_sync[7:4]),auxiliary_sync[1:0],
        (axi_idle<ACTIVE_TIMEOUT),window_good,(ref_idle<ACTIVE_TIMEOUT),
        endpoint_reset_n,manual_reset,perst_seen};
    wire [31:0] event_controls={1'b0,controls[30:0]};
    reg [31:0] previous_controls=0;
    reg previous_arm=0,previous_perst=0;
    reg [15:0] epoch=0;
    reg [ADDR_WIDTH:0] entries=0;
    reg [31:0] dropped_events=0;
    (* ram_style="block" *) reg [255:0] events[0:DEPTH-1];
    wire new_capture=(capture_arm && !previous_arm) || (previous_perst && !perst_seen);
    wire record_event=warmup[4] && perst_seen &&
        (event_controls!=previous_controls || window_tick);
    wire [255:0] record={axi_count,ref_count,raw_sync,window_delta,event_controls,timestamp};
    wire event_write=new_capture || (record_event && entries<DEPTH);
    wire [ADDR_WIDTH-1:0] event_write_address=new_capture ? {ADDR_WIDTH{1'b0}} : entries[ADDR_WIDTH-1:0];
    reg read_valid=0;
    // Exactly one write port and one synchronous read port infer block RAM.
    always @(posedge monitor_clk) if(event_write) events[event_write_address]<=record;
    always @(posedge monitor_clk) begin
        previous_arm<=capture_arm;previous_perst<=perst_seen;
        previous_controls<=event_controls;
        // Count and read validity qualify RAM bytes; never clear the RAM array.
        read_data<=events[read_address];
        read_valid<=({1'b0,read_address}<entries) && !new_capture;
        if(new_capture) begin
            epoch<=epoch+1'b1;entries<=1;dropped_events<=0;
        end else if(record_event) begin
            if(entries<DEPTH) begin
                entries<=entries+1'b1;
            end else if(!(&dropped_events)) dropped_events<=dropped_events+1'b1;
        end
    end
    assign clocks={window_sequence,window_delta,axi_count,ref_count};
    assign metadata={dropped_events,endpoint_reset_n,manual_reset,training_recent,
        training_valid,read_valid,(entries==DEPTH),{{(10-(ADDR_WIDTH+1)){1'b0}},entries},epoch,timestamp};
endmodule

// Physical PERSTn asserts asynchronously. Local requests are registered in
// SYS_CLK before entering the vendor's asynchronous reset synchronizers.
module pcie_boot_reset_bridge (
    input wire monitor_clk,pcie_reset_n,manual_reset,
    output wire perst_seen,
    output wire endpoint_reset_n
);
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) reg [2:0] perst_pipe=0;
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) reg [1:0] endpoint_pipe=0;
    always @(posedge monitor_clk or negedge pcie_reset_n) begin
        if(!pcie_reset_n) begin perst_pipe<=0;endpoint_pipe<=0;end
        else begin
            perst_pipe<={perst_pipe[1:0],1'b1};
            endpoint_pipe<={endpoint_pipe[0],(perst_pipe[2] && !manual_reset)};
        end
    end
    assign perst_seen=perst_pipe[2];
    assign endpoint_reset_n=endpoint_pipe[1];
endmodule
