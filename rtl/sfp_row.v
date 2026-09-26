// Created by prof. Mingu Kang @VVIP Lab in UCSD ECE department
// Modified: sequential dividers, runtime skip threshold, per-lane gating.
//
// Normalises a row of partial sums by the L1 norm of the row taken across both
// cores. Rows whose norm falls below skip_thresh are emitted as zero without
// running the dividers.
module sfp_row (clk, acc, div, div_done, fifo_ext_rd, sum_in, sum_out,
                sfp_in, sfp_out, reset, skip_thresh, row_valid);

  parameter col = 8;
  parameter bw = 8;
  parameter bw_psum = 2*bw+4;
  parameter qw = 8;                     // quotient bits; see seq_div

  input  clk, div, acc, fifo_ext_rd;
  input  reset;
  input  row_valid;                     // a new row's psum is stable on sfp_in
  input  [bw_psum+3:0] sum_in;
  input  [bw_psum+3:0] skip_thresh;     // runtime accuracy/power knob
  input  [col*bw_psum-1:0] sfp_in;
  output [col*bw_psum-1:0] sfp_out;
  output [bw_psum+3:0] sum_out;
  output div_done;

  wire [col*bw_psum-1:0] abs;
  wire [bw_psum+3:0] abs_ext [0:col-1];  // zero-extended, for the row sum
  wire [col*bw_psum-1:0] quotient_flat;
  wire [col-1:0] done;
  wire [col-1:0] lane_en;

  reg  [col*bw_psum-1:0] sfp_out_q;
  reg  [bw_psum+3:0] sum_q;
  reg  div_q;
  reg  fifo_wr;

  reg  busy;                            // one division in flight
  reg  res_valid;                       // sfp_out_q corresponds to the current row
  reg  done_pulse;                      // single-cycle completion
  reg  row_skipped;                     // this row took the skip path

  wire [bw_psum+3:0] sum_this_core;
  wire [bw_psum+3:0] row_norm = sum_this_core + sum_in;
  wire [bw_psum-1:0] divisor  = row_norm >> 7;

  wire skip = (row_norm < skip_thresh);

  // One division per row. res_valid is cleared when a new row arrives and set
  // when its result is captured, so need_div is asserted exactly once per row
  // and the dividers cannot restart on stale data.
  wire need_div  = div_q && !res_valid && !busy;
  wire start_div = need_div && !skip;

  assign sfp_out  = sfp_out_q;

  // A single-cycle pulse: div_done also advances the row-norm FIFOs, which must
  // step once per row, and it marks sfp_out_q as this row's result.
  assign div_done = done_pulse;

  // Magnitude of each lane's partial sum.
  genvar i;
  generate
    for (i = 0; i < col; i = i + 1) begin : abs_lane
      wire signed [bw_psum-1:0] v = sfp_in[bw_psum*(i+1)-1 : bw_psum*i];
      assign abs[bw_psum*(i+1)-1 : bw_psum*i] = v[bw_psum-1] ? (~v + 1'b1) : v;

      assign abs_ext[i] = {4'b0, abs[bw_psum*(i+1)-1 : bw_psum*i]};

      // A zero magnitude normalises to zero for any divisor, so the lane's
      // datapath is held rather than computing a known result.
      assign lane_en[i] = ~skip && (abs[bw_psum*(i+1)-1 : bw_psum*i] != 0);

      seq_div #(.dw(bw_psum), .qw(qw)) div_lane (
        .clk(clk),
        .reset(reset),
        .start(start_div),
        .en(lane_en[i]),
        .dividend(abs[bw_psum*(i+1)-1 : bw_psum*i]),
        .divisor(divisor),
        .quotient(quotient_flat[bw_psum*(i+1)-1 : bw_psum*i]),
        .done(done[i])
      );
    end
  endgenerate

  // Row norms for this core: one copy read back locally, one sent to the other
  // core. Both step on div_done, once per row.
  fifo_depth16 #(.bw(bw_psum+4)) fifo_inst_int (
     .rd_clk(clk), .wr_clk(clk), .in(sum_q), .out(sum_this_core),
     .rd(div_done), .wr(fifo_wr), .reset(reset)
  );

  fifo_depth16 #(.bw(bw_psum+4)) fifo_inst_ext (
     .rd_clk(clk), .wr_clk(clk), .in(sum_q), .out(sum_out),
     .rd(fifo_ext_rd), .wr(fifo_wr), .reset(reset)
  );

  // Row L1 norm. Indexing an unpacked array with a loop variable is legal where
  // a variable part-select of a packed vector is not.
  reg [bw_psum+3:0] row_sum_c;
  integer j;
  always @(*) begin
    row_sum_c = 0;
    for (j = 0; j < col; j = j + 1)
      row_sum_c = row_sum_c + abs_ext[j];
  end

  always @ (posedge clk or posedge reset) begin
    if (reset) begin
      fifo_wr    <= 0;
      sfp_out_q  <= 0;
      div_q      <= 0;
      sum_q      <= 0;
      busy       <= 0;
      res_valid  <= 0;
      done_pulse <= 0;
      row_skipped<= 0;
    end
    else begin
      div_q      <= div;
      done_pulse <= 0;

      if (acc) begin
        sum_q   <= row_sum_c;
        fifo_wr <= 1;
      end
      else begin
        fifo_wr <= 0;

        if (row_valid)
          res_valid <= 0;

        if (start_div) begin
          busy <= 1;
        end
        else if (busy && done[0]) begin
          busy        <= 0;
          sfp_out_q   <= quotient_flat;
          res_valid   <= 1;
          done_pulse  <= 1;
          row_skipped <= 0;
        end
        else if (need_div && skip) begin
          sfp_out_q   <= 0;
          res_valid   <= 1;
          done_pulse  <= 1;
          row_skipped <= 1;
        end
      end
    end
  end

endmodule
