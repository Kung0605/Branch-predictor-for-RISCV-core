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

    // debug signals
    input               debug_single_step_i
);

localparam TBL_WIDTH = $clog2(ENTRY_NUM);
localparam BHR_WIDTH = 4;
localparam BHR_SIZE  = 2**BHR_WIDTH;
reg  [XLEN-1 : 0]      branch_pc_table[ENTRY_NUM-1 : 0];
wire                   we;
wire [XLEN-1 : 0]      predicted_pc;
wire [ENTRY_NUM-1 : 0] addr_hit_PCU;
wire [ENTRY_NUM-1 : 0] addr_hit_DEC;
reg  [TBL_WIDTH-1 : 0] read_addr;
reg  [TBL_WIDTH-1 : 0] write_addr;
reg  [TBL_WIDTH-1 : 0] update_addr;

// two-bit saturating counter
reg  [1: 0]            branch_likelihood[ENTRY_NUM-1 : 0][BHR_SIZE-1:0];

// Simulation register
reg [31:0] branch_miss;
reg [31:0] branch_hit;
reg [31:0] BHT_misses;
reg [31:0] BHT_hits;
wire       BHT_hit;
wire       branch_taken;
wire       branch_misprediction;
// assign branch_taken           = branch_taken_i === 1'bx ? 1 : branch_taken_i;
// assign branch_misprediction   = branch_misprediction_i === 1'bx ? 0 : branch_misprediction_i;
assign branch_taken = branch_taken_i;
assign branch_misprediction = branch_misprediction_i;
// Two-level 
reg [BHR_WIDTH-1:0] branch_history_reg;

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

/* ******************************************************************** *
 *  Mapping example of read_addr/update_addr:                           *
 *     addr_hit_XXX     value   ->  the corresponding address           *
 *       000001           1     ->  0                                   *
 *       000010           2     ->  1                                   *
 *       000100           4     ->  2                                   *
 *       001000           8     ->  3                                   *
 *       010000          16     ->  4                                   *
 *       100000          32     ->  5                                   *
 *  So, we can get the read_addr from log2 function                     *
 * ******************************************************************** */
always @(*)
begin
    case (addr_hit_PCU)
        64'h0000_0000_0000_0002: read_addr <= 1 ;
        64'h0000_0000_0000_0004: read_addr <= 2 ;
        64'h0000_0000_0000_0008: read_addr <= 3 ;
        64'h0000_0000_0000_0010: read_addr <= 4 ;
        64'h0000_0000_0000_0020: read_addr <= 5 ;
        64'h0000_0000_0000_0040: read_addr <= 6 ;
        64'h0000_0000_0000_0080: read_addr <= 7 ;
        64'h0000_0000_0000_0100: read_addr <= 8 ;
        64'h0000_0000_0000_0200: read_addr <= 9 ;
        64'h0000_0000_0000_0400: read_addr <= 10;
        64'h0000_0000_0000_0800: read_addr <= 11;
        64'h0000_0000_0000_1000: read_addr <= 12;
        64'h0000_0000_0000_2000: read_addr <= 13;
        64'h0000_0000_0000_4000: read_addr <= 14;
        64'h0000_0000_0000_8000: read_addr <= 15;
        64'h0000_0000_0001_0000: read_addr <= 16;
        64'h0000_0000_0002_0000: read_addr <= 17;
        64'h0000_0000_0004_0000: read_addr <= 18;
        64'h0000_0000_0008_0000: read_addr <= 19;
        64'h0000_0000_0010_0000: read_addr <= 20;
        64'h0000_0000_0020_0000: read_addr <= 21;
        64'h0000_0000_0040_0000: read_addr <= 22;
        64'h0000_0000_0080_0000: read_addr <= 23;
        64'h0000_0000_0100_0000: read_addr <= 24;
        64'h0000_0000_0200_0000: read_addr <= 25;
        64'h0000_0000_0400_0000: read_addr <= 26;
        64'h0000_0000_0800_0000: read_addr <= 27;
        64'h0000_0000_1000_0000: read_addr <= 28;
        64'h0000_0000_2000_0000: read_addr <= 29;
        64'h0000_0000_4000_0000: read_addr <= 30;
        64'h0000_0000_8000_0000: read_addr <= 31;
        64'h0000_0001_0000_0000: read_addr <= 32;
        64'h0000_0002_0000_0000: read_addr <= 33;
        64'h0000_0004_0000_0000: read_addr <= 34;
        64'h0000_0008_0000_0000: read_addr <= 35;
        64'h0000_0010_0000_0000: read_addr <= 36;
        64'h0000_0020_0000_0000: read_addr <= 37;
        64'h0000_0040_0000_0000: read_addr <= 38;
        64'h0000_0080_0000_0000: read_addr <= 39;
        64'h0000_0100_0000_0000: read_addr <= 40;
        64'h0000_0200_0000_0000: read_addr <= 41;
        64'h0000_0400_0000_0000: read_addr <= 42;
        64'h0000_0800_0000_0000: read_addr <= 43;
        64'h0000_1000_0000_0000: read_addr <= 44;
        64'h0000_2000_0000_0000: read_addr <= 45;
        64'h0000_4000_0000_0000: read_addr <= 46;
        64'h0000_8000_0000_0000: read_addr <= 47;
        64'h0001_0000_0000_0000: read_addr <= 48;
        64'h0002_0000_0000_0000: read_addr <= 49;
        64'h0004_0000_0000_0000: read_addr <= 50;
        64'h0008_0000_0000_0000: read_addr <= 51;
        64'h0010_0000_0000_0000: read_addr <= 52;
        64'h0020_0000_0000_0000: read_addr <= 53;
        64'h0040_0000_0000_0000: read_addr <= 54;
        64'h0080_0000_0000_0000: read_addr <= 55;
        64'h0100_0000_0000_0000: read_addr <= 56;
        64'h0200_0000_0000_0000: read_addr <= 57;
        64'h0400_0000_0000_0000: read_addr <= 58;
        64'h0800_0000_0000_0000: read_addr <= 59;
        64'h1000_0000_0000_0000: read_addr <= 60;
        64'h2000_0000_0000_0000: read_addr <= 61;
        64'h4000_0000_0000_0000: read_addr <= 62;
        64'h8000_0000_0000_0000: read_addr <= 63;
        default:       read_addr <= 0;  //32'h0000_0001
    endcase
