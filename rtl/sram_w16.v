// Created by prof. Mingu Kang @VVIP Lab in UCSD ECE department
// Modified: inferable 16-entry memory in place of a reset flop array
//
// 16 x sram_bit single-port memory, registered read.
//
// The array carries no reset. An asynchronous reset on the storage blocks RAM
// inference, which previously forced 16 x sram_bit flops plus a 16-way mux --
// 2560 flops for the 160-bit psum memory alone. Without it the array maps to
// block RAM on FPGA and to a compiled macro or latch array on ASIC. The reset
// port is retained for interface compatibility and clears only the output
// register, which is all a memory can meaningfully reset.
module sram_w16 (CLK, D, Q, CEN, WEN, A, reset);

  parameter sram_bit = 128;
  parameter depth    = 16;
  parameter aw       = 4;

  input  CLK;
  input  WEN;                           // active low
  input  CEN;                           // active low chip enable
  input  [sram_bit-1:0] D;
  input  [aw-1:0] A;
  input  reset;
  output [sram_bit-1:0] Q;

  reg [sram_bit-1:0] memory [0:depth-1];
  reg [sram_bit-1:0] Q_reg;

  assign Q = Q_reg;

  wire read  = !CEN &&  WEN;
  wire write = !CEN && !WEN;

  always @(posedge CLK) begin
    if (write)
      memory[A] <= D;
  end

  always @(posedge CLK or posedge reset) begin
    if (reset)
      Q_reg <= 0;
    else if (read)
      Q_reg <= memory[A];
  end

endmodule
