/* Copyright (c) 2024 Tobias Scheipel, David Beikircher, Florian Riedl
 * Embedded Architectures & Systems Group, Graz University of Technology
 * SPDX-License-Identifier: MIT
 * ---------------------------------------------------------------------
 * File: test_cpu.sv
 */

module test_cpu;
    // --------------------------------------------------------------------------------------------
    // Testbench for a RISC-V RV32I CPU with two Wishbone ports (fetch + data).
    // Instructions are driven directly from testbench-local IMEM/DMEM arrays.
    //
    // Instruction groups covered:
    //   R-type    : ADD SUB AND OR XOR SLL SRL SRA SLT SLTU
    //   I-type    : ADDI SLTI SLTIU ANDI ORI XORI SLLI SRLI SRAI
    //   Load/Store: LW SW LH SH LB SB LHU LBU
    //   Branch    : BEQ BNE BLT BGE BLTU BGEU
    // --------------------------------------------------------------------------------------------
    import clk_params::*;

    /*verilator lint_off UNUSED*/
    logic clk, clk_vga;
    logic rst;
    /*verilator lint_on UNUSED*/

    // --------------------------------------------------------------------------------------------
    // Clocks
    initial begin
        clk = 1;
        forever begin
            #(int'(SIM_CYCLES_PER_SYS_CLK / 2));
            clk = ~clk;
        end
    end

    initial begin
        clk_vga = 1;
        forever begin
            #(int'(SIM_CYCLES_PER_VGA_CLK / 2));
            clk_vga = ~clk_vga;
        end
    end

    // --------------------------------------------------------------------------------------------
    int error_count = 0;

    // --------------------------------------------------------------------------------------------
    // Wishbone interfaces
    wishbone_interface fetch_bus();
    wishbone_interface mem_bus();

    // --------------------------------------------------------------------------------------------
    // Memory map:
    //   0x0000_0000 – 0x0000_0FFF : IMEM (1024 words)
    //   0x0001_0000 – 0x0001_0FFF : DMEM (1024 words)

    localparam int          IMEM_WORDS = 1024;
    localparam int          DMEM_WORDS = 1024;
    localparam logic [31:0] DMEM_BASE  = 32'h0001_0000;

    logic [31:0] imem [0:IMEM_WORDS-1];
    logic [31:0] dmem [0:DMEM_WORDS-1];

    // Instruction fetch – combinatorial ROM
    assign fetch_bus.dat_miso = imem[fetch_bus.adr[11:2]];
    assign fetch_bus.ack      = fetch_bus.stb & fetch_bus.cyc;
    assign fetch_bus.err      = 1'b0;

    // Data memory – synchronous write, combinatorial read
    always_ff @(posedge clk) begin
        if (mem_bus.stb && mem_bus.cyc && mem_bus.we) begin
            automatic logic [31:0] widx;
            widx = (mem_bus.adr - DMEM_BASE) >> 2;
            if (mem_bus.sel[0]) dmem[widx][ 7: 0] <= mem_bus.dat_mosi[ 7: 0];
            if (mem_bus.sel[1]) dmem[widx][15: 8] <= mem_bus.dat_mosi[15: 8];
            if (mem_bus.sel[2]) dmem[widx][23:16] <= mem_bus.dat_mosi[23:16];
            if (mem_bus.sel[3]) dmem[widx][31:24] <= mem_bus.dat_mosi[31:24];
        end
    end
    assign mem_bus.dat_miso = dmem[(mem_bus.adr - DMEM_BASE) >> 2];
    assign mem_bus.ack      = mem_bus.stb & mem_bus.cyc;
    assign mem_bus.err      = 1'b0;

    // --------------------------------------------------------------------------------------------
    // DUT
    cpu dut (
        .clk                   (clk),
        .rst                   (rst),
        .memory_fetch_port     (fetch_bus.master),
        .memory_mem_port       (mem_bus.master),
        .external_interrupt_in (1'b0),
        .timer_interrupt_in    (1'b0)
    );

    // --------------------------------------------------------------------------------------------
    // Reset
    task automatic perform_rst();
        @(negedge clk); #1;
        rst = 1;
        for (int i = 0; i < IMEM_WORDS; i++) imem[i] = 32'h0000_0013; // NOP
        for (int i = 0; i < DMEM_WORDS; i++) dmem[i] = 32'h0;
        @(posedge clk); #1;
        @(posedge clk); #1;
        rst = 0;
    endtask

    task automatic run_cycles(input int n);
        repeat (n) @(posedge clk);
        #1;
    endtask

    // Verify DMEM word
    task automatic prove_dmem(input logic [31:0] byte_addr, input logic [31:0] expected);
        automatic int idx;
        idx = int'((byte_addr - DMEM_BASE) >> 2);
        assert (dmem[idx] === expected) else begin
            $display("(%6d ns) FAIL dmem[0x%08x] = 0x%08x  (expected 0x%08x)",
                     $time(), byte_addr, dmem[idx], expected);
            error_count++;
        end
    endtask

    // --------------------------------------------------------------------------------------------
    // Opcode constants
    localparam logic [6:0] OP_REG    = 7'b011_0011;
    localparam logic [6:0] OP_IMM    = 7'b001_0011;
    localparam logic [6:0] OP_LOAD   = 7'b000_0011;
    localparam logic [6:0] OP_STORE  = 7'b010_0011;
    localparam logic [6:0] OP_BRANCH = 7'b110_0011;
    localparam logic [6:0] OP_LUI    = 7'b011_0111;
    localparam logic [6:0] OP_JALR   = 7'b110_0111;

    // --------------------------------------------------------------------------------------------
    // Base instruction encoders (all args use 'input', no semicolons)

    function automatic logic [31:0] enc_r(
        input logic [6:0] funct7,
        input logic [4:0] rs2,
        input logic [4:0] rs1,
        input logic [2:0] funct3,
        input logic [4:0] rd,
        input logic [6:0] opcode
    );
        return {funct7, rs2, rs1, funct3, rd, opcode};
    endfunction

    function automatic logic [31:0] enc_i(
        input logic [11:0] imm,
        input logic [4:0]  rs1,
        input logic [2:0]  funct3,
        input logic [4:0]  rd,
        input logic [6:0]  opcode
    );
        return {imm, rs1, funct3, rd, opcode};
    endfunction

    function automatic logic [31:0] enc_s(
        input logic [11:0] imm,
        input logic [4:0]  rs2,
        input logic [4:0]  rs1,
        input logic [2:0]  funct3,
        input logic [6:0]  opcode
    );
        return {imm[11:5], rs2, rs1, funct3, imm[4:0], opcode};
    endfunction

    function automatic logic [31:0] enc_b(
        input logic [12:1] imm,
        input logic [4:0]  rs2,
        input logic [4:0]  rs1,
        input logic [2:0]  funct3,
        input logic [6:0]  opcode
    );
        return {imm[12], imm[10:5], rs2, rs1, funct3, imm[4:1], imm[11], opcode};
    endfunction

    function automatic logic [31:0] enc_u(
        input logic [19:0] imm20,
        input logic [4:0]  rd,
        input logic [6:0]  opcode
    );
        return {imm20, rd, opcode};
    endfunction

    // --------------------------------------------------------------------------------------------
    // R-type
    function automatic logic [31:0] ADD (input logic [4:0] rd, input logic [4:0] rs1, input logic [4:0] rs2); return enc_r(7'b000_0000, rs2, rs1, 3'b000, rd, OP_REG); endfunction
    function automatic logic [31:0] SUB (input logic [4:0] rd, input logic [4:0] rs1, input logic [4:0] rs2); return enc_r(7'b010_0000, rs2, rs1, 3'b000, rd, OP_REG); endfunction
    function automatic logic [31:0] AND (input logic [4:0] rd, input logic [4:0] rs1, input logic [4:0] rs2); return enc_r(7'b000_0000, rs2, rs1, 3'b111, rd, OP_REG); endfunction
    function automatic logic [31:0] OR  (input logic [4:0] rd, input logic [4:0] rs1, input logic [4:0] rs2); return enc_r(7'b000_0000, rs2, rs1, 3'b110, rd, OP_REG); endfunction
    function automatic logic [31:0] XOR (input logic [4:0] rd, input logic [4:0] rs1, input logic [4:0] rs2); return enc_r(7'b000_0000, rs2, rs1, 3'b100, rd, OP_REG); endfunction
    function automatic logic [31:0] SLL (input logic [4:0] rd, input logic [4:0] rs1, input logic [4:0] rs2); return enc_r(7'b000_0000, rs2, rs1, 3'b001, rd, OP_REG); endfunction
    function automatic logic [31:0] SRL (input logic [4:0] rd, input logic [4:0] rs1, input logic [4:0] rs2); return enc_r(7'b000_0000, rs2, rs1, 3'b101, rd, OP_REG); endfunction
    function automatic logic [31:0] SRA (input logic [4:0] rd, input logic [4:0] rs1, input logic [4:0] rs2); return enc_r(7'b010_0000, rs2, rs1, 3'b101, rd, OP_REG); endfunction
    function automatic logic [31:0] SLT (input logic [4:0] rd, input logic [4:0] rs1, input logic [4:0] rs2); return enc_r(7'b000_0000, rs2, rs1, 3'b010, rd, OP_REG); endfunction
    function automatic logic [31:0] SLTU(input logic [4:0] rd, input logic [4:0] rs1, input logic [4:0] rs2); return enc_r(7'b000_0000, rs2, rs1, 3'b011, rd, OP_REG); endfunction

    // I-type ALU
    function automatic logic [31:0] ADDI (input logic [4:0] rd, input logic [4:0] rs1, input logic [11:0] imm); return enc_i(imm,                    rs1, 3'b000, rd, OP_IMM); endfunction
    function automatic logic [31:0] SLTI (input logic [4:0] rd, input logic [4:0] rs1, input logic [11:0] imm); return enc_i(imm,                    rs1, 3'b010, rd, OP_IMM); endfunction
    function automatic logic [31:0] SLTIU(input logic [4:0] rd, input logic [4:0] rs1, input logic [11:0] imm); return enc_i(imm,                    rs1, 3'b011, rd, OP_IMM); endfunction
    function automatic logic [31:0] ANDI (input logic [4:0] rd, input logic [4:0] rs1, input logic [11:0] imm); return enc_i(imm,                    rs1, 3'b111, rd, OP_IMM); endfunction
    function automatic logic [31:0] ORI  (input logic [4:0] rd, input logic [4:0] rs1, input logic [11:0] imm); return enc_i(imm,                    rs1, 3'b110, rd, OP_IMM); endfunction
    function automatic logic [31:0] XORI (input logic [4:0] rd, input logic [4:0] rs1, input logic [11:0] imm); return enc_i(imm,                    rs1, 3'b100, rd, OP_IMM); endfunction
    function automatic logic [31:0] SLLI (input logic [4:0] rd, input logic [4:0] rs1, input logic [4:0] shamt); return enc_i({7'b000_0000, shamt},  rs1, 3'b001, rd, OP_IMM); endfunction
    function automatic logic [31:0] SRLI (input logic [4:0] rd, input logic [4:0] rs1, input logic [4:0] shamt); return enc_i({7'b000_0000, shamt},  rs1, 3'b101, rd, OP_IMM); endfunction
    function automatic logic [31:0] SRAI (input logic [4:0] rd, input logic [4:0] rs1, input logic [4:0] shamt); return enc_i({7'b010_0000, shamt},  rs1, 3'b101, rd, OP_IMM); endfunction

    // LUI
    function automatic logic [31:0] LUI(input logic [4:0] rd, input logic [19:0] imm20);
        return enc_u(imm20, rd, OP_LUI);
    endfunction

    // Loads
    function automatic logic [31:0] LW (input logic [4:0] rd, input logic [4:0] rs1, input logic [11:0] imm); return enc_i(imm, rs1, 3'b010, rd, OP_LOAD); endfunction
    function automatic logic [31:0] LH (input logic [4:0] rd, input logic [4:0] rs1, input logic [11:0] imm); return enc_i(imm, rs1, 3'b001, rd, OP_LOAD); endfunction
    function automatic logic [31:0] LB (input logic [4:0] rd, input logic [4:0] rs1, input logic [11:0] imm); return enc_i(imm, rs1, 3'b000, rd, OP_LOAD); endfunction
    function automatic logic [31:0] LHU(input logic [4:0] rd, input logic [4:0] rs1, input logic [11:0] imm); return enc_i(imm, rs1, 3'b101, rd, OP_LOAD); endfunction
    function automatic logic [31:0] LBU(input logic [4:0] rd, input logic [4:0] rs1, input logic [11:0] imm); return enc_i(imm, rs1, 3'b100, rd, OP_LOAD); endfunction

    // Stores
    function automatic logic [31:0] SW(input logic [4:0] rs1, input logic [4:0] rs2, input logic [11:0] imm); return enc_s(imm, rs2, rs1, 3'b010, OP_STORE); endfunction
    function automatic logic [31:0] SH(input logic [4:0] rs1, input logic [4:0] rs2, input logic [11:0] imm); return enc_s(imm, rs2, rs1, 3'b001, OP_STORE); endfunction
    function automatic logic [31:0] SB(input logic [4:0] rs1, input logic [4:0] rs2, input logic [11:0] imm); return enc_s(imm, rs2, rs1, 3'b000, OP_STORE); endfunction

    // Branches (imm is byte offset [12:1], bit 0 implicit 0)
    function automatic logic [31:0] BEQ (input logic [4:0] rs1, input logic [4:0] rs2, input logic [12:1] imm); return enc_b(imm, rs2, rs1, 3'b000, OP_BRANCH); endfunction
    function automatic logic [31:0] BNE (input logic [4:0] rs1, input logic [4:0] rs2, input logic [12:1] imm); return enc_b(imm, rs2, rs1, 3'b001, OP_BRANCH); endfunction
    function automatic logic [31:0] BLT (input logic [4:0] rs1, input logic [4:0] rs2, input logic [12:1] imm); return enc_b(imm, rs2, rs1, 3'b100, OP_BRANCH); endfunction
    function automatic logic [31:0] BGE (input logic [4:0] rs1, input logic [4:0] rs2, input logic [12:1] imm); return enc_b(imm, rs2, rs1, 3'b101, OP_BRANCH); endfunction
    function automatic logic [31:0] BLTU(input logic [4:0] rs1, input logic [4:0] rs2, input logic [12:1] imm); return enc_b(imm, rs2, rs1, 3'b110, OP_BRANCH); endfunction
    function automatic logic [31:0] BGEU(input logic [4:0] rs1, input logic [4:0] rs2, input logic [12:1] imm); return enc_b(imm, rs2, rs1, 3'b111, OP_BRANCH); endfunction

    // Infinite loop / halt
    function automatic logic [31:0] HALT();
        return enc_i(12'd0, 5'd0, 3'b000, 5'd0, OP_JALR); // JALR x0, x0, 0
    endfunction

    // --------------------------------------------------------------------------------------------
    // Load program from queue into IMEM; append HALT
    task automatic load_program(input logic [31:0] prog [$]);
        automatic int n;
        n = prog.size();
        for (int i = 0; i < IMEM_WORDS; i++) imem[i] = 32'h0000_0013; // NOP
        for (int i = 0; i < n; i++)          imem[i] = prog[i];
        imem[n] = HALT();
    endtask

    // --------------------------------------------------------------------------------------------
    // Register aliases
    localparam logic [4:0]
        X0  = 5'd0,  X1  = 5'd1,  X2  = 5'd2,  X3  = 5'd3,
        X4  = 5'd4,  X5  = 5'd5,  X6  = 5'd6,  X7  = 5'd7,
        X8  = 5'd8,  X9  = 5'd9,  X10 = 5'd10, X11 = 5'd11;

    localparam logic [31:0] RES = DMEM_BASE;

    // --------------------------------------------------------------------------------------------
    // |                                   Main Test                                              |
    // --------------------------------------------------------------------------------------------
    initial begin
        $dumpfile("test_cpu.fst");
        $dumpvars;

        rst = 0;

        // ========================================================================================
        // Section 1 – I-type
        // ========================================================================================
        $display("------------------------------ (%6d ns) Section 1: I-type instructions", $time());
        perform_rst();

        begin : sec1_itype
            automatic logic [31:0] prog [$];

            // x1 = 0x0001_0000 (result base, loaded via LUI)
            // x2 = 42
            // x3 = x2 + (-10) = 32        [ADDI with two's-complement -10 = 0xFF6]
            // x4 = (x2 < 50)  = 1         [SLTI]
            // x5 = (x2 < 42)  = 0         [SLTI, equal → not less than]
            // x6 = (x0 <u 1)  = 1         [SLTIU]
            // x7 = x2 & 0xFF  = 42        [ANDI]
            // x8 = x2 | 0x100 = 0x12A     [ORI]
            // x9 = x2 ^ 0x0F  = 37        [XORI]
            // x10= x2 << 2    = 168       [SLLI]
            // x11= x8 >> 1    = 0x95      [SRLI]

            prog.push_back(LUI  (X1,  20'h0001_0));
            prog.push_back(ADDI (X2,  X0,  12'd42));
            prog.push_back(ADDI (X3,  X2,  12'hFF6));   // -10 in 12-bit two's complement
            prog.push_back(SLTI (X4,  X2,  12'd50));
            prog.push_back(SLTI (X5,  X2,  12'd42));
            prog.push_back(SLTIU(X6,  X0,  12'd1));
            prog.push_back(ANDI (X7,  X2,  12'hFF));
            prog.push_back(ORI  (X8,  X2,  12'h100));
            prog.push_back(XORI (X9,  X2,  12'h00F));
            prog.push_back(SLLI (X10, X2,  5'd2));
            prog.push_back(SRLI (X11, X8,  5'd1));
            prog.push_back(SW   (X1,  X2,  12'd0));
            prog.push_back(SW   (X1,  X3,  12'd4));
            prog.push_back(SW   (X1,  X4,  12'd8));
            prog.push_back(SW   (X1,  X5,  12'd12));
            prog.push_back(SW   (X1,  X6,  12'd16));
            prog.push_back(SW   (X1,  X7,  12'd20));
            prog.push_back(SW   (X1,  X8,  12'd24));
            prog.push_back(SW   (X1,  X9,  12'd28));
            prog.push_back(SW   (X1,  X10, 12'd32));
            prog.push_back(SW   (X1,  X11, 12'd36));

            load_program(prog);
            run_cycles(80);

            prove_dmem(RES + 0,  32'd42);
            prove_dmem(RES + 4,  32'd32);
            prove_dmem(RES + 8,  32'd1);
            prove_dmem(RES + 12, 32'd0);
            prove_dmem(RES + 16, 32'd1);
            prove_dmem(RES + 20, 32'd42);
            prove_dmem(RES + 24, 32'h12A);
            prove_dmem(RES + 28, 32'd37);
            prove_dmem(RES + 32, 32'd168);
            prove_dmem(RES + 36, 32'h95);
        end

        // SRAI: arithmetic right shift of negative values
        begin : sec1_srai
            automatic logic [31:0] prog [$];

            // x2 = -1   (ADDI x0, 0xFFF)
            // x3 = SRAI x2, 4  → -1 (arithmetic shift of all-ones)
            // x4 = -128 (ADDI x0, 0xF80)
            // x5 = SRAI x4, 3  → -16

            prog.push_back(LUI  (X1, 20'h0001_0));
            prog.push_back(ADDI (X2, X0, 12'hFFF));     // -1
            prog.push_back(SRAI (X3, X2, 5'd4));         // -1 >>> 4 = -1
            prog.push_back(ADDI (X4, X0, 12'hF80));     // -128
            prog.push_back(SRAI (X5, X4, 5'd3));         // -128 >>> 3 = -16
            prog.push_back(SW   (X1, X3, 12'd0));
            prog.push_back(SW   (X1, X5, 12'd4));

            load_program(prog);
            run_cycles(40);

            prove_dmem(RES + 0, 32'hFFFF_FFFF);
            prove_dmem(RES + 4, 32'hFFFF_FFF0);
        end

        // ========================================================================================
        // Section 2 – R-type
        // ========================================================================================
        $display("------------------------------ (%6d ns) Section 2: R-type instructions", $time());
        perform_rst();

        begin : sec2_rtype
            automatic logic [31:0] prog [$];

            // x2 = 60, x3 = 15, x4 = -1 (0xFFFF_FFFF)
            prog.push_back(LUI  (X1, 20'h0001_0));
            prog.push_back(ADDI (X2, X0, 12'd60));
            prog.push_back(ADDI (X3, X0, 12'd15));
            prog.push_back(ADDI (X4, X0, 12'hFFF));     // -1

            prog.push_back(ADD  (X5,  X2, X3));          // 75
            prog.push_back(SUB  (X6,  X2, X3));          // 45
            prog.push_back(AND  (X7,  X2, X3));          // 12
            prog.push_back(OR   (X8,  X2, X3));          // 63
            prog.push_back(XOR  (X9,  X2, X3));          // 51
            prog.push_back(SLL  (X10, X3, X3));          // 15 << 15 = 491520
            prog.push_back(SRL  (X10, X10, X3));         // 491520 >> 15 = 15
            prog.push_back(SRA  (X11, X4, X3));          // -1 >>> 15 = -1
            prog.push_back(SLT  (X5,  X4, X3));          // -1 <s 15  → 1
            prog.push_back(SLTU (X6,  X4, X3));          // 0xFFFF_FFFF <u 15 → 0

            prog.push_back(SW(X1, X5,  12'd0));
            prog.push_back(SW(X1, X6,  12'd4));
            prog.push_back(SW(X1, X7,  12'd8));
            prog.push_back(SW(X1, X8,  12'd12));
            prog.push_back(SW(X1, X9,  12'd16));
            prog.push_back(SW(X1, X10, 12'd20));
            prog.push_back(SW(X1, X11, 12'd24));

            load_program(prog);
            run_cycles(80);

            prove_dmem(RES + 0,  32'd1);
            prove_dmem(RES + 4,  32'd0);
            prove_dmem(RES + 8,  32'd12);
            prove_dmem(RES + 12, 32'd63);
            prove_dmem(RES + 16, 32'd51);
            prove_dmem(RES + 20, 32'd15);
            prove_dmem(RES + 24, 32'hFFFF_FFFF);
        end

        // ========================================================================================
        // Section 3 – Load / Store
        // ========================================================================================
        $display("------------------------------ (%6d ns) Section 3: Load / Store", $time());
        perform_rst();

        begin : sec3_ldst
            automatic logic [31:0] prog [$];

            prog.push_back(LUI  (X1, 20'h0001_0));

            // Build 0xFFFF_FFFF in x4
            prog.push_back(ADDI (X2, X0, 12'hFFF));     // x2 = -1 = 0xFFFF_FFFF
            prog.push_back(SRLI (X2, X2, 5'd16));        // x2 = 0x0000_FFFF
            prog.push_back(SLLI (X3, X2, 5'd16));        // x3 = 0xFFFF_0000
            prog.push_back(OR   (X4, X2, X3));            // x4 = 0xFFFF_FFFF

            prog.push_back(SW  (X1, X4, 12'd0));         // dmem[0]  = 0xFFFF_FFFF

            // SB: write 0xAB at byte offset 4
            prog.push_back(ADDI(X5, X0, 12'hAB));
            prog.push_back(SB  (X1, X5, 12'd4));

            // SH: write 0x1234 at byte offset 8
            prog.push_back(ADDI(X6, X0, 12'h123));
            prog.push_back(SLLI(X6, X6, 5'd4));
            prog.push_back(ORI (X6, X6, 12'h4));         // x6 = 0x1234
            prog.push_back(SH  (X1, X6, 12'd8));

            // Loads
            prog.push_back(LW  (X7,  X1, 12'd0));        // 0xFFFF_FFFF
            prog.push_back(LB  (X8,  X1, 12'd4));        // sign-ext(0xAB) = 0xFFFF_FFAB
            prog.push_back(LBU (X9,  X1, 12'd4));        // zero-ext = 0x0000_00AB
            prog.push_back(LH  (X10, X1, 12'd8));        // sign-ext(0x1234) = 0x0000_1234
            prog.push_back(LHU (X11, X1, 12'd8));        // zero-ext = 0x0000_1234

            prog.push_back(SW  (X1, X7,  12'd16));
            prog.push_back(SW  (X1, X8,  12'd20));
            prog.push_back(SW  (X1, X9,  12'd24));
            prog.push_back(SW  (X1, X10, 12'd28));
            prog.push_back(SW  (X1, X11, 12'd32));

            load_program(prog);
            run_cycles(100);

            prove_dmem(RES + 0,  32'hFFFF_FFFF);
            prove_dmem(RES + 16, 32'hFFFF_FFFF);
            prove_dmem(RES + 20, 32'hFFFF_FFAB);
            prove_dmem(RES + 24, 32'h0000_00AB);
            prove_dmem(RES + 28, 32'h0000_1234);
            prove_dmem(RES + 32, 32'h0000_1234);
        end

        // ========================================================================================
        // Section 4 – Branches
        // ========================================================================================
        // Pattern per test:
        //   BRANCH +8             ← if taken, skips the next instruction
        //   SW slot, zero_reg     ← only runs if NOT taken → stores 0
        //   SW slot, one_reg      ← only runs if TAKEN     → stores 1
        // For not-taken tests the stores are swapped so the correct path still stores 1.
        $display("------------------------------ (%6d ns) Section 4: Branch instructions", $time());
        perform_rst();

        begin : sec4_branch
            automatic logic [31:0] prog [$];
            automatic int slot;
            slot = 0;

            prog.push_back(LUI  (X1, 20'h0001_0));
            prog.push_back(ADDI (X2, X0, 12'd10));      // x2 = 10
            prog.push_back(ADDI (X3, X0, 12'd10));      // x3 = 10
            prog.push_back(ADDI (X4, X0, 12'd5));       // x4 =  5
            prog.push_back(ADDI (X5, X0, 12'hFFF));     // x5 = -1
            prog.push_back(ADDI (X6, X0, 12'd0));       // x6 =  0
            prog.push_back(ADDI (X7, X0, 12'd1));       // x7 =  1  (taken marker)

            // BEQ taken  (x2 == x3)
            prog.push_back(BEQ (X2, X3, 12'b0000_0000_1000));
            prog.push_back(SW  (X1, X6, 12'(slot)));    // not-taken → 0
            prog.push_back(SW  (X1, X7, 12'(slot)));    // taken     → 1
            slot += 4;

            // BEQ not-taken  (x2 != x4)
            prog.push_back(BEQ (X2, X4, 12'b0000_0000_1000));
            prog.push_back(SW  (X1, X7, 12'(slot)));    // not-taken → 1 (correct)
            prog.push_back(SW  (X1, X6, 12'(slot)));    // taken     → 0 (wrong)
            slot += 4;

            // BNE taken  (x2 != x4)
            prog.push_back(BNE (X2, X4, 12'b0000_0000_1000));
            prog.push_back(SW  (X1, X6, 12'(slot)));
            prog.push_back(SW  (X1, X7, 12'(slot)));
            slot += 4;

            // BNE not-taken  (x2 == x3)
            prog.push_back(BNE (X2, X3, 12'b0000_0000_1000));
            prog.push_back(SW  (X1, X7, 12'(slot)));
            prog.push_back(SW  (X1, X6, 12'(slot)));
            slot += 4;

            // BLT taken  (-1 <s 5)
            prog.push_back(BLT (X5, X4, 12'b0000_0000_1000));
            prog.push_back(SW  (X1, X6, 12'(slot)));
            prog.push_back(SW  (X1, X7, 12'(slot)));
            slot += 4;

            // BLT not-taken  (5 <s -1 ? No)
            prog.push_back(BLT (X4, X5, 12'b0000_0000_1000));
            prog.push_back(SW  (X1, X7, 12'(slot)));
            prog.push_back(SW  (X1, X6, 12'(slot)));
            slot += 4;

            // BGE taken  (5 >=s -1)
            prog.push_back(BGE (X4, X5, 12'b0000_0000_1000));
            prog.push_back(SW  (X1, X6, 12'(slot)));
            prog.push_back(SW  (X1, X7, 12'(slot)));
            slot += 4;

            // BGE not-taken  (-1 >=s 5 ? No)
            prog.push_back(BGE (X5, X4, 12'b0000_0000_1000));
            prog.push_back(SW  (X1, X7, 12'(slot)));
            prog.push_back(SW  (X1, X6, 12'(slot)));
            slot += 4;

            // BLTU taken  (0 <u 10)
            prog.push_back(BLTU(X6, X2, 12'b0000_0000_1000));
            prog.push_back(SW  (X1, X6, 12'(slot)));
            prog.push_back(SW  (X1, X7, 12'(slot)));
            slot += 4;

            // BLTU not-taken  (0xFFFF_FFFF <u 5 ? No)
            prog.push_back(BLTU(X5, X4, 12'b0000_0000_1000));
            prog.push_back(SW  (X1, X7, 12'(slot)));
            prog.push_back(SW  (X1, X6, 12'(slot)));
            slot += 4;

            // BGEU taken  (0xFFFF_FFFF >=u 5)
            prog.push_back(BGEU(X5, X4, 12'b0000_0000_1000));
            prog.push_back(SW  (X1, X6, 12'(slot)));
            prog.push_back(SW  (X1, X7, 12'(slot)));
            slot += 4;

            // BGEU not-taken  (0 >=u 10 ? No)
            prog.push_back(BGEU(X6, X2, 12'b0000_0000_1000));
            prog.push_back(SW  (X1, X7, 12'(slot)));
            prog.push_back(SW  (X1, X6, 12'(slot)));
            slot += 4;

            load_program(prog);
            run_cycles(150);

            for (int i = 0; i < 12; i++) begin
                prove_dmem(RES + 4*i, 32'd1);
            end
        end

        // ========================================================================================
        // Section 5 – x0 hardwired zero
        // ========================================================================================
        $display("------------------------------ (%6d ns) Section 5: x0 hardwired zero", $time());
        perform_rst();

        begin : sec5_x0
            automatic logic [31:0] prog [$];

            prog.push_back(LUI  (X1, 20'h0001_0));
            prog.push_back(ADDI (X0, X0, 12'hFFF));     // attempt write -1 to x0
            prog.push_back(ADD  (X0, X0, X0));            // attempt again
            prog.push_back(SW   (X1, X0, 12'd0));        // x0 must read as 0

            load_program(prog);
            run_cycles(30);

            prove_dmem(RES, 32'd0);
        end

        // ========================================================================================
        print_test_done();
        $finish();
    end

    // --------------------------------------------------------------------------------------------
    function void print_test_done();
        if (error_count != 0) begin
            $display("\033[0;31m");
            $display("Some test(s) failed! (# Errors: %4d)", error_count);
        end else begin
            $display("\033[0;32m");
            $display("All tests passed! (# Errors: %4d)", error_count);
        end
        $display("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
        $display("!!!!!!!!!!!!!!!!!!!! TEST DONE !!!!!!!!!!!!!!!!!!!!");
        $display("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
        $display("\033[0m");
    endfunction

endmodule