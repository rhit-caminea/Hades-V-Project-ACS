/* Copyright (c) 2024 Tobias Scheipel, David Beikircher, Florian Riedl
 * Embedded Architectures & Systems Group, Graz University of Technology
 * SPDX-License-Identifier: MIT
 * ---------------------------------------------------------------------
 * File: fetch_stage.sv
 */



module fetch_stage (
    input logic clk,
    input logic rst,

    // Memory interface
    wishbone_interface.master wb,

    //  Output data
    output logic [31:0] instruction_reg_out,
    output logic [31:0] program_counter_reg_out,

    // Pipeline control
    output pipeline_status::forwards_t  status_forwards_out,
    input  pipeline_status::backwards_t status_backwards_in,
    input  logic [31:0] jump_address_backwards_in
);

    // DONE: Delete the following line and implement this module.
    //ref_fetch_stage golden(.*);

    always ff @(posedge clk or posedge rst) begin
        if(rst) begin
            instruction_reg_out <= constants::RESET_ADDRESS; //determined by constants in /defines/constants.sv
            next_program_counter_reg_out <= constants::MEMORY_START;
            status_forwards_out <= pipeline_status::forwards_t::VALID;
    end else begin
        if(status_backwards_in == pipeline_status::backwards_t::VALID) begin
        //implement fetch logic here: handling wishbone interface, updating
        // the program counter, and managing pipeline control signals
    end

endmodule
