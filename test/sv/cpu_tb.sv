/* cpu_tb.sv — Minimal testbench for cpu.sv top module */
`timescale 1ns/1ps

module cpu_tb;

    // ----------------------------------------------------------------
    // Clock & reset
    // ----------------------------------------------------------------
    logic clk = 0;
    logic rst = 1;
    always #5 clk = ~clk;   // 100 MHz

    // ----------------------------------------------------------------
    // Interrupt inputs
    // ----------------------------------------------------------------
    logic external_interrupt_in = 0;
    logic timer_interrupt_in    = 0;

    // ----------------------------------------------------------------
    // Wishbone interfaces
    // ----------------------------------------------------------------
    wishbone_interface fetch_wb();
    wishbone_interface mem_wb();

    // Fetch port: always reply with NOP (ADDI x0, x0, 0)
    assign fetch_wb.dat_miso = 32'h0000_0013;
    assign fetch_wb.ack      = fetch_wb.cyc & fetch_wb.stb;
    assign fetch_wb.err      = 1'b0;

    // Mem port: always ACK with 0
    assign mem_wb.dat_miso = 32'h0;
    assign mem_wb.ack      = mem_wb.cyc & mem_wb.stb;
    assign mem_wb.err      = 1'b0;

    // ----------------------------------------------------------------
    // DUT
    // ----------------------------------------------------------------
    cpu dut (
        .clk                   (clk),
        .rst                   (rst),
        .memory_fetch_port     (fetch_wb),
        .memory_mem_port       (mem_wb),
        .external_interrupt_in (external_interrupt_in),
        .timer_interrupt_in    (timer_interrupt_in)
    );

    // ----------------------------------------------------------------
    // Helpers
    // ----------------------------------------------------------------
    task automatic do_reset(input int cycles = 4);
        rst = 1;
        repeat (cycles) @(posedge clk);
        @(negedge clk);
        rst = 0;
    endtask

    task automatic run(input int n);
        repeat (n) @(posedge clk);
    endtask

    task automatic check_no_x(input string name, input logic [31:0] sig);
        if (^sig === 1'bx)
            $display("[FAIL] %s contains X", name);
        else
            $display("[PASS] %s is defined (0x%08X)", name, sig);
    endtask

    // ----------------------------------------------------------------
    // Tests
    // ----------------------------------------------------------------
    initial begin
        $dumpfile("cpu_tb.vcd");
        $dumpvars(0, cpu_tb);

        // ── Test 1: Reset + run ───────────────────────────────────────
        $display("\n-- Test 1: Reset and run --");
        do_reset();
        run(20);
        check_no_x("fetch adr after reset", fetch_wb.adr);

        // ── Test 2: PC advances ───────────────────────────────────────
        $display("\n-- Test 2: PC advances --");
        begin
            logic [31:0] pc_before, pc_after;
            @(posedge clk); pc_before = fetch_wb.adr;
            run(4);
            @(posedge clk); pc_after = fetch_wb.adr;
            if (pc_after > pc_before)
                $display("[PASS] PC advanced: 0x%08X -> 0x%08X", pc_before, pc_after);
            else
                $display("[FAIL] PC did not advance: stuck at 0x%08X", pc_before);
        end

        // ── Test 3: Timer interrupt ───────────────────────────────────
        $display("\n-- Test 3: Timer interrupt --");
        do_reset();
        run(5);
        timer_interrupt_in = 1;
        run(5);
        timer_interrupt_in = 0;
        run(5);
        check_no_x("fetch adr after timer interrupt", fetch_wb.adr);

        // ── Test 4: External interrupt ────────────────────────────────
        $display("\n-- Test 4: External interrupt --");
        do_reset();
        run(5);
        external_interrupt_in = 1;
        run(5);
        external_interrupt_in = 0;
        run(5);
        check_no_x("fetch adr after external interrupt", fetch_wb.adr);

        // ── Test 5: Both interrupts simultaneously ────────────────────
        $display("\n-- Test 5: Both interrupts at once --");
        do_reset();
        run(5);
        external_interrupt_in = 1;
        timer_interrupt_in    = 1;
        run(5);
        external_interrupt_in = 0;
        timer_interrupt_in    = 0;
        run(5);
        check_no_x("fetch adr after both interrupts", fetch_wb.adr);

        // ── Test 6: Multiple resets ───────────────────────────────────
        $display("\n-- Test 6: Multiple resets --");
        repeat (3) begin
            do_reset(2);
            run(5);
        end
        check_no_x("fetch adr after repeated resets", fetch_wb.adr);
        $display("[PASS] Survived multiple resets");

        $display("\n=== Done ===");
        $finish;
    end

    // ── Timeout watchdog ─────────────────────────────────────────────
    initial begin
        #50_000;
        $display("[TIMEOUT] Simulation hung");
        $finish;
    end

endmodule