// Two-stage synchroniser for gray-coded pointers crossing a clock domain.
// Valid only for gray-coded inputs: the stages resolve metastability per bit but
// do not align bits, so at most one bit may change per source update.
module sync_mb(clk, in, out, reset);

parameter bw = 4;

input  [bw:0] in;
input  clk;
input  reset;
output [bw:0] out;

// Must not be merged or retimed: the settling time between stages is the
// mechanism, not redundant logic.
(* ASYNC_REG = "TRUE", DONT_TOUCH = "TRUE", preserve *) reg [bw:0] int1;
(* ASYNC_REG = "TRUE", DONT_TOUCH = "TRUE", preserve *) reg [bw:0] int2;

assign out = int2;

always @ (posedge clk or posedge reset) begin
    if (reset) begin
        int1 <= 0;
        int2 <= 0;
    end
    else begin
        int1 <= in;
        int2 <= int1;
    end
end

endmodule
