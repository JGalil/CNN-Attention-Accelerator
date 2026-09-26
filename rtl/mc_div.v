module mc_div (clk, reset, div, dividend, divisor, quotient, done);
parameter bw = 8;
parameter bw_psum = 2*bw+6;
parameter cycles = 4;

input clk;
input reset;
input div;
input [bw_psum-1:0] dividend;
input [bw_psum-1:0] divisor;
output [bw_psum-1:0] quotient;
output done;

reg done_q;
reg [2:0] count;
reg [bw_psum-1:0] quotient_q;
wire [bw_psum-1:0] quotient_c;


// the comb logic (usually big for divider)
assign quotient_c = dividend / divisor;
assign quotient = quotient_q;
assign done = done_q;

always @(posedge clk or posedge reset) begin
    if (reset) begin
        count <= 0;
        done_q <= 0;
        quotient_q <= 0;

    end
    else if (div) begin
        count <= count + 1;

        if (count == cycles) begin
            quotient_q <= quotient_c;
            done_q <= 1'b1;
            count <= 0;
        end
        else begin
            done_q <= 1'b0;
        end
    end
    else begin 
        count <= 0;
        done_q <= 0;
    end
end

endmodule