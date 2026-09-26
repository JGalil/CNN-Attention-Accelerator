// Created by prof. Mingu Kang @VVIP Lab in UCSD ECE department
// Please do not spread this code without permission 
module mac_col (clk, reset, out, q_in, q_out, i_inst, fifo_wr, o_inst);

parameter bw = 8;
parameter bw_psum = 2*bw+4;
parameter pr = 8;
parameter col_id = 0;
parameter mac_pipeline_latency = 3; // cycles from input to output in mac_8in_pl

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
reg    [1:0] inst_3q;
reg    [1:0] inst_4q;
reg    [1:0] inst_5q;
reg   signed [pr*bw-1:0] query_q;
reg   signed [pr*bw-1:0] key_q;
wire  signed [bw_psum-1:0] psum;

reg signed [bw_psum-1:0] out_q;


assign o_inst = inst_q;
// IF PIPELINING SWITCHING TO 2 + PIPELINE_LATENCY, EX. MAC PIPELINE LATENCY = 4, THEN CHANGE TO inst_4q[1]
assign fifo_wr = inst_5q[1];
assign q_out  = query_q;

// assign out = psum;
assign out = out_q;

localparam [3:0] cnt_limit = 9 - col_id;

reg mac_en;

wire gclk;

integer i;


reg signed [pr*bw-1:0] q_mac_in;

always @ (negedge clk) begin
  mac_en <= (q_in != 0) && (key_q != 0);
end

assign gclk = mac_en ? clk : 0;


always @ (posedge gclk) begin
    if(inst_q[1] | inst_5q[1]) begin
      q_mac_in <= q_in;
    end
end


mac_8in_pl  mac_8in_instance (
  .clk(clk),
  .reset(reset),
  .mac_en(mac_en),
  .a(query_q),
  .b(key_q),
  .out(psum)
);

always @ (posedge clk or posedge reset) begin
  if (reset) begin
    cnt_q <= 0;
    load_ready_q <= 1;
    inst_q <= 0;
    inst_2q <= 0;
    inst_3q <= 0;
    inst_4q <= 0;
    inst_5q <= 0;
    key_q <= 0;
    query_q <= 0;
    out_q <= 0;

  end
  else begin
    inst_q <= i_inst;
    inst_2q <= inst_q;
    inst_3q <= inst_2q;
    inst_4q <= inst_3q;
    inst_5q <= inst_4q;

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
    // IF PIPELINING SWITCHING TO 2 + PIPELINE_LATENCY, EX. MAC PIPELINE LATENCY = 2, THEN CHANGE TO inst_4q[1]
    else if(inst_q[1] | inst_5q[1]) begin

      out_q   <= psum;
      query_q <= q_in;

    end
  end
end

endmodule
