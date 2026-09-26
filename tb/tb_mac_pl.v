`timescale 1ns/1ps
// Checks mac_8in_pl against the combinational mac_8in for every supported
// pipeline depth, including the gated (en low) path and reset while idle.
module tb_mac_pl;
  parameter bw = 8, bw_psum = 2*bw+6, pr = 8;

  reg clk = 0, reset = 1, en = 0;
  reg [pr*bw-1:0] a, b;
  integer errors = 0, i, s;

  wire [bw_psum-1:0] ref_out;
  mac_8in #(.bw(bw), .bw_psum(bw_psum), .pr(pr)) ref_mac (.a(a), .b(b), .out(ref_out));

  // One instance per depth; only the matching one is checked at a time.
  wire [bw_psum-1:0] o1, o2, o3;
  wire v1, v2, v3;
  mac_8in_pl #(.bw(bw), .bw_psum(bw_psum), .pr(pr), .stages(1)) p1
    (.clk(clk), .reset(reset), .en(en), .a(a), .b(b), .out(o1), .out_valid(v1));
  mac_8in_pl #(.bw(bw), .bw_psum(bw_psum), .pr(pr), .stages(2)) p2
    (.clk(clk), .reset(reset), .en(en), .a(a), .b(b), .out(o2), .out_valid(v2));
  mac_8in_pl #(.bw(bw), .bw_psum(bw_psum), .pr(pr), .stages(3)) p3
    (.clk(clk), .reset(reset), .en(en), .a(a), .b(b), .out(o3), .out_valid(v3));

  always #0.5 clk = ~clk;

  reg [bw_psum-1:0] expect_q [0:3];     // reference delayed by pipeline depth

  task check(input integer stage, input [bw_psum-1:0] got, input valid);
    begin
      if (valid && got !== expect_q[stage]) begin
        if (errors < 8)
          $display("  FAIL stages=%0d: expected %0d, got %0d", stage, expect_q[stage], got);
        errors = errors + 1;
      end
    end
  endtask

  // Shift the reference through a matching delay line.
  always @(posedge clk) begin
    if (!reset && en) begin
      expect_q[1] <= ref_out;
      expect_q[2] <= expect_q[1];
      expect_q[3] <= expect_q[2];
    end
  end

  initial begin
    repeat (3) @(negedge clk);
    reset = 0;
    @(negedge clk); en = 1;

    for (i = 0; i < 600; i = i + 1) begin
      @(negedge clk);
      a = {$random, $random};
      b = {$random, $random};
      @(posedge clk);
      #0.1;
      check(1, o1, v1); check(2, o2, v2); check(3, o3, v3);
    end

    // Gated: outputs must hold, and out_valid must fall.
    @(negedge clk); en = 0;
    repeat (5) @(posedge clk);
    #0.1;
    if (v1 || v2 || v3) begin
      $display("  FAIL: out_valid still asserted while gated");
      errors = errors + 1;
    end

    // Reset while idle must clear the pipeline; the old version could not.
    @(negedge clk); reset = 1;
    repeat (2) @(posedge clk);
    #0.1;
    if (o1 !== 0 || o2 !== 0 || o3 !== 0) begin
      $display("  FAIL: reset while gated did not clear the pipeline (%0d %0d %0d)", o1, o2, o3);
      errors = errors + 1;
    end

    $display("tb_mac_pl: %0d errors", errors);
    $finish;
  end
endmodule
