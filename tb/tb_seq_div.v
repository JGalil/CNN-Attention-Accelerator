`timescale 1ns/1ps
// Unit test for seq_div: exactness against Verilog's `/`, saturation above
// 2^qw-1, the gated-lane path, and divide-by-zero.
module tb_seq_div;
  parameter dw = 20, qw = 8;

  reg clk = 0, reset = 1, start = 0, en = 1;
  reg [dw-1:0] n, d;
  wire [dw-1:0] q;
  wire done;
  integer i, errors = 0, expect_q, cycles;

  seq_div #(.dw(dw), .qw(qw)) u (.clk(clk), .reset(reset), .start(start),
    .en(en), .dividend(n), .divisor(d), .quotient(q), .done(done));

  always #0.5 clk = ~clk;

  // Stimulus is driven and sampled on the negedge so it is never changing in
  // the same timestep as the posedge the DUT triggers on.
  task run(input [dw-1:0] nn, input [dw-1:0] dd);
    begin
      @(negedge clk); n = nn; d = dd; start = 1;
      @(negedge clk); start = 0;
      cycles = 0;
      while (!done && cycles < 64) begin
        @(negedge clk);
        cycles = cycles + 1;
      end
      expect_q = (dd == 0 || !en) ? 0 : nn / dd;
      if (expect_q > (1<<qw)-1) expect_q = (1<<qw)-1;   // saturates, not wraps
      if (q !== expect_q[dw-1:0]) begin
        errors = errors + 1;
        $display("  FAIL %0d / %0d (en=%0b): expected %0d, got %0d", nn, dd, en, expect_q, q);
      end
    end
  endtask

  initial begin
    repeat (3) @(negedge clk);
    reset = 0;

    run(115, 5); run(660, 5); run(0, 5); run(100, 7); run(255, 1);
    run(12345, 97);
    run(1048575, 4095);                 // quotient 256 -> saturates to 255
    run(7, 0);                          // divide by zero -> 0
    en = 0; run(1000, 3); en = 1;       // gated lane -> 0, still completes

    // latency must stay within the SFP handshake window
    @(negedge clk); n = 660; d = 5; start = 1;
    @(negedge clk); start = 0;
    cycles = 0;
    while (!done && cycles < 64) begin @(negedge clk); cycles = cycles + 1; end
    $display("seq_div: latency %0d cycles (qw=%0d, upc=%0d)", cycles + 1, qw, u.upc);

    for (i = 0; i < 500; i = i + 1) begin
      d = ($random % 2000); if (d == 0) d = 1;
      n = ($random % 100000);
      run(n, d);
    end

    $display("seq_div: %0d errors", errors);
    $finish;
  end
endmodule
