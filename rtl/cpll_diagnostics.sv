// Read-only monitor in the independent SYS_CLK domain. Event/history state
// survives manual GT resets and starts again only at FPGA configuration.
module cpll_diagnostics (
    input wire monitor_clk,
    input wire [7:0] asynchronous_flags,
    input wire [2:0] control_observe,
    input wire manual_reset,reset_all,ref_qualified,pcie_reset_n,
    input wire [31:0] ref_counter,
    input wire [31:0] heartbeat,
    output wire [95:0] observation,
    output wire [127:0] event_counters
);
    // RTL and simulation tie these inputs low. The native hardware build adds
    // ONLY read-only loads to primitive CPLLRESET/CPLLPD after synthesis and
    // sets bit2 valid. Their actual-control observation is not RTL-simulated.
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO", DONT_TOUCH="TRUE" *)
    reg [2:0] control_meta=0,control_sync=0;
    always @(posedge monitor_clk) begin
        control_meta<=control_observe;
        control_sync<=control_meta;
    end

    reg [31:0] previous_ref=0;
    reg [11:0] ref_idle=12'hfff;
    reg previous_reset_all=1;
    reg [7:0] initialization_releases=0;
    always @(posedge monitor_clk) begin
        previous_ref<=ref_counter;
        if(!ref_qualified) ref_idle<=12'hfff;
        else if(ref_counter!=previous_ref) ref_idle<=0;
        else if(!(&ref_idle)) ref_idle<=ref_idle+1'b1;
        previous_reset_all<=reset_all;
        if(previous_reset_all && !reset_all && !(&initialization_releases))
            initialization_releases<=initialization_releases+1'b1;
    end
    wire ref_active_recent=ref_qualified && !(&ref_idle);
    wire [31:0] flags={initialization_releases,7'b0,control_sync[2],
        heartbeat[7],pcie_reset_n,ref_active_recent,ref_qualified,
        reset_all,manual_reset,control_sync[1:0],asynchronous_flags};
    pcie_phy_monitor #(.WIDTH(32)) flag_monitor (
        .monitor_clk(monitor_clk),.flags_async(flags),.observation(observation));

    wire [31:0] current=observation[31:0];
    reg previous_lock=0,previous_txdone=0;
    reg [2:0] event_warmup=0;
    reg [31:0] lock_rise=0,lock_fall=0,txdone_rise=0,txdone_fall=0;
    always @(posedge monitor_clk) begin
        event_warmup<={event_warmup[1:0],1'b1};
        previous_lock<=current[1];previous_txdone<=current[4];
        if(event_warmup[2]) begin
            if(current[1] && !previous_lock && !(&lock_rise)) lock_rise<=lock_rise+1'b1;
            if(!current[1] && previous_lock && !(&lock_fall)) lock_fall<=lock_fall+1'b1;
            if(current[4] && !previous_txdone && !(&txdone_rise)) txdone_rise<=txdone_rise+1'b1;
            if(!current[4] && previous_txdone && !(&txdone_fall)) txdone_fall<=txdone_fall+1'b1;
        end
    end
    assign event_counters={txdone_fall,txdone_rise,lock_fall,lock_rise};
endmodule
