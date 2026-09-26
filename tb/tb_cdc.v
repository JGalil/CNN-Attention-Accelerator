`timescale 1ns/1ps
// Exercises async_gray_fifo across genuinely independent clocks: every word
// written must be read back exactly once, in order, with no loss, duplication or
// corruption, and the full/empty flags must never be violated.
//
// fullchip tied both cores to one clock, so this logic was never previously run
// in the condition it exists for.
//
// Note on the sync_mb reset bug this was written to chase: that reset branch had
// no effect, but the fault is masked in this FIFO and these cases do not
// distinguish the two versions. The synchronised value is a gray pointer that is
// itself reset to zero by the same reset, so the two-stage pipeline flushes to
// zero within two cycles either way. The fix is still required -- the code as
// written claims a reset it does not perform, and the masking is a property of
// the caller, not of sync_mb.
module tb_cdc;
  parameter BW = 24, ADDR = 3, DEPTH = 1 << ADDR;
  parameter N = 2000;                   // words per ratio

  reg wr_clk = 0, rd_clk = 0, rst = 1;
  reg wr_rst_i = 1, rd_rst_i = 1;      // independently released, as in real CDC
  wire wr_en, rd_en;
  wire [BW-1:0] wr_data;
  wire [BW-1:0] rd_data;
  wire full, empty;

  integer wr_count, rd_count, errors, ratio_errors, i;
  real wr_period, rd_period;

  // Reference queue, indexed by the write count.
  reg [BW-1:0] model [0:N-1];

  async_gray_fifo #(.bw(BW), .addr(ADDR)) dut (
    .wr_clk(wr_clk), .wr_rst(wr_rst_i), .wr_en(wr_en), .wr_data(wr_data),
    .rd_clk(rd_clk), .rd_rst(rd_rst_i), .rd_en(rd_en), .rd_data(rd_data),
    .empty(empty), .full(full)
  );

  always #(wr_period/2.0) wr_clk = ~wr_clk;
  always #(rd_period/2.0) rd_clk = ~rd_clk;

  // The FIFO is first-word-fall-through: rd_data is the current head and the
  // pointer advances on the edge where rd_en is high, so both handshakes are
  // combinational rather than registered.
  assign wr_en   = !rst && (wr_count < N) && !full;
  assign wr_data = model[wr_count];
  assign rd_en   = !rst && !empty;

  always @(posedge wr_clk)
    if (wr_en) wr_count <= wr_count + 1;

  always @(posedge rd_clk) begin
    if (rd_en) begin
      if (rd_data !== model[rd_count]) begin
        if (ratio_errors < 5)
          $display("  FAIL word %0d: expected %h, got %h", rd_count, model[rd_count], rd_data);
        ratio_errors = ratio_errors + 1;
      end
      rd_count <= rd_count + 1;
    end
  end

  // The pointer scheme must never report both full and empty.
  always @(*) if (!rst && full && empty) begin
    $display("  FAIL: full and empty asserted together");
    errors = errors + 1;
  end

  task run_ratio(input real wp, input real rp, input [127:0] name);
    begin
      wr_period = wp; rd_period = rp;
      rst = 1; wr_rst_i = 1; rd_rst_i = 1;
      wr_count = 0; rd_count = 0; ratio_errors = 0;
      for (i = 0; i < N; i = i + 1) model[i] = {$random} ^ (i << 3);
      repeat (8) @(posedge wr_clk);
      rst = 0; wr_rst_i = 0; rd_rst_i = 0;
      // Run until every word is read, with a generous bound.
      fork : watch
        begin wait (rd_count == N); disable watch; end
        begin #(N * (wp > rp ? wp : rp) * 20); disable watch; end
      join
      if (rd_count != N) begin
        $display("  FAIL %0s: only %0d of %0d words read", name, rd_count, N);
        ratio_errors = ratio_errors + 1;
      end
      errors = errors + ratio_errors;
      $display("  %0s: wr=%0.2fns rd=%0.2fns  %0d words, %0d errors",
               name, wp, rp, rd_count, ratio_errors);
    end
  endtask

  // Reset asserted while the pointers are non-zero, then released on the two
  // domains at different times. A synchroniser that does not actually reset can
  // present a stale pointer here, making the FIFO look non-empty after reset.
  task run_reset_recovery(input real wp, input real rp, input integer stagger);
    begin
      wr_period = wp; rd_period = rp;
      wr_rst_i = 1; rd_rst_i = 1; rst = 1;
      wr_count = 0; rd_count = 0; ratio_errors = 0;
      for (i = 0; i < N; i = i + 1) model[i] = {$random} ^ (i << 3);
      repeat (4) @(posedge wr_clk);
      wr_rst_i = 0; rd_rst_i = 0; rst = 0;

      // advance the pointers part way round, then stop the reader so the
      // pointers are unequal and non-zero
      wait (wr_count >= 5);
      wr_rst_i = 1; rd_rst_i = 1; rst = 1;
      repeat (2) @(posedge wr_clk);

      // release the two domains at different times
      rd_rst_i = 0; rst = 0;
      repeat (stagger) @(posedge rd_clk);
      if (!empty) begin
        $display("  FAIL reset recovery: FIFO not empty after reset (stagger=%0d)", stagger);
        ratio_errors = ratio_errors + 1;
      end
      wr_rst_i = 0;

      wr_count = 0; rd_count = 0;
      fork : watch2
        begin wait (rd_count == N); disable watch2; end
        begin #(N * (wp > rp ? wp : rp) * 20); disable watch2; end
      join
      if (rd_count != N) begin
        $display("  FAIL reset recovery: only %0d of %0d words read", rd_count, N);
        ratio_errors = ratio_errors + 1;
      end
      errors = errors + ratio_errors;
      $display("  reset recovery (stagger=%0d): %0d words, %0d errors",
               stagger, rd_count, ratio_errors);
    end
  endtask

  initial begin
    errors = 0;
    wr_period = 10.0; rd_period = 10.0;
    $display("async_gray_fifo CDC test");
    run_ratio(10.0,  10.0,  "same freq   ");
    run_ratio(10.0,   3.7,  "read faster ");
    run_ratio( 3.7,  10.0,  "write faster");
    run_ratio(10.0,   9.7,  "near-equal  ");   // worst case for pointer capture
    run_ratio( 7.0,  10.0,  "1:1.43      ");
    run_ratio(10.0,   1.3,  "read 7.7x   ");
    run_reset_recovery(10.0, 3.7, 1);
    run_reset_recovery(10.0, 3.7, 4);
    run_reset_recovery( 3.7, 10.0, 2);
    $display("tb_cdc: %0d errors", errors);
    $finish;
  end
endmodule
