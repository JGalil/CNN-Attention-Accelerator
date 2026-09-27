// Created by prof. Mingu Kang @VVIP Lab in UCSD ECE department
// Please do not spread this code without permission 

// 10ns time unit so the testbench's half-cycle `#0.5` delays are 5 ns and the
// clock period is 10 ns, matching the 100 MHz the design is constrained at.
// With a 1ns unit the simulated clock was 1 GHz, which a power analyser reading
// the VCD takes at face value and scales dynamic power by.
`timescale 10ns/1ps

module fullchip_tb;

parameter total_cycle = 8;   // how many streamed Q vectors will be processed
parameter bw = 8;            // Q & K vector bit precision
parameter bw_psum = 2*bw+4;  // partial sum bit precision
parameter pr = 8;           // how many products added in each dot product 
parameter col = 8;           // how many dot product units are equipped

localparam SKIP_GATING_THRESH = 660;

integer qk_file ; // file handler
integer qk_file2 ; // file handler

integer qk_scan_file ; // file handler
integer qk_scan_file2 ; // file handler



integer  captured_data;
integer  captured_data2;

integer  weight [col*pr-1:0];
integer  weight2 [col*pr-1:0];

`define NULL 0




integer  K[col-1:0][pr-1:0];
integer  K2[col-1:0][pr-1:0];
integer  Q[total_cycle-1:0][pr-1:0];
integer  result[total_cycle-1:0][col-1:0];
integer  result2[total_cycle-1:0][col-1:0];
integer  sum[total_cycle-1:0];
integer  sum2[total_cycle-1:0];


integer i,j,k,t,p,q,s,u, m;





reg [bw_psum+3:0] skip_thresh = SKIP_GATING_THRESH;
reg reset = 1;
reg clk = 0;
reg [pr*bw-1:0] mem_in; 
reg [pr*bw-1:0] mem_in_2; 
reg ofifo_rd = 0;
wire [19:0] inst; 
reg qmem_rd = 0;
reg qmem_wr = 0; 
reg kmem_rd = 0; 
reg kmem_wr = 0;
reg pmem_rd = 0; 
reg pmem_wr = 0; 
reg execute = 0;
reg load = 0;
reg [3:0] qkmem_add = 0;
reg [3:0] pmem_add = 0;
reg acc = 0;
reg div = 0;
reg write_sum_out = 0;

assign inst[19] = write_sum_out;
assign inst[18] = div;
assign inst[17] = acc;
assign inst[16] = ofifo_rd;
assign inst[15:12] = qkmem_add;
assign inst[11:8]  = pmem_add;
assign inst[7] = execute;
assign inst[6] = load;
assign inst[5] = qmem_rd;
assign inst[4] = qmem_wr;
assign inst[3] = kmem_rd;
assign inst[2] = kmem_wr;
assign inst[1] = pmem_rd;
assign inst[0] = pmem_wr;

wire [bw_psum*col-1:0] pmem_out;
wire [bw_psum*col-1:0] pmem_out2;

wire [bw_psum*col-1:0] sfp_out;
wire [bw_psum*col-1:0] sfp_out2;
wire div_done_1;
wire div_done_2;

wire [bw_psum+3:0] sum_out;
wire [bw_psum+3:0] sum_out2;



reg [bw_psum-1:0] temp8b;
reg [bw_psum+3:0] temp_sum;
reg [bw_psum*col-1:0] temp20b;
reg [bw_psum*col-1:0] temp20b_arr_pmem [0:total_cycle-1];

reg [bw_psum-1:0] temp8b_2;
reg [bw_psum+3:0] temp_sum_2;
reg [bw_psum*col-1:0] temp20b_2;
reg [bw_psum*col-1:0] temp20b_arr_pmem_2 [0:total_cycle-1];

// copy for second core

reg [bw_psum-1:0] temp20b_arr_norm [0:total_cycle-1][0:col-1];
reg [bw_psum+3:0] sum_est;
reg [bw_psum+3:0] sum_est_arr [0:total_cycle-1];

reg [bw_psum-1:0] temp_val;

reg [bw_psum-1:0] temp20b_arr_norm2 [0:total_cycle-1][0:col-1];
reg [bw_psum+3:0] sum_est2;
reg [bw_psum+3:0] sum_est2_arr [0:total_cycle-1];
reg [bw_psum-1:0] temp_val2;






