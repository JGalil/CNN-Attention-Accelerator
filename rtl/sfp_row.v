module sfp_row (clk, acc, div, div_done, fifo_ext_rd, sum_in, sum_out, sfp_in, sfp_out, reset);

  parameter col = 8;
  parameter bw = 8;
  parameter bw_psum = 2*bw+4;

  localparam SKIP_GATING_THRESH = 660;
 
  input  clk, div, acc, fifo_ext_rd;
  input  [bw_psum+3:0] sum_in;
  input  [col*bw_psum-1:0] sfp_in;
  input reset;
  wire  [col*bw_psum-1:0] abs;
  reg    div_q;
  output [col*bw_psum-1:0] sfp_out;
  output [bw_psum+3:0] sum_out;
  output div_done;
  wire [bw_psum+3:0] sum_this_core;
  wire signed [bw_psum-1:0] sum_2core;
  wire signed [bw_psum-1:0] sfp_in_sign0;
  wire signed [bw_psum-1:0] sfp_in_sign1;
  wire signed [bw_psum-1:0] sfp_in_sign2;
  wire signed [bw_psum-1:0] sfp_in_sign3;
  wire signed [bw_psum-1:0] sfp_in_sign4;
  wire signed [bw_psum-1:0] sfp_in_sign5;
  wire signed [bw_psum-1:0] sfp_in_sign6;
  wire signed [bw_psum-1:0] sfp_in_sign7;


  reg signed [bw_psum-1:0] sfp_out_sign0;
  reg signed [bw_psum-1:0] sfp_out_sign1;
  reg signed [bw_psum-1:0] sfp_out_sign2;
  reg signed [bw_psum-1:0] sfp_out_sign3;
  reg signed [bw_psum-1:0] sfp_out_sign4;
  reg signed [bw_psum-1:0] sfp_out_sign5;
  reg signed [bw_psum-1:0] sfp_out_sign6;
  reg signed [bw_psum-1:0] sfp_out_sign7;

  reg [bw_psum+3:0] sum_q;
  reg fifo_wr;
  wire [7:0] done;
  wire [7:0][bw_psum-1:0] quotient_out;

  wire skip;
  wire skip_inst;
  wire [bw_psum-1:0]   gated_divisor;
  wire [col*bw_psum-1:0] gated_abs;

  assign sfp_in_sign0 =  sfp_in[bw_psum*1-1 : bw_psum*0];
  assign sfp_in_sign1 =  sfp_in[bw_psum*2-1 : bw_psum*1];
  assign sfp_in_sign2 =  sfp_in[bw_psum*3-1 : bw_psum*2];
  assign sfp_in_sign3 =  sfp_in[bw_psum*4-1 : bw_psum*3];
  assign sfp_in_sign4 =  sfp_in[bw_psum*5-1 : bw_psum*4];
  assign sfp_in_sign5 =  sfp_in[bw_psum*6-1 : bw_psum*5];
  assign sfp_in_sign6 =  sfp_in[bw_psum*7-1 : bw_psum*6];
  assign sfp_in_sign7 =  sfp_in[bw_psum*8-1 : bw_psum*7];


  assign sfp_out[bw_psum*1-1 : bw_psum*0] = sfp_out_sign0;
  assign sfp_out[bw_psum*2-1 : bw_psum*1] = sfp_out_sign1;
  assign sfp_out[bw_psum*3-1 : bw_psum*2] = sfp_out_sign2;
  assign sfp_out[bw_psum*4-1 : bw_psum*3] = sfp_out_sign3;
  assign sfp_out[bw_psum*5-1 : bw_psum*4] = sfp_out_sign4;
  assign sfp_out[bw_psum*6-1 : bw_psum*5] = sfp_out_sign5;
  assign sfp_out[bw_psum*7-1 : bw_psum*6] = sfp_out_sign6;
  assign sfp_out[bw_psum*8-1 : bw_psum*7] = sfp_out_sign7;


  // assign sum_2core = sum_this_core[bw_psum+3:6] + sum_in[bw_psum+3:6]; //shift sum right by 6 so we don't get fractions
  assign sum_2core = (sum_this_core + sum_in) >> 7; //shift sum right by 6 so we don't get fractions
  assign skip = (sum_this_core + sum_in) < SKIP_GATING_THRESH;
  assign skip_inst = div_q && skip;
  assign div_done = done[0] || skip_inst;

  assign abs[bw_psum*1-1 : bw_psum*0] = (sfp_in[bw_psum*1-1]) ?  (~sfp_in[bw_psum*1-1 : bw_psum*0] + 1)  :  sfp_in[bw_psum*1-1 : bw_psum*0];
  assign abs[bw_psum*2-1 : bw_psum*1] = (sfp_in[bw_psum*2-1]) ?  (~sfp_in[bw_psum*2-1 : bw_psum*1] + 1)  :  sfp_in[bw_psum*2-1 : bw_psum*1];
  assign abs[bw_psum*3-1 : bw_psum*2] = (sfp_in[bw_psum*3-1]) ?  (~sfp_in[bw_psum*3-1 : bw_psum*2] + 1)  :  sfp_in[bw_psum*3-1 : bw_psum*2];
  assign abs[bw_psum*4-1 : bw_psum*3] = (sfp_in[bw_psum*4-1]) ?  (~sfp_in[bw_psum*4-1 : bw_psum*3] + 1)  :  sfp_in[bw_psum*4-1 : bw_psum*3];
  assign abs[bw_psum*5-1 : bw_psum*4] = (sfp_in[bw_psum*5-1]) ?  (~sfp_in[bw_psum*5-1 : bw_psum*4] + 1)  :  sfp_in[bw_psum*5-1 : bw_psum*4];
  assign abs[bw_psum*6-1 : bw_psum*5] = (sfp_in[bw_psum*6-1]) ?  (~sfp_in[bw_psum*6-1 : bw_psum*5] + 1)  :  sfp_in[bw_psum*6-1 : bw_psum*5];
  assign abs[bw_psum*7-1 : bw_psum*6] = (sfp_in[bw_psum*7-1]) ?  (~sfp_in[bw_psum*7-1 : bw_psum*6] + 1)  :  sfp_in[bw_psum*7-1 : bw_psum*6];
  assign abs[bw_psum*8-1 : bw_psum*7] = (sfp_in[bw_psum*8-1]) ?  (~sfp_in[bw_psum*8-1 : bw_psum*7] + 1)  :  sfp_in[bw_psum*8-1 : bw_psum*7];

  fifo_depth16 #(.bw(bw_psum+4)) fifo_inst_int (
     .rd_clk(clk), 
     .wr_clk(clk), 
     .in(sum_q),
     .out(sum_this_core), 
     .rd(div_done), //done flag from mc_divider tells fifo to send out next. Don't need a signal for first read as fifo out pointer is on it already
     .wr(fifo_wr), 
     .reset(reset)
  );

  fifo_depth16 #(.bw(bw_psum+4)) fifo_inst_ext (
     .rd_clk(clk), 
     .wr_clk(clk), 
     .in(sum_q),
     .out(sum_out), 
     .rd(fifo_ext_rd), 
     .wr(fifo_wr), 
     .reset(reset)
  );

  assign gated_divisor = (div_q && !skip) ? sum_2core : 0;
  assign gated_abs     = (div_q && !skip) ? abs : 0;

  genvar i;
  generate
    for (i = 0; i < 8; i = i + 1) begin : mc_div_loop
        mc_div #(.bw(bw), .bw_psum(bw_psum)) mc_div_instance (
          .clk(clk),
          .div(div_q && !skip), // only start division if we're not skipping
          .reset(reset),
          .divisor(gated_divisor),
          .dividend(gated_abs[bw_psum*(i+1)-1 : bw_psum*i]),
          .done(done[i]),
          .quotient(quotient_out[i])
        );
    end
    
  endgenerate

  always @ (posedge clk or posedge reset) begin
    if (reset) begin
      fifo_wr <= 0;
      sfp_out_sign0 <= 0;
      sfp_out_sign1 <= 0;
      sfp_out_sign2 <= 0;
      sfp_out_sign3 <= 0;
      sfp_out_sign4 <= 0;
      sfp_out_sign5 <= 0;
      sfp_out_sign6 <= 0;
      sfp_out_sign7 <= 0;
      div_q <= 0;
      sum_q <= 0;
    end
    else begin
       div_q <= div;

       if (acc) begin
      
         sum_q <= 
           {4'b0, abs[bw_psum*1-1 : bw_psum*0]} +
           {4'b0, abs[bw_psum*2-1 : bw_psum*1]} +
           {4'b0, abs[bw_psum*3-1 : bw_psum*2]} +
           {4'b0, abs[bw_psum*4-1 : bw_psum*3]} +
           {4'b0, abs[bw_psum*5-1 : bw_psum*4]} +
           {4'b0, abs[bw_psum*6-1 : bw_psum*5]} +
           {4'b0, abs[bw_psum*7-1 : bw_psum*6]} +
           {4'b0, abs[bw_psum*8-1 : bw_psum*7]} ;
         fifo_wr <= 1;
       end
       else begin
         fifo_wr <= 0;

            if (skip_inst) begin
              sfp_out_sign0 <= 0;
              sfp_out_sign1 <= 0;
              sfp_out_sign2 <= 0;
              sfp_out_sign3 <= 0;
              sfp_out_sign4 <= 0;
              sfp_out_sign5 <= 0;
              sfp_out_sign6 <= 0;
              sfp_out_sign7 <= 0;
            end else if (div_q && done[0]) begin
                  sfp_out_sign0 <= quotient_out[0];
                  sfp_out_sign1 <= quotient_out[1];
                  sfp_out_sign2 <= quotient_out[2];
                  sfp_out_sign3 <= quotient_out[3];
                  sfp_out_sign4 <= quotient_out[4];
                  sfp_out_sign5 <= quotient_out[5];
                  sfp_out_sign6 <= quotient_out[6];
                  sfp_out_sign7 <= quotient_out[7];
            end

       end
   end
 end

//  always @(posedge clk) begin
//     if (div_q) begin
//         $display("sfp_row: sum_this_core=%0d sum_in=%0d skip=%0b skip_inst=%0b",
//             sum_this_core, sum_in, skip, skip_inst);
//     end
//   end

endmodule