// Created by prof. Mingu Kang @VVIP Lab in UCSD ECE department
// Please do not spread this code without permission 
module fullchip (clk, clk2, mem_in_1, mem_in_2, inst, reset, pmem_out_1, pmem_out_2, sfp_out_1, sfp_out_2, div_done_1, div_done_2, skip_thresh);

parameter col = 8;
parameter bw = 8;
parameter bw_psum = 2*bw+4;
parameter pr = 8;

input  clk;      // core 1 and the host interface
input  clk2;     // core 2; may be asynchronous to clk
input  [pr*bw-1:0] mem_in_1; 
input  [pr*bw-1:0] mem_in_2; 
input  [19:0] inst; 
input  reset;
input  [bw_psum+3:0] skip_thresh;   // SFP row-norm skip threshold
// output [bw_psum+3:0] sum_out;
output [bw_psum*col-1:0] sfp_out_1;
output [bw_psum*col-1:0] sfp_out_2;
output div_done_1;
output div_done_2;
output [bw_psum*col-1:0] pmem_out_1;
output [bw_psum*col-1:0] pmem_out_2;


wire [bw_psum+3:0] sum_out_core1;
wire [bw_psum+3:0] sum_out_core2;

wire fifo_ext_rd;
wire [bw_psum+3:0] sum_in_core1;
wire [bw_psum+3:0] sum_in_core2;

// The external fifo rd enable signal for the sfp 
wire fifo_ext_rd_core1;
wire fifo_ext_rd_core2;

wire full1;
wire full2;

wire empty1;
wire empty2;

wire write_sum_out;


wire core1_clk;
wire core2_clk;

assign write_sum_out = inst[19];
assign core1_clk = clk;
assign core2_clk = clk2;

// The two row-sum FIFOs cross between core1_clk and core2_clk with gray-coded
// pointers, so the inter-core data path is safe for independent clocks.
//
// The instruction bus is not: inst is driven in the clk domain and consumed by
// both cores, so write_sum_out (inst[19]) reaches core 2 unsynchronised. Running
// clk2 genuinely asynchronously therefore requires either a second instruction
// port or a command FIFO into core 2. Until then clk2 must be driven from clk,
// and tb/tb_cdc.v exercises the FIFOs across independent clocks directly.
assign fifo_ext_rd_core1 = ~full1 & write_sum_out;
assign fifo_ext_rd_core2 = ~full2 & write_sum_out;




core #(.bw(bw), .bw_psum(bw_psum), .col(col), .pr(pr)) core_instance1 (
      .reset(reset), 
      .clk(core1_clk), 
      .mem_in(mem_in_1), 
      .inst(inst),
      .pmem_out(pmem_out_1),
      .sum_out(sum_out_core1),
      .sum_in(sum_in_core1),
      .sfp_out(sfp_out_1),
      .fifo_ext_rd(fifo_ext_rd_core1),
      .skip_thresh(skip_thresh),
      .div_done(div_done_1)
);

core #(.bw(bw), .bw_psum(bw_psum), .col(col), .pr(pr)) core_instance2 (
      .reset(reset), 
      .clk(core2_clk), 
      .mem_in(mem_in_2), 
      .inst(inst),
      .pmem_out(pmem_out_2),
      .sum_out(sum_out_core2),
      .sum_in(sum_in_core2),
      .sfp_out(sfp_out_2),
      .fifo_ext_rd(fifo_ext_rd_core2),
      .skip_thresh(skip_thresh),
      .div_done(div_done_2)
);

// Async fifo instances
async_gray_fifo #(.bw(bw_psum + 4)) async_gray_fifo_instance_core1_to_2 (
      .wr_clk(core1_clk),
      .wr_rst(reset),
      .wr_en(write_sum_out),
      .wr_data(sum_out_core1),
      //
      .rd_clk(core2_clk),
      .rd_rst(reset),
      .rd_en(div_done_2), // whenever divider is ready for another value in core 2
      .rd_data(sum_in_core2),
      .empty(empty1),
      .full(full1)
);

async_gray_fifo #(.bw(bw_psum + 4)) async_gray_fifo_instance_core2_to_1 (
      .wr_clk(core2_clk),
      .wr_rst(reset),
      .wr_en(write_sum_out),
      .wr_data(sum_out_core2),
      //
      .rd_clk(core1_clk),
      .rd_rst(reset),
      .rd_en(div_done_1), // whenever divider is ready for another value in core 1
      .rd_data(sum_in_core1),
      .empty(empty2),
      .full(full2)
);

//Plan:
// Ideally, we want to send data from write to fifo around 3 cycles earlier than the first read,
// Since the syncrounizers take some cycles to propagate the pointer through



endmodule