fullchip #(.bw(bw), .bw_psum(bw_psum), .col(col), .pr(pr)) fullchip_instance (
      .reset(reset),
      .clk(clk),
      .clk2(clk),   // see fullchip.v: inst is not yet synchronised into core 2
      .mem_in_1(mem_in), 
      .mem_in_2(mem_in_2), 
      .inst(inst),
      .pmem_out_1(pmem_out),
      .pmem_out_2(pmem_out2),
      .sfp_out_1(sfp_out),
      .sfp_out_2(sfp_out2),
      .skip_thresh(skip_thresh),
      .div_done_1(div_done_1),
      .div_done_2(div_done_2)
);


initial begin 

  $dumpfile("fullchip_tb.vcd");
  $dumpvars(0,fullchip_tb);

`ifdef SAIF_DUMP
  // Toggle capture for activity-annotated power analysis. Icarus does not
  // implement these, so they are guarded; build with -DSAIF_DUMP under a
  // simulator that does (see sim/gen_saif.md).
  //
  // Capture starts after reset and the memory preload so the average is not
  // dominated by a burst of writes the real workload performs once.
  $set_gate_level_monitoring("rtl_on");
  $set_toggle_region(fullchip_tb.fullchip_instance);
`endif
  // $dumpvars(1, fullchip_tb.full_chip_instance.async_gray_fifo_instance_core1_to_2.fifo[0]);
  // $dumpvars(1, fullchip_tb.full_chip_instance.async_gray_fifo_instance_core1_to_2.fifo[1]);



///// Q data txt reading /////

$display("##### Q data txt reading #####"); // same Q for both cores


  qk_file = $fopen("qdata.txt", "r");

  // //// To get rid of first 3 lines in data file ////
  // qk_scan_file = $fscanf(qk_file, "%s\n", captured_data);
  // qk_scan_file = $fscanf(qk_file, "%s\n", captured_data);
  // qk_scan_file = $fscanf(qk_file, "%s\n", captured_data);
  // qk_scan_file = $fscanf(qk_file, "%s\n", captured_data);


  for (q=0; q<total_cycle; q=q+1) begin
    for (j=0; j<pr; j=j+1) begin
          qk_scan_file = $fscanf(qk_file, "%d\n", captured_data);
          Q[q][j] = captured_data;
          //$display("%d\n", K[q][j]);
    end
  end
/////////////////////////////////




  for (q=0; q<2; q=q+1) begin
    #0.5 clk = 1'b0;   
    #0.5 clk = 1'b1;   
  end




///// K data txt reading /////

$display("##### K data txt reading core 1 #####");

  for (q=0; q<10; q=q+1) begin
    #0.5 clk = 1'b0;   
    #0.5 clk = 1'b1;   
  end
  reset = 0;

  qk_file = $fopen("kdata_core0.txt", "r");

  //// To get rid of first 4 lines in data file ////
  // qk_scan_file = $fscanf(qk_file, "%s\n", captured_data);
  // qk_scan_file = $fscanf(qk_file, "%s\n", captured_data);
  // qk_scan_file = $fscanf(qk_file, "%s\n", captured_data);
  // qk_scan_file = $fscanf(qk_file, "%s\n", captured_data);




  for (q=0; q<col; q=q+1) begin
    for (j=0; j<pr; j=j+1) begin
          qk_scan_file = $fscanf(qk_file, "%d\n", captured_data);
          $display("captured_data=%d, @j=%d", captured_data, j);
          K[q][j] = captured_data;
          //$display("##### %d\n", K[q][j]);
    end
  end


  $display("##### K data txt reading core 2 #####");

  for (q=0; q<10; q=q+1) begin
    #0.5 clk = 1'b0;   
    #0.5 clk = 1'b1;   
  end
  reset = 0;

  qk_file = $fopen("kdata_core1.txt", "r");

  //// To get rid of first 4 lines in data file ////
  // qk_scan_file = $fscanf(qk_file, "%s\n", captured_data);
  // qk_scan_file = $fscanf(qk_file, "%s\n", captured_data);
  // qk_scan_file = $fscanf(qk_file, "%s\n", captured_data);
  // qk_scan_file = $fscanf(qk_file, "%s\n", captured_data);




  for (q=0; q<col; q=q+1) begin
    for (j=0; j<pr; j=j+1) begin
          qk_scan_file = $fscanf(qk_file, "%d\n", captured_data);
          $display("captured_data=%d, @j=%d", captured_data, j);
          K2[q][j] = captured_data;
          //$display("##### %d\n", K[q][j]);
    end
  end
