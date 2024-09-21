`timescale 1ns / 1ps 

`include "aquila_config.vh"

module bpu #( parameter ENTRY_NUM = 64, parameter XLEN = 32 )
(
    // System signals
    input               clk_i,
    input               rst_i,
    input               stall_i,

    // from Program_Counter
    input  [XLEN-1 : 0] pc_i,

    // from Decode
    input               is_jal_i,
    input               is_cond_branch_i,
    input  [XLEN-1 : 0] dec_pc_i,

    // from Execute
    input               exe_is_branch_i,
    input               branch_taken_i,
    input               branch_misprediction_i,
    input  [XLEN-1 : 0] branch_target_addr_i,

    // to Program_Counter
    output              branch_hit_o,
    output              branch_decision_o,
    output [XLEN-1 : 0] branch_target_addr_o,

    input               debug_single_step_i
);

localparam TBL_WIDTH = $clog2(ENTRY_NUM);

reg  [XLEN-1 : 0]      branch_pc_table[ENTRY_NUM-1 : 0];
wire                   we;
wire [XLEN-1 : 0]      predicted_pc;
wire [ENTRY_NUM-1 : 0] addr_hit_PCU;
wire [ENTRY_NUM-1 : 0] addr_hit_DEC;
reg  [TBL_WIDTH-1 : 0] write_addr;     // write address for pc_table(branch target buffer)

// Simulation register
reg [31:0] branch_miss;
reg [31:0] branch_hit;
reg [31:0] BHT_misses;
reg [31:0] BHT_hits;
wire       BHT_hit;
// "we" is enabled to add a new entry to the BPU table when
// the decoder sees a branch instruction for the first time.
// CY Hsiang 0220_2020: added "~stall_i" to "we ="
assign we = ~stall_i & (is_cond_branch_i | is_jal_i) & ~(|addr_hit_DEC);

`ifdef DEBUG 
wire debug_addr_PCU = (pc_i[XLEN-1:XLEN-8] == 8'hCD);
wire debug_addr_DEC = (pc_i[XLEN-1:XLEN-8] == 8'hCD);
genvar i;
generate
    for (i = 0; i < ENTRY_NUM; i = i + 1)
    begin
        assign addr_hit_PCU[i] = (debug_addr_PCU || debug_single_step_i) ? 0 : (branch_pc_table[i] == pc_i);
        assign addr_hit_DEC[i] = (debug_addr_DEC || debug_single_step_i) ? 0 : (branch_pc_table[i] == dec_pc_i);
    end
endgenerate
`else
genvar i;
generate
    for (i = 0; i < ENTRY_NUM; i = i + 1)
    begin
        assign addr_hit_PCU[i] = (branch_pc_table[i] == pc_i);
        assign addr_hit_DEC[i] = (branch_pc_table[i] == dec_pc_i);
    end
endgenerate
`endif

always @(posedge clk_i)
begin
    if (rst_i)
    begin
        write_addr <= 0;
    end
    else if (stall_i)
    begin
        write_addr <= write_addr;
    end
    else if (we)
    begin
        write_addr <= (write_addr == (ENTRY_NUM - 1)) ? 0 : write_addr + 1;
    end
end

integer idx;
always @(posedge clk_i)
begin
    if (rst_i)
    begin
        for (idx = 0; idx < ENTRY_NUM; idx = idx + 1)
            branch_pc_table[idx] <= 0;
    end
    else if (stall_i)
    begin
        for (idx = 0; idx < ENTRY_NUM; idx = idx + 1)
            branch_pc_table[idx] <= branch_pc_table[idx];
    end
    else if (we)
    begin
        branch_pc_table[write_addr] <= dec_pc_i;
    end
end

// ===========================================================================
//  Branch PC histroy table.
//
distri_ram #(.ENTRY_NUM(ENTRY_NUM), .XLEN(XLEN))
bpu_pc_history(
    .clk_i(clk_i),
    .we_i(we),                     // Enabled when the instruction at Decode.
    .write_addr_i(write_addr),     // Write addr for the instruction at Decode.
    .read_addr_i(read_addr),       // Read addr for Fetch.
    .data_i(branch_target_addr_i), // Valid at the next cycle (instr. at Execute).
    .data_o(predicted_pc)          // Combinational read data (same cycle at Fetch).
);

// ===========================================================================
//  Outputs signals
//
assign branch_hit_o = ( | addr_hit_PCU) & ( | pc_i);
assign branch_target_addr_o = {32{( | addr_hit_PCU)}} & predicted_pc;
assign branch_decision_o = 0;

always @(posedge clk_i) begin
    if (rst_i) begin 
        branch_hit  <= 0;
        branch_miss <= 0;
    end
    else if (~stall_i && exe_is_branch_i && is_cond_branch_i) begin 
        branch_hit  <= branch_hit  + !branch_misprediction_i;
        branch_miss <= branch_miss + branch_misprediction_i;
    end
    else begin 
        branch_hit  <= branch_hit;
        branch_miss <= branch_miss;
    end
end

always @(posedge clk_i) begin 
    if (rst_i) begin 
        BHT_misses <= 0;
        BHT_hits   <= 0;
    end
    else begin
        BHT_misses <= BHT_misses + we;
        BHT_hits   <= BHT_hits   + BHT_hit;
    end
end

assign BHT_hit = ~stall_i & (is_cond_branch_i | is_jal_i) & (|addr_hit_DEC);
endmodule