module sync_mb(clk, in, out, reset);

parameter bw = 4;

input  [bw:0] in; 
input  clk;
input reset;
output [bw:0] out;

reg    [bw:0] int1; 
reg    [bw:0] int2; 

assign out = int2;

always @ (posedge clk or posedge reset) begin
    if(reset) begin
        int1 = 0;
        int2 = 0;
    end
    int1 <= in;
    int2 <= int1;
end

endmodule
