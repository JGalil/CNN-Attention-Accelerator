// Created by prof. Mingu Kang @VVIP Lab in UCSD ECE department
// Modified: register enable in place of a hand-rolled gated clock, operand
// isolation on the streaming operand only, registered weight-zero flag,
// whole-column bypass for zero weight vectors.
module mac_col (clk, reset, out, q_in, q_out, i_inst, fifo_wr, o_inst, col_active);

parameter bw = 8;
parameter bw_psum = 2*bw+6;
parameter pr = 8;
parameter col_id = 0;

output signed [bw_psum-1:0] out;
input  signed [pr*bw-1:0] q_in;
output signed [pr*bw-1:0] q_out;
input  clk, reset;
input  [1:0] i_inst;            // [1]: execute, [0]: load
output [1:0] o_inst;
output fifo_wr;
output col_active;              // low when this column holds an all-zero weight vector

reg    load_ready_q;
reg    [3:0] cnt_q;
reg    [1:0] inst_q;
reg    [1:0] inst_2q;
reg    signed [pr*bw-1:0] query_q;
reg    signed [pr*bw-1:0] key_q;
reg    key_zero_q;
wire   signed [bw_psum-1:0] psum;

localparam [3:0] cnt_limit = 9 - col_id;

// Register enable. Expressed as a data enable rather than a gated clock so that
// Design Compiler (compile_ultra -gate_clock) infers an integrated clock-gating
// cell and Quartus infers the LE register clock-enable. A hand-built
// "clk & en" is not recognised as a gater by either, is charged as a
// high-fanout combinational net by the power engines, and on an FPGA lands on
// routing that cannot meet skew.
wire is_idle  = (i_inst == 2'b00) && (inst_q == 2'b00) && (inst_2q == 2'b00);
wire col_en   = ~is_idle;

// key_zero_q is registered at load time rather than recomputed from key_q every
// cycle: key_q is the stationary operand and only changes on a weight load.
assign col_active = ~key_zero_q;

// Operand isolation on the streaming operand only. Gating the stationary
// operand with the streaming operand's zero flag measured as 85% more activity
// on key_q, since it turns a near-static bus into a toggling one.
wire signed [pr*bw-1:0] mac_query_in = key_zero_q ? {(pr*bw){1'b0}} : query_q;

// A column holding an all-zero weight vector contributes nothing for as long as
// those weights are loaded, so its product is forced to zero at the source
// rather than computed and discarded.
assign out = key_zero_q ? {bw_psum{1'b0}} : psum;

assign o_inst  = inst_q;
assign fifo_wr = inst_2q[1];
assign q_out   = query_q;

mac_8in #(.bw(bw), .bw_psum(bw_psum), .pr(pr)) mac_8in_instance (
        .a(mac_query_in),
        .b(key_q),
        .out(psum)
);

always @ (posedge clk or posedge reset) begin
  if (reset) begin
    cnt_q <= 0;
    load_ready_q <= 1;
    inst_q <= 0;
    inst_2q <= 0;
    key_q <= 0;
    key_zero_q <= 1;
    query_q <= 0;
  end
  else if (col_en) begin
    inst_q <= i_inst;
    inst_2q <= inst_q;

    if (inst_q[0]) begin
       query_q <= q_in;
       if (cnt_q == cnt_limit) begin
         cnt_q <= 0;
         key_q <= q_in;
         key_zero_q <= (q_in == 0);
         load_ready_q <= 0;
       end
       else if (load_ready_q) begin
         cnt_q <= cnt_q + 1;
       end
    end
    else if (inst_q[1]) begin
      query_q <= q_in;
    end
  end
end

endmodule
