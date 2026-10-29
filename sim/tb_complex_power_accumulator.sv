`timescale 1ns/1ps

module tb_complex_power_accumulator;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg [31:0] cfg_window_samples = 0;
    reg s_axis_tvalid = 0;
    wire s_axis_tready;
    reg signed [15:0] s_axis_i = 0, s_axis_q = 0;
    wire m_axis_tvalid;
    reg m_axis_tready = 0;
    wire [63:0] m_axis_power_sum;
    wire [31:0] m_axis_sample_count;

    complex_power_accumulator dut (.*);

    reg [63:0] expected_sums [0:511];
    reg [31:0] expected_counts [0:511];
    integer expected_head = 0, expected_tail = 0;
    integer checked_windows = 0, accepted_samples = 0, stalled_cycles = 0;
    integer ready_mode = 0;
    reg [31:0] ready_rng = 32'h1234abcd;
    reg [31:0] input_rng = 32'h9876abcd;
    reg was_stalled = 0;
    reg [63:0] held_sum;
    reg [31:0] held_count;

    // Deterministic receiver backpressure, independent of the input driver.
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
            // Reset deliberately cancels both partial windows and held results.
            expected_head = expected_tail;
            was_stalled = 0;
        end else begin
            if (was_stalled && (!m_axis_tvalid || m_axis_power_sum !== held_sum
                              || m_axis_sample_count !== held_count))
                $fatal(1, "Output changed while receiver was stalled");
            was_stalled = m_axis_tvalid && !m_axis_tready;
            held_sum = m_axis_power_sum;
            held_count = m_axis_sample_count;
            if (was_stalled) stalled_cycles = stalled_cycles + 1;
            if (s_axis_tvalid && s_axis_tready) accepted_samples = accepted_samples + 1;
            if (m_axis_tvalid && m_axis_tready) begin
                if (expected_head == expected_tail)
                    $fatal(1, "Unexpected output (duplicate, stale state, or bad window)");
                if (m_axis_power_sum !== expected_sums[expected_head]
                    || m_axis_sample_count !== expected_counts[expected_head])
                    $fatal(1, "Window %0d: got sum=%0d count=%0d expected sum=%0d count=%0d",
                           checked_windows, m_axis_power_sum, m_axis_sample_count,
                           expected_sums[expected_head], expected_counts[expected_head]);
                expected_head = expected_head + 1;
                checked_windows = checked_windows + 1;
            end
        end
    end

    task expect_window(input reg [63:0] power_sum, input reg [31:0] count);
        begin
            if (expected_tail >= 512) $fatal(1, "Expected-result ledger overflow");
            expected_sums[expected_tail] = power_sum;
            expected_counts[expected_tail] = count;
            expected_tail = expected_tail + 1;
        end
    endtask

    task send_sample(input integer i_value, input integer q_value,
                     input reg change_config = 0, input reg [31:0] new_config = 0);
        begin
            @(negedge clk);
            if (change_config) cfg_window_samples = new_config;
            s_axis_i = i_value;
            s_axis_q = q_value;
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
    integer i_value, q_value, windows_from_file = 0, pass_file;
    reg [63:0] reference_sum;
    reg [31:0] mutation;

    initial begin
        reset_core();
        ready_mode = 2;

        // Zero is an invalid target: no input transaction or result is allowed.
        @(negedge clk);
        cfg_window_samples = 0;
        s_axis_tvalid = 1;
        repeat (8) begin
            @(posedge clk);
            if (s_axis_tready || m_axis_tvalid) $fatal(1, "Zero target accepted");
        end
        idle_input();

        // An incomplete window must not leak into the first post-reset result.
        cfg_window_samples = 10;
        send_sample(30000, -30000);
        send_sample(-32768, -32768);
        send_sample(1234, -5678);
        reset_core();

        // A completed but unconsumed result must also disappear on reset.
        ready_mode = 1;
        cfg_window_samples = 1;
        expect_window(64'd25, 32'd1);
        send_sample(3, 4);
        idle_input();
        repeat (8) begin
            @(posedge clk);
            if (!m_axis_tvalid || s_axis_tready)
                $fatal(1, "Held output did not apply input backpressure");
        end
        reset_core();
        ready_mode = 0;

        vector_file = $fopen("windows.txt", "r");
        if (!vector_file) $fatal(1, "Missing Python reference vectors");
        while (!$feof(vector_file)) begin
            scan_status = $fscanf(vector_file, "%d %d %d\n", window_size, reference_sum, mutation);
            if (scan_status == 3) begin
                expect_window(reference_sum, window_size);
                @(negedge clk);
                s_axis_tvalid = 0;
                cfg_window_samples = window_size;
                for (sample_index = 0; sample_index < window_size; sample_index = sample_index + 1) begin
                    scan_status = $fscanf(vector_file, "%d %d\n", i_value, q_value);
                    if (scan_status != 2) $fatal(1, "Truncated input vector file");
                    // Configuration changes must not split an active window.
                    send_sample(i_value, q_value,
                                sample_index > 0 && sample_index == window_size / 2,
                                mutation);
                    input_rng = {input_rng[30:0], input_rng[31] ^ input_rng[6]
                                ^ input_rng[4] ^ input_rng[2]};
                    // Keep the first long windows contiguous; later use gaps.
                    if (windows_from_file >= 9 && input_rng[2:0] == 0) begin
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

        // Exercise the maximum target without waiting billions of cycles.
        cfg_window_samples = 32'hffffffff;
        send_sample(-32768, -32768);
        send_sample(32767, 32767);
        idle_input();
        repeat (5) @(negedge clk);
        if (m_axis_tvalid) $fatal(1, "Maximum target terminated prematurely");
        reset_core();
        ready_mode = 2;
        cfg_window_samples = 1;
        expect_window(64'd1, 32'd1);
        send_sample(0, -1);
        drain_results();

        if (checked_windows != windows_from_file + 1 || stalled_cycles == 0)
            $fatal(1, "Incomplete test coverage");
        pass_file = $fopen("simulation_pass.txt", "w");
        if (!pass_file) $fatal(1, "Cannot write pass marker");
        $fdisplay(pass_file, "PASS windows=%0d accepted_samples=%0d stalled_cycles=%0d",
                  checked_windows, accepted_samples, stalled_cycles);
        $fclose(pass_file);
        $display("PASS windows=%0d accepted_samples=%0d stalled_cycles=%0d",
                 checked_windows, accepted_samples, stalled_cycles);
        $finish;
    end

    initial begin
        #20000000;
        $fatal(1, "Simulation timeout: windows=%0d index=%0d size=%0d cfg=%0d accepted=%0d target=%0d ledger=%0d/%0d valid/ready=%b/%b out=%b/%b",
               windows_from_file, sample_index, window_size, cfg_window_samples,
               dut.samples_accepted, dut.window_target, expected_head, expected_tail,
               s_axis_tvalid, s_axis_tready, m_axis_tvalid, m_axis_tready);
    end
endmodule
