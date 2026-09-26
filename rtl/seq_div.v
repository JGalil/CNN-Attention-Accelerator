// Sequential restoring divider. Exact integer truncating division, saturating
// at 2^qw-1. Latency qw/upc cycles.
//
// Replaces a combinational `dividend / divisor` that was sampled after a fixed
// counter delay: that form placed a full divider array in the critical path and
// the counter pipelined nothing.
//
// qw is sized from the application bound, not the operand width. In the SFP the
// dividend is one |psum| and the divisor is (row_sum >> 7), where row_sum is the
// sum of all |psum| in the row. Since |psum| <= row_sum the quotient is bounded
// by 128*row_sum/(row_sum-128), under 160 for any row_sum above the skip
// threshold, so 8 bits suffice.
//
// upc trades combinational depth for latency: upc quotient bits are resolved per
// cycle, giving upc chained subtract-compares. upc=2 holds the latency at the
// 4 cycles the previous implementation reported while keeping the path 2 levels
// deep instead of 20.
module seq_div (clk, reset, start, en, dividend, divisor, quotient, done);

parameter dw  = 20;                 // dividend / divisor width
parameter qw  = 8;                  // quotient bits produced
parameter upc = 2;                  // quotient bits resolved per cycle

localparam aw = dw + qw;            // width of the shifted-divisor accumulator

input  clk, reset;
input  start;                       // begin a division; free-runs while held
input  en;                          // low holds the datapath and returns zero
input  [dw-1:0] dividend;
input  [dw-1:0] divisor;
output [dw-1:0] quotient;
output done;                        // one-cycle pulse on completion

reg [aw-1:0] rem;
reg [aw-1:0] dsh;                   // divisor << i, walked down each cycle
reg [qw-1:0] quot;
reg [$clog2(qw+1)-1:0] step;
reg running;
reg done_q;
reg en_q;                           // en latched for the duration of a division

// Combinational per-cycle unroll state.
reg [aw-1:0] rem_t, dsh_t;
reg [qw-1:0] quot_t;
integer k;

// Not reachable through the SFP skip path; defined as a zero quotient rather
// than an all-ones saturation.
wire div_zero = (divisor == 0);

// The control path (running/step/done) runs regardless of en so that every lane
// in an array stays in lockstep and a single done is a valid reference for all
// of them. Only the wide datapath (rem/dsh/quot, ~36 flops and the subtractor)
// is gated, which is where the power is.
wire dp_en = en && !div_zero;

assign quotient = {{(dw-qw){1'b0}}, quot};
assign done     = done_q;

always @(posedge clk or posedge reset) begin
  if (reset) begin
    rem     <= 0;
    dsh     <= 0;
    quot    <= 0;
    step    <= 0;
    running <= 0;
    done_q  <= 0;
    en_q    <= 0;
  end
  else if (start && !running) begin
    step    <= qw;
    running <= 1;
    done_q  <= 0;
    en_q    <= dp_en;
    quot    <= 0;
    if (dp_en) begin
      rem <= {{qw{1'b0}}, dividend};
      dsh <= {1'b0, divisor, {(qw-1){1'b0}}};
    end
  end
  else if (running) begin
    if (en_q) begin
      rem_t  = rem;
      dsh_t  = dsh;
      quot_t = quot;
      for (k=0; k<upc; k=k+1) begin
        quot_t = quot_t << 1;
        if (rem_t >= dsh_t) begin
          rem_t  = rem_t - dsh_t;
          quot_t = quot_t | {{(qw-1){1'b0}}, 1'b1};
        end
        dsh_t = dsh_t >> 1;
      end
      rem  <= rem_t;
      dsh  <= dsh_t;
      quot <= quot_t;
    end
    step <= step - upc;
    if (step == upc) begin
      running <= 0;
      done_q  <= 1;
    end
  end
  else begin
    done_q <= 0;
  end
end

endmodule
