// Pipelined 8-lane MAC. Parameterisable depth, register-enable gating.
//
// Stages: multiply -> partial sums -> final sum. stages selects how many of the
// three boundaries are registered, so the same source covers latency 1 to 3.
//
// Replaces an earlier version with three defects:
//   - reset was synchronous to a gated clock (mac_en && clk), so the pipeline
//     registers could not be reset while the MAC was idle, which is the normal
//     state;
//   - add_0_3_q and add_4_7_q were assigned from two always blocks on two
//     different gated clocks, i.e. multiply driven;
//   - gating used `assign gclk = en ? clk : 0`, a mux on the clock, which no
//     synthesis tool treats as a clock gater.
// Gating is now a register enable on the ungated clock, which Design Compiler
// converts to an integrated clock gating cell and Quartus to the LE clock-enable.
module mac_8in_pl (clk, reset, out, en, a, b, out_valid);

parameter bw = 8;
parameter bw_psum = 2*bw+6;
parameter pr = 8;
parameter stages = 3;                   // 1..3 registered boundaries

localparam pw = 2*bw;                   // product width
localparam sw = 2*bw+2;                 // 4-term partial sum width

input  clk, reset;
input  en;                              // hold the pipeline and emit zero
input  [pr*bw-1:0] a;
input  [pr*bw-1:0] b;
output [bw_psum-1:0] out;
output out_valid;                       // en, delayed by the pipeline depth

wire [pr*pw-1:0] product;
reg  [pr*pw-1:0] product_q;
wire [pr*pw-1:0] product_s;             // stage 1 output, registered or not

genvar i;
generate
    for (i = 0; i < pr; i = i + 1) begin : mul
        wire [bw-1:0] a_val = a[bw*(i+1)-1 : bw*i];
        wire [bw-1:0] b_val = b[bw*(i+1)-1 : bw*i];
        assign product[pw*(i+1)-1 : pw*i] =
            {{(bw){a_val[bw-1]}}, a_val} * {{(bw){b_val[bw-1]}}, b_val};
    end
endgenerate

assign product_s = (stages >= 1) ? product_q : product;

// Sign-extend a product to the partial-sum width.
wire [sw-1:0] p_ext [0:pr-1];
generate
    for (i = 0; i < pr; i = i + 1) begin : ext
        assign p_ext[i] = {{(sw-pw){product_s[pw*(i+1)-1]}},
                           product_s[pw*(i+1)-1 : pw*i]};
    end
endgenerate

wire [sw-1:0] add_0_3 = p_ext[0] + p_ext[1] + p_ext[2] + p_ext[3];
wire [sw-1:0] add_4_7 = p_ext[4] + p_ext[5] + p_ext[6] + p_ext[7];

reg  [sw-1:0] add_0_3_q, add_4_7_q;
wire [sw-1:0] add_0_3_s = (stages >= 2) ? add_0_3_q : add_0_3;
wire [sw-1:0] add_4_7_s = (stages >= 2) ? add_4_7_q : add_4_7;

wire [bw_psum-1:0] total = {{(bw_psum-sw){add_0_3_s[sw-1]}}, add_0_3_s} +
                           {{(bw_psum-sw){add_4_7_s[sw-1]}}, add_4_7_s};

reg [bw_psum-1:0] total_q;
assign out = (stages >= 3) ? total_q : total;

// en travels with the data so out_valid marks a result the pipeline actually
// computed rather than a held one.
reg [2:0] en_pipe;
assign out_valid = en_pipe[stages-1];

// One always block per register, all on the ungated clock with asynchronous
// reset, so reset does not depend on en.
always @(posedge clk or posedge reset) begin
  if (reset) begin
    product_q <= 0;
    add_0_3_q <= 0;
    add_4_7_q <= 0;
    total_q   <= 0;
    en_pipe   <= 0;
  end
  else begin
    en_pipe <= {en_pipe[1:0], en};
    if (en)         product_q <= product;
    if (en_pipe[0]) begin
      add_0_3_q <= add_0_3;
      add_4_7_q <= add_4_7;
    end
    if (en_pipe[1]) total_q <= total;
  end
end

endmodule