/////////////////////////////////








/////////////// Estimated result printing /////////////////


$display("##### Estimated multiplication result core 1 #####");

  for (t=0; t<total_cycle; t=t+1) begin
     for (q=0; q<col; q=q+1) begin
       result[t][q] = 0;
     end
  end

  for (t=0; t<total_cycle; t=t+1) begin
     for (q=0; q<col; q=q+1) begin
         for (k=0; k<pr; k=k+1) begin
            result[t][q] = result[t][q] + Q[t][k] * K[q][k];
         end

         temp8b = result[t][q];
         temp20b = {temp20b[139:0], temp8b}; // shifting 20 bits from the left into current 160 bit reg 
     end
     temp20b_arr_pmem[t] = temp20b;
  
     // Calculate sum of absolute values
     sum_est = 0;
     for (q=0; q<col; q=q+1) begin
         // Extract each 20-bit value
        if (result[t][q] < 0)
            sum_est = sum_est - result[t][q];
        else
            sum_est = sum_est + result[t][q];
        
     end
    //  sum_est = sum_est >> 6; // to match the hardware
     sum_est_arr[t] = sum_est;


    //  for (q=0; q<col; q=q+1) begin
    //     if (result[t][q] <0)
    //       temp20b_arr_norm[t][col-q-1] = (-result[t][q]) / sum_est;
    //     else
    //       temp20b_arr_norm[t][col-q-1] = (result[t][q]) / sum_est;
    //  end
  end
  // $display("last temp20b element= %0d %0d %0d %0d %0d %0d %0d %0d",
  //     temp20b_arr_norm[7][0],
  //     temp20b_arr_norm[7][1],
  //     temp20b_arr_norm[7][2],
  //     temp20b_arr_norm[7][3],
  //     temp20b_arr_norm[7][4],
  //     temp20b_arr_norm[7][5],
  //     temp20b_arr_norm[7][6],
  //     temp20b_arr_norm[7][7]);

  $display("##### Estimated multiplication result core 2 #####");

  for (t=0; t<total_cycle; t=t+1) begin
     for (q=0; q<col; q=q+1) begin
       result2[t][q] = 0;
     end
  end

  for (t=0; t<total_cycle; t=t+1) begin
     for (q=0; q<col; q=q+1) begin
         for (k=0; k<pr; k=k+1) begin
            result2[t][q] = result2[t][q] + Q[t][k] * K2[q][k];
         end

         temp8b_2 = result2[t][q];
         temp20b_2 = {temp20b_2[139:0], temp8b_2}; // shifting 20 bits from the left into current 160 bit reg 
     end
     temp20b_arr_pmem_2[t] = temp20b_2;
  
     // Calculate sum of absolute values
     sum_est2 = 0;
     for (q=0; q<col; q=q+1) begin
         // Extract each 20-bit value
        if (result2[t][q] < 0)
            sum_est2 = sum_est2 - result2[t][q];
        else
            sum_est2 = sum_est2 + result2[t][q];
        
     end
    //  sum_est2 = sum_est2 >> 6; // to match the hardware
     sum_est2_arr[t] = sum_est2;

    //  for (q=0; q<col; q=q+1) begin
    //     if (result2[t][q] <0)
    //       temp20b_arr_norm2[t][col-q-1] = (-result2[t][q]) / sum_est2;
    //     else
    //       temp20b_arr_norm2[t][col-q-1] = (result2[t][q]) / sum_est2;
    //  end
  end
  // for (t=0; t<total_cycle; t=t+1) begin
  //   for (q=0; q<col; q=q+1) begin
  //       if (result[t][q] <0)
  //         temp20b_arr_norm[t][col-q-1] = (-result[t][q]) / ((sum_est_arr[t] + sum_est2_arr[t]) >> 7);
  //       else
  //         temp20b_arr_norm[t][col-q-1] = (result[t][q]) / ((sum_est_arr[t] + sum_est2_arr[t]) >> 7);
  //    end
  //   for (q=0; q<col; q=q+1) begin
  //       if (result2[t][q] <0)
  //         temp20b_arr_norm2[t][col-q-1] = (-result2[t][q]) / ((sum_est2_arr[t] + sum_est_arr[t]) >> 7);
  //       else
  //         temp20b_arr_norm2[t][col-q-1] = (result2[t][q]) / ((sum_est2_arr[t] + sum_est_arr[t]) >> 7);
  //    end
  // end
  for (t=0; t<total_cycle; t=t+1) begin
    for (q=0; q<col; q=q+1) begin
        if ((sum_est_arr[t] + sum_est2_arr[t]) < SKIP_GATING_THRESH) begin
            temp20b_arr_norm[t][col-q-1] = 0;
        end else begin
            if (result[t][q] < 0)
              temp20b_arr_norm[t][col-q-1] = (-result[t][q]) / ((sum_est_arr[t] + sum_est2_arr[t]) >> 7);
            else
              temp20b_arr_norm[t][col-q-1] = (result[t][q]) / ((sum_est_arr[t] + sum_est2_arr[t]) >> 7);
        end
    end

    for (q=0; q<col; q=q+1) begin
        if ((sum_est2_arr[t] + sum_est_arr[t]) < SKIP_GATING_THRESH) begin
            temp20b_arr_norm2[t][col-q-1] = 0;
        end else begin
            if (result2[t][q] < 0)
              temp20b_arr_norm2[t][col-q-1] = (-result2[t][q]) / ((sum_est2_arr[t] + sum_est_arr[t]) >> 7);
            else
              temp20b_arr_norm2[t][col-q-1] = (result2[t][q]) / ((sum_est2_arr[t] + sum_est_arr[t]) >> 7);
        end
    end
  end



