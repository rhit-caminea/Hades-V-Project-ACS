`timescale 1ns/1ps

module full_test;

    // ----------------------------------------------------------------
    // Clock & reset
    // ----------------------------------------------------------------
    logic clk = 0;
    logic rst = 1;
    always #5 clk = ~clk;

    logic external_interrupt_in = 0;
    logic timer_interrupt_in    = 0;

    // ----------------------------------------------------------------
    // Wishbone interfaces
    // ----------------------------------------------------------------
    wishbone_interface fetch_wb();
    wishbone_interface mem_wb();

    cpu dut (
        .clk                   (clk),
        .rst                   (rst),
        .memory_fetch_port     (fetch_wb),
        .memory_mem_port       (mem_wb),
        .external_interrupt_in (external_interrupt_in),
        .timer_interrupt_in    (timer_interrupt_in)
    );

    // ----------------------------------------------------------------
    // Instruction memory (fetch port)
    // ----------------------------------------------------------------
    logic [31:0] imem [0:255];

    localparam logic [31:0] RESET_VECTOR = 32'h0001_0000;
    logic [31:0] fetch_addr_word;
    assign fetch_addr_word   = (fetch_wb.adr - RESET_VECTOR) >> 2;
    assign fetch_wb.dat_miso = imem[fetch_addr_word[7:0]];
    assign fetch_wb.ack      = fetch_wb.cyc & fetch_wb.stb;
    assign fetch_wb.err      = 1'b0;

    // ----------------------------------------------------------------
    // Data memory (mem port)
    // ----------------------------------------------------------------
    logic [31:0] dmem [0:255];
    logic [31:0] mem_addr_word;
    assign mem_addr_word = mem_wb.adr >> 2;

    always_ff @(posedge clk) begin
        if (mem_wb.cyc && mem_wb.stb && mem_wb.we) begin
            if (mem_wb.sel[0]) dmem[mem_addr_word[7:0]][ 7: 0] <= mem_wb.dat_mosi[ 7: 0];
            if (mem_wb.sel[1]) dmem[mem_addr_word[7:0]][15: 8] <= mem_wb.dat_mosi[15: 8];
            if (mem_wb.sel[2]) dmem[mem_addr_word[7:0]][23:16] <= mem_wb.dat_mosi[23:16];
            if (mem_wb.sel[3]) dmem[mem_addr_word[7:0]][31:24] <= mem_wb.dat_mosi[31:24];
        end
    end

    assign mem_wb.dat_miso = dmem[mem_addr_word[7:0]];
    assign mem_wb.ack      = mem_wb.cyc & mem_wb.stb;
    assign mem_wb.err      = 1'b0;

    // ----------------------------------------------------------------
    // Instruction encoding helpers
    // ----------------------------------------------------------------
    function automatic logic [31:0] NOP();
        return 32'h0000_0013;
    endfunction

    function automatic logic [31:0] LUI(input logic [4:0] rd, input logic [19:0] imm);
        return {imm, rd, 7'b011_0111};
    endfunction

    function automatic logic [31:0] AUIPC(input logic [4:0] rd, input logic [19:0] imm);
        return {imm, rd, 7'b001_0111};
    endfunction

    function automatic logic [31:0] JAL(input logic [4:0] rd, input logic [20:1] imm);
        return {imm[20], imm[10:1], imm[11], imm[19:12], rd, 7'b110_1111};
    endfunction

    function automatic logic [31:0] JALR(input logic [4:0] rd, rs1, input logic [11:0] imm);
        return {imm, rs1, 3'b000, rd, 7'b110_0111};
    endfunction

    function automatic logic [31:0] BEQ(input logic [4:0] rs1, rs2, input logic [12:1] imm);
        return {imm[12], imm[10:5], rs2, rs1, 3'b000, imm[4:1], imm[11], 7'b110_0011};
    endfunction

    function automatic logic [31:0] BNE(input logic [4:0] rs1, rs2, input logic [12:1] imm);
        return {imm[12], imm[10:5], rs2, rs1, 3'b001, imm[4:1], imm[11], 7'b110_0011};
    endfunction

    function automatic logic [31:0] BLT(input logic [4:0] rs1, rs2, input logic [12:1] imm);
        return {imm[12], imm[10:5], rs2, rs1, 3'b100, imm[4:1], imm[11], 7'b110_0011};
    endfunction

    function automatic logic [31:0] BGE(input logic [4:0] rs1, rs2, input logic [12:1] imm);
        return {imm[12], imm[10:5], rs2, rs1, 3'b101, imm[4:1], imm[11], 7'b110_0011};
    endfunction

    function automatic logic [31:0] LB(input logic [4:0] rd, rs1, input logic [11:0] imm);
        return {imm, rs1, 3'b000, rd, 7'b000_0011};
    endfunction

    function automatic logic [31:0] LH(input logic [4:0] rd, rs1, input logic [11:0] imm);
        return {imm, rs1, 3'b001, rd, 7'b000_0011};
    endfunction

    function automatic logic [31:0] LW(input logic [4:0] rd, rs1, input logic [11:0] imm);
        return {imm, rs1, 3'b010, rd, 7'b000_0011};
    endfunction

    function automatic logic [31:0] LBU(input logic [4:0] rd, rs1, input logic [11:0] imm);
        return {imm, rs1, 3'b100, rd, 7'b000_0011};
    endfunction

    function automatic logic [31:0] LHU(input logic [4:0] rd, rs1, input logic [11:0] imm);
        return {imm, rs1, 3'b101, rd, 7'b000_0011};
    endfunction

    function automatic logic [31:0] SB(input logic [4:0] rs1, rs2, input logic [11:0] imm);
        return {imm[11:5], rs2, rs1, 3'b000, imm[4:0], 7'b010_0011};
    endfunction

    function automatic logic [31:0] SH(input logic [4:0] rs1, rs2, input logic [11:0] imm);
        return {imm[11:5], rs2, rs1, 3'b001, imm[4:0], 7'b010_0011};
    endfunction

    function automatic logic [31:0] SW(input logic [4:0] rs1, rs2, input logic [11:0] imm);
        return {imm[11:5], rs2, rs1, 3'b010, imm[4:0], 7'b010_0011};
    endfunction

    function automatic logic [31:0] ADDI(input logic [4:0] rd, rs1, input logic [11:0] imm);
        return {imm, rs1, 3'b000, rd, 7'b001_0011};
    endfunction

    function automatic logic [31:0] SLTI(input logic [4:0] rd, rs1, input logic [11:0] imm);
        return {imm, rs1, 3'b010, rd, 7'b001_0011};
    endfunction

    function automatic logic [31:0] SLTIU(input logic [4:0] rd, rs1, input logic [11:0] imm);
        return {imm, rs1, 3'b011, rd, 7'b001_0011};
    endfunction

    function automatic logic [31:0] XORI(input logic [4:0] rd, rs1, input logic [11:0] imm);
        return {imm, rs1, 3'b100, rd, 7'b001_0011};
    endfunction

    function automatic logic [31:0] ORI(input logic [4:0] rd, rs1, input logic [11:0] imm);
        return {imm, rs1, 3'b110, rd, 7'b001_0011};
    endfunction

    function automatic logic [31:0] ANDI(input logic [4:0] rd, rs1, input logic [11:0] imm);
        return {imm, rs1, 3'b111, rd, 7'b001_0011};
    endfunction

    function automatic logic [31:0] SLLI(input logic [4:0] rd, rs1, input logic [4:0] shamt);
        return {7'b000_0000, shamt, rs1, 3'b001, rd, 7'b001_0011};
    endfunction

    function automatic logic [31:0] SRLI(input logic [4:0] rd, rs1, input logic [4:0] shamt);
        return {7'b000_0000, shamt, rs1, 3'b101, rd, 7'b001_0011};
    endfunction

    function automatic logic [31:0] SRAI(input logic [4:0] rd, rs1, input logic [4:0] shamt);
        return {7'b010_0000, shamt, rs1, 3'b101, rd, 7'b001_0011};
    endfunction

    function automatic logic [31:0] ADD(input logic [4:0] rd, rs1, rs2);
        return {7'b000_0000, rs2, rs1, 3'b000, rd, 7'b011_0011};
    endfunction

    function automatic logic [31:0] SUB(input logic [4:0] rd, rs1, rs2);
        return {7'b010_0000, rs2, rs1, 3'b000, rd, 7'b011_0011};
    endfunction

    function automatic logic [31:0] SLL(input logic [4:0] rd, rs1, rs2);
        return {7'b000_0000, rs2, rs1, 3'b001, rd, 7'b011_0011};
    endfunction

    function automatic logic [31:0] SLT(input logic [4:0] rd, rs1, rs2);
        return {7'b000_0000, rs2, rs1, 3'b010, rd, 7'b011_0011};
    endfunction

    function automatic logic [31:0] SLTU(input logic [4:0] rd, rs1, rs2);
        return {7'b000_0000, rs2, rs1, 3'b011, rd, 7'b011_0011};
    endfunction

    function automatic logic [31:0] XOR(input logic [4:0] rd, rs1, rs2);
        return {7'b000_0000, rs2, rs1, 3'b100, rd, 7'b011_0011};
    endfunction

    function automatic logic [31:0] SRL(input logic [4:0] rd, rs1, rs2);
        return {7'b000_0000, rs2, rs1, 3'b101, rd, 7'b011_0011};
    endfunction

    function automatic logic [31:0] SRA(input logic [4:0] rd, rs1, rs2);
        return {7'b010_0000, rs2, rs1, 3'b101, rd, 7'b011_0011};
    endfunction

    function automatic logic [31:0] OR(input logic [4:0] rd, rs1, rs2);
        return {7'b000_0000, rs2, rs1, 3'b110, rd, 7'b011_0011};
    endfunction

    function automatic logic [31:0] AND(input logic [4:0] rd, rs1, rs2);
        return {7'b000_0000, rs2, rs1, 3'b111, rd, 7'b011_0011};
    endfunction

    // ----------------------------------------------------------------
    // Helpers
    // ----------------------------------------------------------------
    int pass_count = 0;
    int fail_count = 0;

    task automatic do_reset(input int cycles = 4);
        rst = 1;
        repeat (cycles) @(posedge clk);
        @(negedge clk);
        rst = 0;
    endtask

    task automatic run(input int n);
        repeat (n) @(posedge clk);
    endtask

    task automatic check(input string name, input logic [31:0] got, input logic [31:0] exp);
        if (got === exp) begin
            $display("[PASS] %s = 0x%08X", name, got);
            pass_count++;
        end else begin
            $display("[FAIL] %s: got 0x%08X, expected 0x%08X", name, got, exp);
            fail_count++;
        end
    endtask

    task automatic fill_nops();
        for (int i = 0; i < 256; i++) imem[i] = NOP();
        for (int i = 0; i < 256; i++) dmem[i] = 32'h0;
    endtask

    // ----------------------------------------------------------------
    // TEST PROGRAMS
    // ----------------------------------------------------------------

    // ── Test 1: ADDI ─────────────────────────────────────────────────
    task automatic test_addi();
        $display("\n-- Test 1: ADDI --");
        fill_nops();
        imem[0] = ADDI(5'd1, 5'd0, 12'd42);
        imem[1] = ADDI(5'd2, 5'd1, 12'd10);
        imem[2] = NOP(); imem[3] = NOP(); imem[4] = NOP(); imem[5] = NOP();
        imem[6] = SW  (5'd0, 5'd2, 12'd0);
        imem[7] = NOP(); imem[8] = NOP(); imem[9] = NOP(); imem[10] = NOP();
        do_reset(); run(30);
        check("ADDI: dmem[0]", dmem[0], 32'd52);
    endtask

    // ── Test 2: ADD / SUB ────────────────────────────────────────────
    task automatic test_add_sub();
        $display("\n-- Test 2: ADD / SUB --");
        fill_nops();
        imem[0]  = ADDI(5'd1, 5'd0, 12'd100);
        imem[1]  = ADDI(5'd2, 5'd0, 12'd37);
        imem[2]  = ADD (5'd3, 5'd1, 5'd2);
        imem[3]  = SUB (5'd4, 5'd1, 5'd2);
        imem[4]  = NOP(); imem[5]  = NOP(); imem[6]  = NOP(); imem[7]  = NOP();
        imem[8]  = SW  (5'd0, 5'd3, 12'd0);
        imem[9]  = NOP(); imem[10] = NOP(); imem[11] = NOP(); imem[12] = NOP();
        imem[13] = NOP(); imem[14] = NOP(); imem[15] = NOP(); imem[16] = NOP();
        imem[17] = SW  (5'd0, 5'd4, 12'd4);
        imem[18] = NOP(); imem[19] = NOP(); imem[20] = NOP(); imem[21] = NOP();
        do_reset(); run(60);
        check("ADD: dmem[0]", dmem[0], 32'd137);
        check("SUB: dmem[1]", dmem[1], 32'd63);
    endtask

    // ── Test 3: Forwarding ───────────────────────────────────────────
    task automatic test_forwarding();
        $display("\n-- Test 3: Forwarding --");
        fill_nops();
        imem[0] = ADDI(5'd1, 5'd0, 12'd1);
        imem[1] = ADDI(5'd2, 5'd1, 12'd1);
        imem[2] = ADDI(5'd3, 5'd2, 12'd1);
        imem[3] = ADDI(5'd4, 5'd3, 12'd1);
        imem[4] = NOP(); imem[5] = NOP(); imem[6] = NOP(); imem[7] = NOP();
        imem[8] = SW  (5'd0, 5'd4, 12'd0);
        imem[9] = NOP(); imem[10] = NOP(); imem[11] = NOP(); imem[12] = NOP();
        do_reset(); run(35);
        check("Forwarding: dmem[0]", dmem[0], 32'd4);
    endtask

    // ── Test 4: LUI / AUIPC ──────────────────────────────────────────
    task automatic test_lui_auipc();
        $display("\n-- Test 4: LUI / AUIPC --");
        fill_nops();
        // imem[0]  = 0x00010000: LUI x1, 0xDEAD  -> x1 = 0xDEAD_0000
        // imem[5]  = 0x00010014: SW x1 -> dmem[0]
        // imem[10] = 0x00010028: AUIPC x2, 1 -> x2 = 0x00010028 + 0x1000 = 0x00011028
        // imem[15] = 0x0001003C: SW x2 -> dmem[1]
        imem[0]  = LUI  (5'd1, 20'hDEAD);
        imem[1]  = NOP(); imem[2]  = NOP(); imem[3]  = NOP(); imem[4]  = NOP();
        imem[5]  = SW   (5'd0, 5'd1, 12'd0);
        imem[6]  = NOP(); imem[7]  = NOP(); imem[8]  = NOP(); imem[9]  = NOP();
        imem[10] = AUIPC(5'd2, 20'h1);
        imem[11] = NOP(); imem[12] = NOP(); imem[13] = NOP(); imem[14] = NOP();
        imem[15] = SW   (5'd0, 5'd2, 12'd4);
        imem[16] = NOP(); imem[17] = NOP(); imem[18] = NOP(); imem[19] = NOP();
        do_reset(); run(60);
        check("LUI:   dmem[0]", dmem[0], 32'hDEAD_0000);
        check("AUIPC: dmem[1]", dmem[1], 32'h0001_1028);
    endtask

    // ── Test 5: SW + LW ──────────────────────────────────────────────
    task automatic test_load_store();
        $display("\n-- Test 5: SW + LW --");
        fill_nops();
        imem[0]  = ADDI(5'd1, 5'd0, 12'h123);
        imem[1]  = NOP(); imem[2]  = NOP(); imem[3]  = NOP(); imem[4]  = NOP();
        imem[5]  = SW  (5'd0, 5'd1, 12'd0);
        imem[6]  = NOP(); imem[7]  = NOP(); imem[8]  = NOP(); imem[9]  = NOP();
        imem[10] = LW  (5'd2, 5'd0, 12'd0);
        imem[11] = NOP(); imem[12] = NOP(); imem[13] = NOP(); imem[14] = NOP();
        imem[15] = NOP(); imem[16] = NOP(); imem[17] = NOP(); imem[18] = NOP();
        imem[19] = SW  (5'd0, 5'd2, 12'd4);
        imem[20] = NOP(); imem[21] = NOP(); imem[22] = NOP(); imem[23] = NOP();
        do_reset(); run(60);
        check("SW+LW: dmem[0]", dmem[0], 32'h0000_0123);
        check("SW+LW: dmem[1]", dmem[1], 32'h0000_0123);
    endtask

    // ── Test 6: BEQ taken ────────────────────────────────────────────
    task automatic test_beq_taken();
        $display("\n-- Test 6: BEQ taken --");
        fill_nops();
        // imem[0] = ADDI x1, 5
        // imem[1] = ADDI x2, 5
        // imem[2] = BEQ +16 -> land at imem[6]
        // imem[3] = SW dmem[0]  <- skipped
        // imem[6..9] = NOPs
        // imem[10] = SW dmem[4] <- executed
        imem[0]  = ADDI(5'd1, 5'd0, 12'd5);
        imem[1]  = ADDI(5'd2, 5'd0, 12'd5);
        imem[2]  = BEQ (5'd1, 5'd2, 13'd16);
        imem[3]  = SW  (5'd0, 5'd1, 12'd0);   // skipped
        imem[4]  = NOP(); imem[5]  = NOP();
        imem[6]  = NOP(); imem[7]  = NOP(); imem[8]  = NOP(); imem[9]  = NOP();
        imem[10] = SW  (5'd0, 5'd2, 12'd4);   // executed
        imem[11] = NOP(); imem[12] = NOP(); imem[13] = NOP(); imem[14] = NOP();
        do_reset(); run(50);
        check("BEQ taken: dmem[0] not written", dmem[0], 32'd0);
        check("BEQ taken: dmem[1] written",     dmem[1], 32'd5);
    endtask

    // ── Test 7: BNE not taken ────────────────────────────────────────
    task automatic test_bne_not_taken();
        $display("\n-- Test 7: BNE not taken --");
        fill_nops();
        imem[0] = ADDI(5'd1, 5'd0, 12'd3);
        imem[1] = ADDI(5'd2, 5'd0, 12'd3);
        imem[2] = BNE (5'd1, 5'd2, 13'd8);   // not taken x1==x2
        imem[3] = NOP(); imem[4] = NOP(); imem[5] = NOP(); imem[6] = NOP();
        imem[7] = SW  (5'd0, 5'd1, 12'd0);   // executed
        imem[8] = NOP(); imem[9] = NOP(); imem[10] = NOP(); imem[11] = NOP();
        do_reset(); run(35);
        check("BNE not taken: dmem[0]", dmem[0], 32'd3);
    endtask

    // ── Test 8: AND / OR / XOR ───────────────────────────────────────
    task automatic test_logic();
        $display("\n-- Test 8: AND / OR / XOR --");
        fill_nops();
        imem[0]  = ADDI(5'd1, 5'd0, 12'hFF);
        imem[1]  = ADDI(5'd2, 5'd0, 12'h0F);
        imem[2]  = AND (5'd3, 5'd1, 5'd2);
        imem[3]  = OR  (5'd4, 5'd1, 5'd2);
        imem[4]  = XOR (5'd5, 5'd1, 5'd2);
        imem[5]  = NOP(); imem[6]  = NOP(); imem[7]  = NOP(); imem[8]  = NOP();
        imem[9]  = SW  (5'd0, 5'd3, 12'd0);
        imem[10] = NOP(); imem[11] = NOP(); imem[12] = NOP(); imem[13] = NOP();
        imem[14] = NOP(); imem[15] = NOP(); imem[16] = NOP(); imem[17] = NOP();
        imem[18] = SW  (5'd0, 5'd4, 12'd4);
        imem[19] = NOP(); imem[20] = NOP(); imem[21] = NOP(); imem[22] = NOP();
        imem[23] = NOP(); imem[24] = NOP(); imem[25] = NOP(); imem[26] = NOP();
        imem[27] = SW  (5'd0, 5'd5, 12'd8);
        imem[28] = NOP(); imem[29] = NOP(); imem[30] = NOP(); imem[31] = NOP();
        do_reset(); run(70);
        check("AND: dmem[0]", dmem[0], 32'h0000_000F);
        check("OR:  dmem[1]", dmem[1], 32'h0000_00FF);
        check("XOR: dmem[2]", dmem[2], 32'h0000_00F0);
    endtask

    // ── Test 9: Timer interrupt ───────────────────────────────────────
    task automatic test_timer_interrupt();
        $display("\n-- Test 9: Timer interrupt --");
        fill_nops();
        do_reset();
        run(5);
        timer_interrupt_in = 1;
        run(5);
        timer_interrupt_in = 0;
        run(10);
        if (^fetch_wb.adr === 1'bx)
            $display("[FAIL] fetch adr X after timer interrupt");
        else begin
            $display("[PASS] CPU alive after timer interrupt (PC=0x%08X)", fetch_wb.adr);
            pass_count++;
        end
    endtask

    // ── Test 10: External interrupt ───────────────────────────────────
    task automatic test_external_interrupt();
        $display("\n-- Test 10: External interrupt --");
        fill_nops();
        do_reset();
        run(5);
        external_interrupt_in = 1;
        run(5);
        external_interrupt_in = 0;
        run(10);
        if (^fetch_wb.adr === 1'bx)
            $display("[FAIL] fetch adr X after external interrupt");
        else begin
            $display("[PASS] CPU alive after external interrupt (PC=0x%08X)", fetch_wb.adr);
            pass_count++;
        end
    endtask

    // ----------------------------------------------------------------
    // MAIN
    // ----------------------------------------------------------------
    initial begin
        $dumpfile("cpu_tb.vcd");
        $dumpvars(0, cpu_tb);

        test_addi();
        test_add_sub();
        test_forwarding();
        test_lui_auipc();
        test_load_store();
        test_beq_taken();
        test_bne_not_taken();
        test_logic();
        test_timer_interrupt();
        test_external_interrupt();

        $display("\n=== Results: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED — check waveform");

        $finish;
    end

    initial begin
        #200_000;
        $display("[TIMEOUT] Simulation hung");
        $finish;
    end

endmodule