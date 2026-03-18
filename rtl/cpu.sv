/* Copyright (c) 2024 Tobias Scheipel, David Beikircher, Florian Riedl
 * Embedded Architectures & Systems Group, Graz University of Technology
 * SPDX-License-Identifier: MIT
 * ---------------------------------------------------------------------
 * File: cpu.sv
 */






module cpu (
    input logic clk,
    input logic rst,


    wishbone_interface.master memory_fetch_port,
    wishbone_interface.master memory_mem_port,


    input logic external_interrupt_in,
    input logic timer_interrupt_in
);


    // DONE: Delete the following line and implement this module.
    //ref_cpu golden(.*);


    //--------- STAGES ---------
    //FETCH STAGE
    logic [31:0] instruction_fetch_out; // WIRE --> output of the fetch stage, input to the decode stage
    logic [31:0] pc_fetch_out;
    logic status_forwards_fetch_out;


    logic status_backwards_fetch_in;
    logic [31:0] jump_address_fetch_in;


    //DECODE STAGE
    logic [31:0] instruction_decode_in;
    logic [31:0] pc_decode_in;
    logic status_forwards_decode_in;
    logic [31:0] wb_forwarding_decode_in;
    logic [31:0] mem_forwarding_decode_in;
    logic [31:0] exe_forwarding_decode_in;
    logic [31:0] jump_address_decode_in;


    logic statis_backwards_decode_out;
    logic [31:0] jump_address_decode_out;
    logic [31:0] intruction_decode_out;
    logic [31:0] pc_decode_out;
    logic [31:0] rs1_data_decode_out;
    logic [31:0] rs2_data_decode_out
    logic status_forwards_decode_out;
    logic status_backwards_decode_out;


    //EXECUTE STAGE
    logic [31:0] forwarding_execute_out;
    logic status_backwards_execute_out;
    logic [31:0] jump_address_execute_out;
    logic [31:0] instruction_execute_out;
    logic [31:0] pc_execute_out;
    logic [31:0] next_px_execute_out;
    logic [31:0] rd_data_execute_out;
    logic [31:0] source_data_execute_out;
    logic status_forwards_execute_out;


    logic [31:0] instruction_execute_in;
    logic [31:0] pc_execute_in;
    logic [31:0] rs1_data_execute_in;
    logic [31:0] rs2_data_execute_in;
    logic status_forwards_execute_in;
    logic [31:0] jump_address_execute_in;




    //MEMORY STAGE
    logic [31:0] instruction_memory_in;
    logic [31:0] pc_memory_in;
    logic [31:0] next_pc_memory_in;
    logic [31:0] rd_data_memory_in;
    logic [31:0] source_data_memory_in;
    logic [31:0] jump_address_memory_in;
    logic status_forwards_memory_in;
    logic status_backwards_memory_in;
   


    logic [31:0] instruction_memory_out;
    logic [31:0] pc_memory_out;
    logic [31:0] next_pc_memory_out;
    logic [31:0] rd_data_memory_out;
    logic [31:0] source_data_memory_out;
    logic [31:0] jump_address_memory_out;
    logic [31:0] forwarding_memory_out;
    logic status_forwards_memory_out;
    logic status_backwards_memory_out;


    //WRITEBACK STAGE
    logic [31:0] instruction_writeback_in;
    logic [31:0] pc_writeback_in;
    logic [31:0] next_pc_writeback_in;
    logic [31:0] rd_data_writeback_in;
    logic [31:0] source_data_writeback_in;
    logic status_forwards_writeback_in;


    logic [31:0] forwarding_writeback_out;
    logic [31:0] jump_address_writeback_out;
    logic status_backwards_writeback_out;




    //--------- DECLARE MODULES ---------
    fetch_stage fetchStage(
        .clk(clk), //.___ represents the port inside the module, the (name) contains the wire related to the port
        .rst(rst),


        .instruction_reg_out(instruction_fetch_out),
        .program_counter_reg_out(pc_fetch_out),
        .status_forwards_out(status_forwards_fetch_out),
        .status_backwards_in(status_backwards_fetch_in),
        .jump_address_backwards_in(jump_address_fetch),
    );


    decode_stage decodeStage(
        .clk(clk),
        .rst(rst),


        .instruction_in(instruction_decode_in),
        .program_counter_in(pc_decode_in),
        .exe_forwarding_in(exe_forwarding_decode_in),
        .mem_forwarding_in(mem_forwarding_decode_in),
        .wb_forwarding_in(wb_forwarding_decode_in),


        .rs1_data_reg_out(rs1_data_decode_out),
        .rs2_data_reg_out(rs2_data_decode_out),
        .program_counter_reg_out(pc_decode_out),
        .instruction_reg_out(intruction_decode_out),


        .status_forwards_in(status_forwards_decode_in),
        .status_forwards_out(status_forwards_decode_out),
        .status_backwards_in(status_backwards_decode_in),
        .status_backwards_out(status_backwards_decode_out),
        .jump_address_backwards_in(jump_address_decode_in),
        .jump_address_backwards_out(jump_address_decode_out)
    );


    execute_stage executeStage(
        .clk(clk),
        .rst(rst),


        .rs1_data_in(rs1_data_execute_in),
        .rs2_data_in(rs2_data_execute_in),
        .instruction_in(instruction_execute_in),
        .program_counter_in(pc_execute_in),


        .source_data_reg_out(source_data_execute_out),
        .rd_data_reg_out(rd_data_execute_out),
        .instruction_reg_out(instruction_execute_out),
        .program_counter_reg_out(pc_execute_out),
        .next_program_counter_reg_out(next_px_execute_out),
        .forwarding_out(forwarding_execute_out),


        .status_forwards_in(status_forwards_execute_in),
        .status_forwards_out(status_forwards_execute_out),
        .status_backwards_in(),
        .status_backwards_out(status_backwards_execute_out),


        .jump_address_backwards_in(jump_address_execute_in),
        .jump_address_backwards_out(jump_address_execute_out),


    );


    memory_stage memoryStage(
        .clk(clk),
        .rst(rst),


        .source_data_in(source_data_memory_in),
        .rd_data_in(rd_data_memory_in),
        .instruction_in(instruction_memory_in),
        .program_counter_in(pc_memory_in),
        .next_program_counter_in(next_pc_memory_in),
        .source_data_reg_out(source_data_memory_out),
        .rd_data_reg_out(rd_data_memory_out),
        .instruction_reg_out(instruction_memory_out),
        .program_counter_reg_out(pc_memory_out),
        .next_program_counter_reg_out(next_pc_memory_out),
        .forwarding_out(forwarding_memory_out),


        .status_forwards_in(status_forwards_memory_in),
        .status_forwards_out(status_forwards_memory_out),
        .status_backwards_in(status_backwards_memory_out),
        .status_backwards_out(status_backwards_memory_in),
        .jump_address_backwards_in(jump_address_memory_in),
        .jump_address_backwards_out(jump_address_memory_out),


    );


    writeback_stage writebackStage(
        .clk(clk);
        .rst(rst);


        .source_data_in(source_data_writeback_in),
        .rd_data_in(rd_data_writeback_in),
        .instruction_in(instruction_writeback_in),
        .program_counter_in(pc_writeback_in),
        .next_program_counter_in(next_pc_writeback_in),


        .external_interrupt_in(),
        .timer_interrupt_in(),


        .forwarding_out(forwarding_writeback_out),
        .status_forwards_in(status_forwards_writeback_in),
        .status_backwards_out(status_backwards_writeback_out),


        .jump_address_backwards_out(jump_address_writeback_out),


    );


endmodule