//////////////////////////////////////////////






///// Qmem writing  /////

$display("##### Qmem writing  #####");

  for (q=0; q<total_cycle; q=q+1) begin

    #0.5 clk = 1'b0;  
    qmem_wr = 1;  if (q>0) qkmem_add = qkmem_add + 1; 
    
    mem_in[1*bw-1:0*bw] = Q[q][0];
    mem_in[2*bw-1:1*bw] = Q[q][1];
    mem_in[3*bw-1:2*bw] = Q[q][2];
    mem_in[4*bw-1:3*bw] = Q[q][3];
    mem_in[5*bw-1:4*bw] = Q[q][4];
    mem_in[6*bw-1:5*bw] = Q[q][5];
    mem_in[7*bw-1:6*bw] = Q[q][6];
    mem_in[8*bw-1:7*bw] = Q[q][7];

  // core 2
    mem_in_2[1*bw-1:0*bw] = Q[q][0];
    mem_in_2[2*bw-1:1*bw] = Q[q][1];
    mem_in_2[3*bw-1:2*bw] = Q[q][2];
    mem_in_2[4*bw-1:3*bw] = Q[q][3];
    mem_in_2[5*bw-1:4*bw] = Q[q][4];
    mem_in_2[6*bw-1:5*bw] = Q[q][5];
    mem_in_2[7*bw-1:6*bw] = Q[q][6];
    mem_in_2[8*bw-1:7*bw] = Q[q][7];
 
    $display("Writing Q Data to SRAM @ Cycle %0d: %0d %0d %0d %0d %0d %0d %0d %0d", 
              q, Q[q][0], Q[q][1], Q[q][2], Q[q][3], Q[q][4], Q[q][5], Q[q][6], Q[q][7]);

    #0.5 clk = 1'b1;  

  end


  #0.5 clk = 1'b0;  
  qmem_wr = 0; 
  qkmem_add = 0;
  #0.5 clk = 1'b1;  
///////////////////////////////////////////





///// Kmem writing  /////

