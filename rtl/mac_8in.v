// Created by prof. Mingu Kang @VVIP Lab in UCSD ECE department
// Please do not spread this code without permission 
module mac_8in (out, a, b);

parameter bw = 8;
parameter bw_psum = 2*bw+6;
parameter pr = 8; // parallel factor: number of inputs = 64

output [bw_psum-1:0] out;
input  [pr*bw-1:0] a;
input  [pr*bw-1:0] b;

// Save products in 1D flat "array" for easier operand isolation using generate
wire [pr*2*bw-1:0] product_flat;


// Loop through all mac lanes
genvar i;
generate
    for (i=0; i<pr; i=i+1) begin : mac_lanes
        // Extract individual 8 bit lanes
        wire [bw-1:0] a_val = a[bw*(i+1)-1 : bw*i];
        wire [bw-1:0] b_val = b[bw*(i+1)-1 : bw*i];
		
		// Operand isolation
		// Prevents toggling if either A or B is 0
		wire a_zero = (a_val == 0);
		wire b_zero = (b_val == 0);
		
        // Generate new A and B, if either is 0, set other one to 0
		// If B is already 0, then also set A to 0
		// If A is already 0, then also set B to 0
        wire [bw-1:0] a_iso = b_val ? a_val : {bw{1'b0}};
        wire [bw-1:0] b_iso = a_val ? b_val : {bw{1'b0}};
        
        // Perform mult and assign to correct slice of flat 1D "array"
        assign product_flat[2*bw*(i+1)-1 : 2*bw*i] = {{(bw){a_iso[bw-1]}}, a_iso} * {{(bw){b_iso[bw-1]}}, b_iso};
    end
endgenerate


// Change out assign to be slices of the flat 1D "array"
assign out = 
        {{(bw_psum-2*bw){product_flat[2*bw*1-1]}}, product_flat[2*bw*1-1 : 2*bw*0]} +
        {{(bw_psum-2*bw){product_flat[2*bw*2-1]}}, product_flat[2*bw*2-1 : 2*bw*1]} +
        {{(bw_psum-2*bw){product_flat[2*bw*3-1]}}, product_flat[2*bw*3-1 : 2*bw*2]} +
        {{(bw_psum-2*bw){product_flat[2*bw*4-1]}}, product_flat[2*bw*4-1 : 2*bw*3]} +
        {{(bw_psum-2*bw){product_flat[2*bw*5-1]}}, product_flat[2*bw*5-1 : 2*bw*4]} +
        {{(bw_psum-2*bw){product_flat[2*bw*6-1]}}, product_flat[2*bw*6-1 : 2*bw*5]} +
        {{(bw_psum-2*bw){product_flat[2*bw*7-1]}}, product_flat[2*bw*7-1 : 2*bw*6]} +
        {{(bw_psum-2*bw){product_flat[2*bw*8-1]}}, product_flat[2*bw*8-1 : 2*bw*7]};


endmodule