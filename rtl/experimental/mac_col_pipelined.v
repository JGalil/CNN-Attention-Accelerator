// Created by prof. Mingu Kang @VVIP Lab in UCSD ECE department
// Modified: pipelined MAC variant of rtl/mac_col.v
//
// Same interface and gating strategy as rtl/mac_col.v, with mac_8in_pl in place
// of the combinational mac_8in. The output-valid instruction is delayed by the
// pipeline depth so fifo_wr still lines up with the psum it describes.
//
// Not the default: the design is constrained at 10 ns, where the combinational
// MAC closes with large margin, so the extra registers buy nothing. This is
// here for retargeting to a faster clock -- see docs/extensions.md 3.6.
module mac_col (clk, reset, out, q_in, q_out, i_inst, fifo_wr, o_inst, col_active);

parameter bw = 8;
parameter bw_psum = 2*bw+6;
parameter pr = 8;
parameter col_id = 0;
parameter stages = 3;                   // mac_8in_pl pipeline depth

localparam idelay = 2 + stages;         // instruction stages before fifo_wr

output signed [bw_psum-1:0] out;
input  signed [pr*bw-1:0] q_in;
output signed [pr*bw-1:0] q_out;
input  clk, reset;
input  [1:0] i_inst;
output [1:0] o_inst;
output fifo_wr;
output col_active;

reg    load_ready_q;
reg    [3:0] cnt_q;
reg    [1:0] inst_pipe [0:idelay-1];
reg    signed [pr*bw-1:0] query_q;
reg    signed [pr*bw-1:0] key_q;
reg    key_zero_q;
reg    signed [bw_psum-1:0] out_q;
wire   signed [bw_psum-1:0] psum;

localparam [3:0] cnt_limit = 9 - col_id;

wire is_idle = (i_inst == 2'b00) && (inst_pipe[0] == 2'b00) && (inst_pipe[1] == 2'b00);
wire col_en  = ~is_idle;

assign col_active = ~key_zero_q;
assign o_inst     = inst_pipe[0];
assign fifo_wr    = inst_pipe[idelay-1][1];
assign q_out      = query_q;
assign out        = out_q;

wire signed [pr*bw-1:0] mac_query_in = key_zero_q ? {(pr*bw){1'b0}} : query_q;
wire mac_en = col_en && ~key_zero_q;

mac_8in_pl #(.bw(bw), .bw_psum(bw_psum), .pr(pr), .stages(stages)) mac_8in_instance (
        .clk(clk),
        .reset(reset),
        .en(mac_en),
        .a(mac_query_in),
        .b(key_q),
        .out(psum),
        .out_valid()
);

integer k;
always @ (posedge clk or posedge reset) begin
  if (reset) begin
    cnt_q <= 0;
    load_ready_q <= 1;
    key_q <= 0;
    key_zero_q <= 1;
    query_q <= 0;
    out_q <= 0;
    for (k = 0; k < idelay; k = k + 1) inst_pipe[k] <= 0;
  end
  else if (col_en) begin
    inst_pipe[0] <= i_inst;
    for (k = 1; k < idelay; k = k + 1) inst_pipe[k] <= inst_pipe[k-1];

    out_q <= key_zero_q ? {bw_psum{1'b0}} : psum;

    if (inst_pipe[0][0]) begin
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
    else if (inst_pipe[0][1]) begin
      query_q <= q_in;
    end
  end
end

endmodule