$display("##### Kmem writing #####");

  for (q=0; q<col; q=q+1) begin

    #0.5 clk = 1'b0;  
    kmem_wr = 1; if (q>0) qkmem_add = qkmem_add + 1; 
    
    mem_in[1*bw-1:0*bw] = K[q][0];
    mem_in[2*bw-1:1*bw] = K[q][1];
    mem_in[3*bw-1:2*bw] = K[q][2];
    mem_in[4*bw-1:3*bw] = K[q][3];
    mem_in[5*bw-1:4*bw] = K[q][4];
    mem_in[6*bw-1:5*bw] = K[q][5];
    mem_in[7*bw-1:6*bw] = K[q][6];
    mem_in[8*bw-1:7*bw] = K[q][7];

    mem_in_2[1*bw-1:0*bw] = K2[q][0];
    mem_in_2[2*bw-1:1*bw] = K2[q][1];
    mem_in_2[3*bw-1:2*bw] = K2[q][2];
    mem_in_2[4*bw-1:3*bw] = K2[q][3];
    mem_in_2[5*bw-1:4*bw] = K2[q][4];
    mem_in_2[6*bw-1:5*bw] = K2[q][5];
    mem_in_2[7*bw-1:6*bw] = K2[q][6];
    mem_in_2[8*bw-1:7*bw] = K2[q][7];


    #0.5 clk = 1'b1;  

  end

  #0.5 clk = 1'b0;  
  kmem_wr = 0;  
  qkmem_add = 0;
  #0.5 clk = 1'b1;  
///////////////////////////////////////////



  for (q=0; q<2; q=q+1) begin
    #0.5 clk = 1'b0;  
    #0.5 clk = 1'b1;   
  end




/////  K data loading  /////
$display("##### K data loading to processor #####");

  for (q=0; q<col+1; q=q+1) begin
    #0.5 clk = 1'b0;  
    load = 1; 
    if (q==1) kmem_rd = 1;
    if (q>1) begin
       qkmem_add = qkmem_add + 1;
    end

    #0.5 clk = 1'b1;  
  end

  #0.5 clk = 1'b0;  
  kmem_rd = 0; qkmem_add = 0;
  #0.5 clk = 1'b1;  

  #0.5 clk = 1'b0;  
  load = 0; 
  #0.5 clk = 1'b1;  

///////////////////////////////////////////

 for (q=0; q<10; q=q+1) begin
    #0.5 clk = 1'b0;   
    #0.5 clk = 1'b1;   
 end





///// execution  /////
$display("##### execute #####");

  for (q=0; q<total_cycle; q=q+1) begin
    #0.5 clk = 1'b0;  
    execute = 1; 
    qmem_rd = 1;

    if (q>0) begin
       qkmem_add = qkmem_add + 1;
    end

    #0.5 clk = 1'b1;  
  end

  #0.5 clk = 1'b0;  
  qmem_rd = 0; qkmem_add = 0; execute = 0;
  #0.5 clk = 1'b1;  


///////////////////////////////////////////

 for (q=0; q<10; q=q+1) begin
    #0.5 clk = 1'b0;   
    #0.5 clk = 1'b1;   
 end




////////////// output fifo rd and wb to psum mem ///////////////////

$display("##### move ofifo to pmem #####");

  for (q=0; q<total_cycle; q=q+1) begin
    #0.5 clk = 1'b0;  
    ofifo_rd = 1; 
    pmem_wr = 1; 

    if (q>0) begin
       pmem_add = pmem_add + 1;
    end

    #0.5 clk = 1'b1;  
  end

  #0.5 clk = 1'b0;  
  pmem_wr = 0; pmem_add = 0; ofifo_rd = 0; pmem_rd = 1;
  #0.5 clk = 1'b1;  

///////////////////////////////////////////

  #0.5 clk = 1'b0;
  #0.5 clk = 1'b1;

////////////// write to pmem_out ///////////////////