end

always @(*)
begin
    case (addr_hit_DEC)
        64'h0000_0000_0000_0002: update_addr <= 1 ;
        64'h0000_0000_0000_0004: update_addr <= 2 ;
        64'h0000_0000_0000_0008: update_addr <= 3 ;
        64'h0000_0000_0000_0010: update_addr <= 4 ;
        64'h0000_0000_0000_0020: update_addr <= 5 ;
        64'h0000_0000_0000_0040: update_addr <= 6 ;
        64'h0000_0000_0000_0080: update_addr <= 7 ;
        64'h0000_0000_0000_0100: update_addr <= 8 ;
        64'h0000_0000_0000_0200: update_addr <= 9 ;
        64'h0000_0000_0000_0400: update_addr <= 10;
        64'h0000_0000_0000_0800: update_addr <= 11;
        64'h0000_0000_0000_1000: update_addr <= 12;
        64'h0000_0000_0000_2000: update_addr <= 13;
        64'h0000_0000_0000_4000: update_addr <= 14;
        64'h0000_0000_0000_8000: update_addr <= 15;
        64'h0000_0000_0001_0000: update_addr <= 16;
        64'h0000_0000_0002_0000: update_addr <= 17;
        64'h0000_0000_0004_0000: update_addr <= 18;
        64'h0000_0000_0008_0000: update_addr <= 19;
        64'h0000_0000_0010_0000: update_addr <= 20;
        64'h0000_0000_0020_0000: update_addr <= 21;
        64'h0000_0000_0040_0000: update_addr <= 22;
        64'h0000_0000_0080_0000: update_addr <= 23;
        64'h0000_0000_0100_0000: update_addr <= 24;
        64'h0000_0000_0200_0000: update_addr <= 25;
        64'h0000_0000_0400_0000: update_addr <= 26;
        64'h0000_0000_0800_0000: update_addr <= 27;
        64'h0000_0000_1000_0000: update_addr <= 28;
        64'h0000_0000_2000_0000: update_addr <= 29;
        64'h0000_0000_4000_0000: update_addr <= 30;
        64'h0000_0000_8000_0000: update_addr <= 31;
        64'h0000_0001_0000_0000: update_addr <= 32;
        64'h0000_0002_0000_0000: update_addr <= 33;
        64'h0000_0004_0000_0000: update_addr <= 34;
        64'h0000_0008_0000_0000: update_addr <= 35;
        64'h0000_0010_0000_0000: update_addr <= 36;
        64'h0000_0020_0000_0000: update_addr <= 37;
        64'h0000_0040_0000_0000: update_addr <= 38;
        64'h0000_0080_0000_0000: update_addr <= 39;
        64'h0000_0100_0000_0000: update_addr <= 40;
        64'h0000_0200_0000_0000: update_addr <= 41;
        64'h0000_0400_0000_0000: update_addr <= 42;
        64'h0000_0800_0000_0000: update_addr <= 43;
        64'h0000_1000_0000_0000: update_addr <= 44;
        64'h0000_2000_0000_0000: update_addr <= 45;
        64'h0000_4000_0000_0000: update_addr <= 46;
        64'h0000_8000_0000_0000: update_addr <= 47;
        64'h0001_0000_0000_0000: update_addr <= 48;
        64'h0002_0000_0000_0000: update_addr <= 49;
        64'h0004_0000_0000_0000: update_addr <= 50;
        64'h0008_0000_0000_0000: update_addr <= 51;
        64'h0010_0000_0000_0000: update_addr <= 52;
        64'h0020_0000_0000_0000: update_addr <= 53;
        64'h0040_0000_0000_0000: update_addr <= 54;
        64'h0080_0000_0000_0000: update_addr <= 55;
        64'h0100_0000_0000_0000: update_addr <= 56;
        64'h0200_0000_0000_0000: update_addr <= 57;
        64'h0400_0000_0000_0000: update_addr <= 58;
        64'h0800_0000_0000_0000: update_addr <= 59;
        64'h1000_0000_0000_0000: update_addr <= 60;
        64'h2000_0000_0000_0000: update_addr <= 61;
        64'h4000_0000_0000_0000: update_addr <= 62;
        64'h8000_0000_0000_0000: update_addr <= 63;
        default:       update_addr <= 0;  //32'h0000_0001
    endcase
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
integer jdx;
always @(posedge clk_i)
begin
    if (rst_i)
    begin
        for (idx = 0; idx < ENTRY_NUM; idx = idx + 1) begin 
            for (jdx = 0; jdx < BHR_SIZE; jdx = jdx + 1)
                branch_likelihood[idx][jdx] <= 2'b01;
        end 
    end
    else if (stall_i)
    begin
        for (idx = 0; idx < ENTRY_NUM; idx = idx + 1) begin 
            for (jdx = 0; jdx < BHR_SIZE; jdx = jdx + 1)
                branch_likelihood[idx][jdx] <= branch_likelihood[idx][jdx];
        end
    end
    else
    begin
        if (we) // Execute the branch instruction for the first time.
        begin
            branch_likelihood[write_addr][branch_history_reg] <= {branch_taken, branch_taken};
        end
        else if (exe_is_branch_i)
        begin
            case (branch_likelihood[update_addr][branch_history_reg])
                2'b00:  // strongly not taken
                    if (branch_taken)
                        branch_likelihood[update_addr][branch_history_reg] <= 2'b01;
                    else
                        branch_likelihood[update_addr][branch_history_reg] <= 2'b00;
                2'b01:  // weakly not taken
                    if (branch_taken)
                        branch_likelihood[update_addr][branch_history_reg] <= 2'b10;
                    else
                        branch_likelihood[update_addr][branch_history_reg] <= 2'b00;
                2'b10:  // weakly taken
                    if (branch_taken)
                        branch_likelihood[update_addr][branch_history_reg] <= 2'b11;
                    else
                        branch_likelihood[update_addr][branch_history_reg] <= 2'b01;
                2'b11:  // strongly taken
                    if (branch_taken)
                        branch_likelihood[update_addr][branch_history_reg] <= 2'b11;
                    else
                        branch_likelihood[update_addr][branch_history_reg] <= 2'b10;
            endcase
        end
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


// Two-level 
always @(posedge clk_i) begin 
    if (rst_i)
        branch_history_reg <= 0;
    else 
        branch_history_reg <= {branch_history_reg[BHR_WIDTH-2:0], branch_taken};
end

assign branch_hit_o = ( | addr_hit_PCU) & ( | pc_i);
assign branch_target_addr_o = {32{( | addr_hit_PCU)}} & predicted_pc;
assign branch_decision_o = ( branch_likelihood[read_addr][branch_history_reg][1] );

always @(posedge clk_i) begin
    if (rst_i) begin 
        branch_hit  <= 0;
        branch_miss <= 0;
    end
    else if (~stall_i && exe_is_branch_i && is_cond_branch_i) begin 
        branch_hit  <= branch_hit  + !branch_misprediction;
        branch_miss <= branch_miss + branch_misprediction;
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
