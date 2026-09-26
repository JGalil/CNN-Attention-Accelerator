// Created by prof. Mingu Kang @VVIP Lab in UCSD ECE department
// Modified: flat product array, per-lane operand isolation removed
module mac_8in (out, a, b);

parameter bw = 8;
parameter bw_psum = 2*bw+6;
parameter pr = 8;                       // products summed per column

output [bw_psum-1:0] out;
input  [pr*bw-1:0] a;
input  [pr*bw-1:0] b;

wire [pr*2*bw-1:0] product_flat;
wire [pr*bw_psum-1:0] product_ext;      // each product sign-extended to psum width

// Operand isolation is applied once on the full-width operands in mac_col.
// Repeating it per lane here measured as no change on the a side and 22% more
// activity on the b side, for 128 extra mux cells per column.
genvar i;
generate
    for (i=0; i<pr; i=i+1) begin : mac_lanes
        wire [bw-1:0] a_val = a[bw*(i+1)-1 : bw*i];
        wire [bw-1:0] b_val = b[bw*(i+1)-1 : bw*i];

        assign product_flat[2*bw*(i+1)-1 : 2*bw*i] =
            {{(bw){a_val[bw-1]}}, a_val} * {{(bw){b_val[bw-1]}}, b_val};

        assign product_ext[bw_psum*(i+1)-1 : bw_psum*i] =
            {{(bw_psum-2*bw){product_flat[2*bw*(i+1)-1]}},
             product_flat[2*bw*(i+1)-1 : 2*bw*i]};
    end
endgenerate

assign out = product_ext[bw_psum*1-1 : bw_psum*0] +
             product_ext[bw_psum*2-1 : bw_psum*1] +
             product_ext[bw_psum*3-1 : bw_psum*2] +
             product_ext[bw_psum*4-1 : bw_psum*3] +
             product_ext[bw_psum*5-1 : bw_psum*4] +
             product_ext[bw_psum*6-1 : bw_psum*5] +
             product_ext[bw_psum*7-1 : bw_psum*6] +
             product_ext[bw_psum*8-1 : bw_psum*7];

endmodule