$display("##### move pmem to pmem_out #####");

  for (q=0; q<total_cycle; q=q+1) begin
    #0.5 clk = 1'b0;  
    pmem_rd = 1; 
    pmem_wr = 0; 

   // if (q>0) begin
       pmem_add = pmem_add + 1;
       
   // end
    if (pmem_out === temp20b_arr_pmem[q]) begin
        $display(":) CORE 1 MATCHED @cycle%2d", q);
    end 
    
    else begin
        $display(":( CORE 1 MISMATCH @cycle%2d", q);
    end
    // Display actual unpacked columns
    $display("  Actual  = %0d %0d %0d %0d %0d %0d %0d %0d",
      $signed(pmem_out[bw_psum*1-1 : bw_psum*0]),
      $signed(pmem_out[bw_psum*2-1 : bw_psum*1]),
      $signed(pmem_out[bw_psum*3-1 : bw_psum*2]),
      $signed(pmem_out[bw_psum*4-1 : bw_psum*3]),
      $signed(pmem_out[bw_psum*5-1 : bw_psum*4]),
      $signed(pmem_out[bw_psum*6-1 : bw_psum*5]),
      $signed(pmem_out[bw_psum*7-1 : bw_psum*6]),
      $signed(pmem_out[bw_psum*8-1 : bw_psum*7]));

    // Display predicted unpacked columns
    $display("  Predict = %0d %0d %0d %0d %0d %0d %0d %0d",
      $signed(temp20b_arr_pmem[q][bw_psum*1-1 : bw_psum*0]),
      $signed(temp20b_arr_pmem[q][bw_psum*2-1 : bw_psum*1]),
      $signed(temp20b_arr_pmem[q][bw_psum*3-1 : bw_psum*2]),
      $signed(temp20b_arr_pmem[q][bw_psum*4-1 : bw_psum*3]),
      $signed(temp20b_arr_pmem[q][bw_psum*5-1 : bw_psum*4]),
      $signed(temp20b_arr_pmem[q][bw_psum*6-1 : bw_psum*5]),
      $signed(temp20b_arr_pmem[q][bw_psum*7-1 : bw_psum*6]),
      $signed(temp20b_arr_pmem[q][bw_psum*8-1 : bw_psum*7]));

    // core 2 print pmem out
    if (pmem_out2 === temp20b_arr_pmem_2[q]) begin
        $display(":) CORE 2 MATCHED @cycle%2d", q);
    end 
    
    else begin
        $display(":( CORE 2 MISMATCH @cycle%2d", q);
    end
    // Display actual unpacked columns
    $display("  Actual  = %0d %0d %0d %0d %0d %0d %0d %0d",
      $signed(pmem_out2[bw_psum*1-1 : bw_psum*0]),
      $signed(pmem_out2[bw_psum*2-1 : bw_psum*1]),
      $signed(pmem_out2[bw_psum*3-1 : bw_psum*2]),
      $signed(pmem_out2[bw_psum*4-1 : bw_psum*3]),
      $signed(pmem_out2[bw_psum*5-1 : bw_psum*4]),
      $signed(pmem_out2[bw_psum*6-1 : bw_psum*5]),
      $signed(pmem_out2[bw_psum*7-1 : bw_psum*6]),
      $signed(pmem_out2[bw_psum*8-1 : bw_psum*7]));

    // Display predicted unpacked columns
    $display("  Predict = %0d %0d %0d %0d %0d %0d %0d %0d",
      $signed(temp20b_arr_pmem_2[q][bw_psum*1-1 : bw_psum*0]),
      $signed(temp20b_arr_pmem_2[q][bw_psum*2-1 : bw_psum*1]),
      $signed(temp20b_arr_pmem_2[q][bw_psum*3-1 : bw_psum*2]),
      $signed(temp20b_arr_pmem_2[q][bw_psum*4-1 : bw_psum*3]),
      $signed(temp20b_arr_pmem_2[q][bw_psum*5-1 : bw_psum*4]),
      $signed(temp20b_arr_pmem_2[q][bw_psum*6-1 : bw_psum*5]),
      $signed(temp20b_arr_pmem_2[q][bw_psum*7-1 : bw_psum*6]),
      $signed(temp20b_arr_pmem_2[q][bw_psum*8-1 : bw_psum*7]));

    #0.5 clk = 1'b1;  
  end

  #0.5 clk = 1'b0;  
  pmem_wr = 0; pmem_add = 0; ofifo_rd = 0; pmem_rd = 0;
  #0.5 clk = 1'b1;  

  // reset and read again for sfp
  #0.5 clk = 1'b0;  
  pmem_wr = 0; pmem_add = 0; ofifo_rd = 0; pmem_rd = 1;
  #0.5 clk = 1'b1;  

///////////////////////////////////////////

////////////// SFP Norm ///////////////////

