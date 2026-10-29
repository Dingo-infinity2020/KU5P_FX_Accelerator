`timescale 1ns/1ps

module tb_two_channel_correlator;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg [31:0] cfg_window_samples = 0;
    reg s_axis_tvalid = 0;
    wire s_axis_tready;
    reg signed [15:0] s_axis_a_i = 0, s_axis_a_q = 0;
    reg signed [15:0] s_axis_b_i = 0, s_axis_b_q = 0;
    wire m_axis_tvalid;
    reg m_axis_tready = 0;
    wire [63:0] m_axis_auto_a, m_axis_auto_b;
    wire signed [63:0] m_axis_cross_real, m_axis_cross_imag;
    wire [31:0] m_axis_sample_count;

    two_channel_correlator dut (.*);

    reg [63:0] expected_a [0:511], expected_b [0:511];
    reg signed [63:0] expected_real [0:511], expected_imag [0:511];
    reg [31:0] expected_counts [0:511];
    integer expected_head = 0, expected_tail = 0;
    integer checked_windows = 0, accepted_pairs = 0, stalled_cycles = 0;
    integer consecutive_inputs = 0, max_consecutive_inputs = 0;
    integer simultaneous_transfers = 0, pipeline_stall_cycles = 0;
    integer ready_mode = 0;
    reg [31:0] ready_rng = 32'h23abcd45, input_rng = 32'h9876abcd;
    reg was_stalled = 0;
    reg [287:0] held_result;
    reg [321:0] held_pipeline;

    always @(negedge clk) begin
        ready_rng = {ready_rng[30:0], ready_rng[31] ^ ready_rng[21]
                    ^ ready_rng[1] ^ ready_rng[0]};
        case (ready_mode)
            1: m_axis_tready = 0;
            2: m_axis_tready = 1;
            default: m_axis_tready = ready_rng[0] | ready_rng[3];
        endcase
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            // Reset cancels partial windows, products in flight and held output.
            expected_head = expected_tail;
            was_stalled = 0;
            consecutive_inputs = 0;
        end else begin
            if (was_stalled) begin
                if (!m_axis_tvalid || {m_axis_auto_a, m_axis_auto_b, m_axis_cross_real,
                                      m_axis_cross_imag, m_axis_sample_count} !== held_result)
                    $fatal(1, "Output changed under backpressure");
                if ({dut.product_valid, dut.product_last, dut.product_count,
                     dut.aa_ii, dut.aa_qq, dut.bb_ii, dut.bb_qq,
                     dut.ab_ii, dut.ab_qq, dut.ab_qi, dut.ab_iq,
                     dut.samples_accepted} !== held_pipeline)
                    $fatal(1, "Pipeline changed while output was blocked");
            end
            was_stalled = m_axis_tvalid && !m_axis_tready;
            held_result = {m_axis_auto_a, m_axis_auto_b, m_axis_cross_real,
                           m_axis_cross_imag, m_axis_sample_count};
            held_pipeline = {dut.product_valid, dut.product_last, dut.product_count,
                             dut.aa_ii, dut.aa_qq, dut.bb_ii, dut.bb_qq,
                             dut.ab_ii, dut.ab_qq, dut.ab_qi, dut.ab_iq,
                             dut.samples_accepted};
            if (was_stalled) begin
                stalled_cycles = stalled_cycles + 1;
                if (s_axis_tready) $fatal(1, "Blocked output still accepted input");
                if (dut.product_valid) pipeline_stall_cycles = pipeline_stall_cycles + 1;
            end
            if (s_axis_tvalid && s_axis_tready) begin
                accepted_pairs = accepted_pairs + 1;
                consecutive_inputs = consecutive_inputs + 1;
                if (consecutive_inputs > max_consecutive_inputs)
                    max_consecutive_inputs = consecutive_inputs;
            end else consecutive_inputs = 0;

            if (m_axis_tvalid && m_axis_tready) begin
                if (s_axis_tvalid && s_axis_tready)
                    simultaneous_transfers = simultaneous_transfers + 1;
                if (expected_head == expected_tail)
                    $fatal(1, "Unexpected output (duplicate, stale state or bad window)");
                if (m_axis_auto_a !== expected_a[expected_head]
                    || m_axis_auto_b !== expected_b[expected_head]
                    || m_axis_cross_real !== expected_real[expected_head]
                    || m_axis_cross_imag !== expected_imag[expected_head]
                    || m_axis_sample_count !== expected_counts[expected_head])
                    $fatal(1, "Window %0d: got (%0d,%0d,%0d,%0d,%0d), expected (%0d,%0d,%0d,%0d,%0d)",
                           checked_windows, m_axis_auto_a, m_axis_auto_b,
                           m_axis_cross_real, m_axis_cross_imag, m_axis_sample_count,
                           expected_a[expected_head], expected_b[expected_head],
                           expected_real[expected_head], expected_imag[expected_head],
                           expected_counts[expected_head]);
                expected_head = expected_head + 1;
                checked_windows = checked_windows + 1;
            end
        end
    end

    task expect_window(input reg [63:0] pa, input reg [63:0] pb,
                       input reg signed [63:0] vr, input reg signed [63:0] vi,
                       input reg [31:0] count);
        begin
            if (expected_tail >= 512) $fatal(1, "Expected-result ledger overflow");
            expected_a[expected_tail] = pa;
            expected_b[expected_tail] = pb;
            expected_real[expected_tail] = vr;
            expected_imag[expected_tail] = vi;
            expected_counts[expected_tail] = count;
            expected_tail = expected_tail + 1;
        end
    endtask

    task send_pair(input integer ai, input integer aq, input integer bi, input integer bq,
                   input reg change_config = 0, input reg [31:0] new_config = 0);
        begin
            @(negedge clk);
            if (change_config) cfg_window_samples = new_config;
            s_axis_a_i = ai; s_axis_a_q = aq;
            s_axis_b_i = bi; s_axis_b_q = bq;
            s_axis_tvalid = 1;
            @(posedge clk);
            while (!s_axis_tready) @(posedge clk);
        end
    endtask

    task idle_input;
        begin
            @(negedge clk);
            s_axis_tvalid = 0;
        end
    endtask

    task reset_core;
        begin
            @(negedge clk);
            rst_n = 0;
            s_axis_tvalid = 0;
            repeat (3) @(negedge clk);
            rst_n = 1;
        end
    endtask

    task drain_results;
        begin
            idle_input();
            ready_mode = 2;
            while (expected_head != expected_tail) @(negedge clk);
            repeat (4) @(negedge clk);
        end
    endtask

    integer vector_file, scan_status, window_size, sample_index, gap_index;
    integer ai, aq, bi, bq, windows_from_file = 0, pass_file, index;
    reg [63:0] pa, pb;
    reg signed [63:0] vr, vi;
    reg [31:0] mutation;

    initial begin
        reset_core();
        ready_mode = 2;
        @(negedge clk);
        cfg_window_samples = 0;
        s_axis_tvalid = 1;
        repeat (8) begin
            @(posedge clk);
            if (s_axis_tready || m_axis_tvalid) $fatal(1, "Zero target accepted");
        end
        idle_input();

        // Reset after some accumulation but before the end of a window.
        cfg_window_samples = 10;
        send_pair(30000, -30000, -32768, 32767);
        send_pair(-32768, -32768, 1234, -5678);
        send_pair(1234, -5678, 30000, 0);
        idle_input();
        repeat (2) @(negedge clk);
        reset_core();

        // Reset between multiplication and accumulation of an M=1 window.
        cfg_window_samples = 1;
        expect_window(5, 25, 2, -11, 1);
        send_pair(2, -1, 3, 4);
        reset_core();
        repeat (3) @(negedge clk);
        if (m_axis_tvalid || dut.product_valid) $fatal(1, "In-flight product survived reset");

        // Hold output A while B is already in the product register. Releasing
        // backpressure must deliver BOTH results exactly once and in order.
        ready_mode = 1;
        cfg_window_samples = 1;
        expect_window(25, 5, 11, -2, 1);
        expect_window(1, 1, 0, -1, 1);
        send_pair(3, 4, 1, 2);
        send_pair(1, 0, 0, 1);
        idle_input();
        repeat (8) begin
            @(posedge clk);
            if (!m_axis_tvalid || s_axis_tready || !dut.product_valid)
                $fatal(1, "Expected both held output and in-flight product");
        end
        drain_results();

        // Reset also cancels a result already held at the output.
        ready_mode = 1;
        expect_window(25, 5, 11, -2, 1);
        send_pair(3, 4, 1, 2);
        idle_input();
        repeat (4) @(negedge clk);
        if (!m_axis_tvalid) $fatal(1, "Missing pending result before reset");
        reset_core();
        ready_mode = 2;

        // Setting the NEXT target to zero must not prevent the previous
        // window's final in-flight product from completing.
        cfg_window_samples = 1;
        expect_window(25, 5, 11, -2, 1);
        send_pair(3, 4, 1, 2);
        @(negedge clk);
        s_axis_tvalid = 0;
        cfg_window_samples = 0;
        drain_results();
        if (s_axis_tready) $fatal(1, "Zero next target did not block new window");

        // Sustained M=1 traffic: consecutive inputs and outputs, with the
        // first product processed while the next input is multiplied.
        cfg_window_samples = 1;
        for (index = 1; index <= 32; index = index + 1) begin
            expect_window(index * index + 1, 1, index, -1, 1);
            send_pair(index, -1, 1, 0);
        end
        drain_results();
        ready_mode = 0;

        vector_file = $fopen("windows.txt", "r");
        if (!vector_file) $fatal(1, "Missing Python reference vectors");
        while (!$feof(vector_file)) begin
            scan_status = $fscanf(vector_file, "%d %d %d %d %d %d\n",
                                  window_size, pa, pb, vr, vi, mutation);
            if (scan_status == 6) begin
                expect_window(pa, pb, vr, vi, window_size);
                @(negedge clk);
                s_axis_tvalid = 0;
                cfg_window_samples = window_size;
                for (sample_index = 0; sample_index < window_size; sample_index = sample_index + 1) begin
                    scan_status = $fscanf(vector_file, "%d %d %d %d\n", ai, aq, bi, bq);
                    if (scan_status != 4) $fatal(1, "Truncated reference sample pair");
                    send_pair(ai, aq, bi, bq, sample_index == 1, mutation);
                    input_rng = {input_rng[30:0], input_rng[31] ^ input_rng[21]
                                 ^ input_rng[1] ^ input_rng[0]};
                    if (input_rng[2:0] == 0) begin
                        idle_input();
                        for (gap_index = 0; gap_index < input_rng[4:3]; gap_index = gap_index + 1)
                            @(negedge clk);
                    end
                end
                windows_from_file = windows_from_file + 1;
            end else if (!$feof(vector_file)) $fatal(1, "Invalid reference window header");
        end
        $fclose(vector_file);
        drain_results();

        cfg_window_samples = 32'hffffffff;
        send_pair(-32768, -32768, -32768, -32768);
        send_pair(32767, 32767, -32768, -32768);
        idle_input();
        repeat (5) @(negedge clk);
        if (m_axis_tvalid) $fatal(1, "Maximum target terminated prematurely");
        reset_core();
        ready_mode = 2;
        cfg_window_samples = 1;
        expect_window(1, 1, 0, 1, 1);
        send_pair(0, 1, 1, 0);
        drain_results();

        if (checked_windows != windows_from_file + 36 || stalled_cycles == 0
            || pipeline_stall_cycles < 8 || max_consecutive_inputs < 32
            || simultaneous_transfers == 0)
            $fatal(1, "Incomplete coverage: windows=%0d max_burst=%0d held_pipeline=%0d",
                   checked_windows, max_consecutive_inputs, pipeline_stall_cycles);
        pass_file = $fopen("simulation_pass.txt", "w");
        if (!pass_file) $fatal(1, "Cannot write pass marker");
        $fdisplay(pass_file, "PASS windows=%0d accepted_pairs=%0d stalled_cycles=%0d pipeline_stall_cycles=%0d max_consecutive_inputs=%0d simultaneous_transfers=%0d",
                  checked_windows, accepted_pairs, stalled_cycles, pipeline_stall_cycles,
                  max_consecutive_inputs, simultaneous_transfers);
        $fclose(pass_file);
        $display("PASS windows=%0d accepted_pairs=%0d stalled_cycles=%0d pipeline_stall_cycles=%0d max_consecutive_inputs=%0d simultaneous_transfers=%0d",
                 checked_windows, accepted_pairs, stalled_cycles, pipeline_stall_cycles,
                 max_consecutive_inputs, simultaneous_transfers);
        $finish;
    end

    initial begin
        #20000000;
        $fatal(1, "Timeout: windows=%0d cfg=%0d accepted=%0d target=%0d ledger=%0d/%0d in=%b/%b out=%b/%b product=%b",
               windows_from_file, cfg_window_samples, dut.samples_accepted,
               dut.window_target, expected_head, expected_tail,
               s_axis_tvalid, s_axis_tready, m_axis_tvalid, m_axis_tready, dut.product_valid);
    end
endmodule
