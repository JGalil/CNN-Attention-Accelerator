// Created by prof. Mingu Kang @VVIP Lab in UCSD ECE department
// Please do not spread this code without permission 
module mac_col (clk, reset, out, q_in, q_out, i_inst, fifo_wr, o_inst);

parameter bw = 8;
parameter bw_psum = 2*bw+6;
parameter pr = 8;
parameter col_id = 0;

output signed [bw_psum-1:0] out;
input  signed [pr*bw-1:0] q_in;
output signed [pr*bw-1:0] q_out;
input  clk, reset;
input  [1:0] i_inst; // [1]: execute, [0]: load 
output [1:0] o_inst; // [1]: execute, [0]: load 
output fifo_wr;
reg    load_ready_q;
reg    [3:0] cnt_q;
reg    [1:0] inst_q;
reg    [1:0] inst_2q;
reg   signed [pr*bw-1:0] query_q;
reg   signed [pr*bw-1:0] key_q;
wire  signed [bw_psum-1:0] psum;

// Gate the clock when incoming instruction and 2 pipeline stages of instruction are 0, then no data is moving
wire is_idle = (i_inst == 2'b00) && (inst_q == 2'b00) && (inst_2q == 2'b00);
// Shut off clock if not useful
wire clk_en = ~is_idle;

// Latch to safely capture clock
reg clk_en_latch;
// When clk is low, latch is transparent, when clk is high, it holds the value
// Makes sure not to miss the first cycle after reset
always @(*) begin
    if (!clk) begin
        clk_en_latch = clk_en;
    end
end

// Safe gated clock
wire g_clk = clk & clk_en_latch;

// Operand isolation
// Prevents comb multiplier from toggling if either operand is 0
wire input_zero  = (query_q == 0);
wire weight_zero = (key_q == 0);

// Generate new mac inputs, if either input is 0, set other one to 0
// If key is already 0, then also set query to 0
// If query is already 0, then also set key to 0
wire signed [pr*bw-1:0] mac_query_in = weight_zero ? {(pr*bw){1'b0}} : query_q;
wire signed [pr*bw-1:0] mac_key_in   = input_zero  ? {(pr*bw){1'b0}} : key_q;



assign o_inst = inst_q;
assign fifo_wr = inst_2q[1];
assign q_out  = query_q;
assign out = psum;

localparam [3:0] cnt_limit = 9 - col_id;

mac_8in #(.bw(bw), .bw_psum(bw_psum), .pr(pr)) mac_8in_instance (
        .a(mac_query_in),  // Used to be query_q
        .b(mac_key_in), // Used to be key_q
	.out(psum)
); 


// Changed to use gated clock
always @ (posedge g_clk or posedge reset) begin
  if (reset) begin
    cnt_q <= 0;
    load_ready_q <= 1;
    inst_q <= 0;
    inst_2q <= 0;
    key_q <= 0;
    query_q <= 0;
  end
  else begin
    inst_q <= i_inst;
    inst_2q <= inst_q;

    // default assignments
    cnt_q <= cnt_q;
    key_q <= key_q;
    query_q <= query_q;
    load_ready_q <= load_ready_q;


    if (inst_q[0]) begin
       query_q <= q_in;
       if (cnt_q == cnt_limit)begin
         cnt_q <= 0;
         key_q <= q_in;
         load_ready_q <= 0;
       end
       else if (load_ready_q) begin
         cnt_q <= cnt_q + 1;
       end
    end
    else if(inst_q[1]) begin
      //out     <= psum;
      query_q <= q_in;
    end
  end
end

endmodule