`ifdef SAIF_DUMP
  $toggle_start();
`endif

$display("##### SFP Normalization #####");

  for (q=0; q<total_cycle; q=q+1) begin
    #0.5 clk = 1'b0;  
    pmem_rd = 1; 
    pmem_wr = 0; 
    // sum first and write to internal sfp fifo
    acc = 1;

   // if (q>0) begin
       pmem_add = pmem_add + 1;

    #0.5 clk = 1'b1;  
  end

  #0.5 clk = 1'b0;  
  pmem_wr = 0; pmem_add = 0; ofifo_rd = 0; 
  acc = 0; div = 0; pmem_rd = 0; qkmem_add = 0; 
  write_sum_out = 1;
  #0.5 clk = 1'b1; 
///////////////////////////////////////////////////
// wait 3 cycles for first sum to be ready in async fifo
 for (k=0; k<3; k=k+1) begin
      #0.5 clk = 1'b0;   
      #0.5 clk = 1'b1;   
end

  #0.5 clk = 1'b0;  
  pmem_wr = 0; pmem_add = 0; ofifo_rd = 0; 
  acc = 0; div = 1; pmem_rd = 1; qkmem_add = 0; 
  write_sum_out = 1;
  #0.5 clk = 1'b1; 
///////////////////////////////////////////////////
  for (q=0; q<total_cycle; q=q+1) begin //+1 for pipeline latency
    // for (k=0; k<5; k=k+1) begin
    //   #0.5 clk = 1'b0;   
    //   #0.5 clk = 1'b1;   
    // end
    begin : wait_for_sfp
        integer timeout;
        timeout = 0;
        while (!div_done_1 && timeout < 10) begin
            #0.5 clk = 1'b0;
            #0.5 clk = 1'b1;
            timeout = timeout + 1;
        end
        #0.5 clk = 1'b0;
        $display("SFP cycle %0d: waited %0d cycles (skip=%0b)", q, timeout,
                 fullchip_tb.fullchip_instance.core_instance1.sfp_instance.row_skipped);
    end

    #0.5 clk = 1'b0;

    write_sum_out = 0;
    pmem_add = pmem_add + 1;

    if (q < total_cycle) begin
      if (q>0) qkmem_add = qkmem_add + 1;

      mem_in[1*bw-1:0*bw] = sfp_out[bw_psum*1-1 : bw_psum*0];
      mem_in[2*bw-1:1*bw] = sfp_out[bw_psum*2-1 : bw_psum*1];
      mem_in[3*bw-1:2*bw] = sfp_out[bw_psum*3-1 : bw_psum*2];
      mem_in[4*bw-1:3*bw] = sfp_out[bw_psum*4-1 : bw_psum*3];
      mem_in[5*bw-1:4*bw] = sfp_out[bw_psum*5-1 : bw_psum*4];
      mem_in[6*bw-1:5*bw] = sfp_out[bw_psum*6-1 : bw_psum*5];
      mem_in[7*bw-1:6*bw] = sfp_out[bw_psum*7-1 : bw_psum*6];
      mem_in[8*bw-1:7*bw] = sfp_out[bw_psum*8-1 : bw_psum*7];

      mem_in_2[1*bw-1:0*bw] = sfp_out2[bw_psum*1-1 : bw_psum*0];
      mem_in_2[2*bw-1:1*bw] = sfp_out2[bw_psum*2-1 : bw_psum*1];
      mem_in_2[3*bw-1:2*bw] = sfp_out2[bw_psum*3-1 : bw_psum*2];
      mem_in_2[4*bw-1:3*bw] = sfp_out2[bw_psum*4-1 : bw_psum*3];
      mem_in_2[5*bw-1:4*bw] = sfp_out2[bw_psum*5-1 : bw_psum*4];
      mem_in_2[6*bw-1:5*bw] = sfp_out2[bw_psum*6-1 : bw_psum*5];
      mem_in_2[7*bw-1:6*bw] = sfp_out2[bw_psum*7-1 : bw_psum*6];
      mem_in_2[8*bw-1:7*bw] = sfp_out2[bw_psum*8-1 : bw_psum*7];

      $display("core1@cycle%2d:    Actual= %0d %0d %0d %0d %0d %0d %0d %0d", q,  // was q-1
        sfp_out[bw_psum*1-1:bw_psum*0], sfp_out[bw_psum*2-1:bw_psum*1],
        sfp_out[bw_psum*3-1:bw_psum*2], sfp_out[bw_psum*4-1:bw_psum*3],
        sfp_out[bw_psum*5-1:bw_psum*4], sfp_out[bw_psum*6-1:bw_psum*5],
        sfp_out[bw_psum*7-1:bw_psum*6], sfp_out[bw_psum*8-1:bw_psum*7]);
      $display("core1@cycle%2d: Pred Norm= %0d %0d %0d %0d %0d %0d %0d %0d", q,  // was q-1
        temp20b_arr_norm[q][0], temp20b_arr_norm[q][1],   // was q-1
        temp20b_arr_norm[q][2], temp20b_arr_norm[q][3],
        temp20b_arr_norm[q][4], temp20b_arr_norm[q][5],
        temp20b_arr_norm[q][6], temp20b_arr_norm[q][7]);
      $display("core2@cycle%2d:    Actual= %0d %0d %0d %0d %0d %0d %0d %0d", q,  // was q-1
        sfp_out2[bw_psum*1-1:bw_psum*0], sfp_out2[bw_psum*2-1:bw_psum*1],
        sfp_out2[bw_psum*3-1:bw_psum*2], sfp_out2[bw_psum*4-1:bw_psum*3],
        sfp_out2[bw_psum*5-1:bw_psum*4], sfp_out2[bw_psum*6-1:bw_psum*5],
        sfp_out2[bw_psum*7-1:bw_psum*6], sfp_out2[bw_psum*8-1:bw_psum*7]);
      $display("core2@cycle%2d: Pred Norm= %0d %0d %0d %0d %0d %0d %0d %0d", q,  // was q-1
        temp20b_arr_norm2[q][0], temp20b_arr_norm2[q][1],  // was q-1
        temp20b_arr_norm2[q][2], temp20b_arr_norm2[q][3],
        temp20b_arr_norm2[q][4], temp20b_arr_norm2[q][5],
        temp20b_arr_norm2[q][6], temp20b_arr_norm2[q][7]);
    end

    #0.5 clk = 1'b1;
    write_sum_out = 1;
  end

  #0.5 clk = 1'b0;  
  pmem_wr = 0; pmem_add = 0; ofifo_rd = 0; pmem_rd = 0;
  acc = 0; div = 0;
  #0.5 clk = 1'b1; 

  #10;
`ifdef SAIF_DUMP
  $toggle_stop();
  $toggle_report("../fullchip.saif", 1.0e-9, fullchip_tb.fullchip_instance);
`endif
  $finish;


//  for (q=0; q<col; q=q+1) begin

//     #0.5 clk = 1'b0;  
//     kmem_wr = 1; if (q>0) qkmem_add = qkmem_add + 1; 
    
//     mem_in[1*bw-1:0*bw] = K[q][0];
//     mem_in[2*bw-1:1*bw] = K[q][1];
//     mem_in[3*bw-1:2*bw] = K[q][2];
//     mem_in[4*bw-1:3*bw] = K[q][3];
//     mem_in[5*bw-1:4*bw] = K[q][4];
//     mem_in[6*bw-1:5*bw] = K[q][5];
//     mem_in[7*bw-1:6*bw] = K[q][6];
//     mem_in[8*bw-1:7*bw] = K[q][7];
//     mem_in[9*bw-1:8*bw] = K[q][8];
//     mem_in[10*bw-1:9*bw] = K[q][9];
//     mem_in[11*bw-1:10*bw] = K[q][10];
//     mem_in[12*bw-1:11*bw] = K[q][11];
//     mem_in[13*bw-1:12*bw] = K[q][12];
//     mem_in[14*bw-1:13*bw] = K[q][13];
//     mem_in[15*bw-1:14*bw] = K[q][14];
//     mem_in[16*bw-1:15*bw] = K[q][15];

//     #0.5 clk = 1'b1;  

//   end

//   #0.5 clk = 1'b0;  
//   kmem_wr = 0;  
//   qkmem_add = 0;
//   #0.5 clk = 1'b1;  

end

endmodule




