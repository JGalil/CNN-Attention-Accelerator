// Asynchronous FIFO, gray-coded pointers. Carries partial row sums between the
// two cores across their clock-domain boundary.
module async_gray_fifo (wr_clk, wr_rst, wr_en, wr_data, rd_clk, rd_rst, rd_en, rd_data, empty, full);

parameter bw   = 20;
parameter addr = 3;                 // depth = 2^addr = 8 entries

localparam depth = 1 << addr;

input  wr_clk, wr_rst, wr_en;
input  rd_clk, rd_rst, rd_en;
output empty, full;
input  [bw-1:0] wr_data;
output [bw-1:0] rd_data;

// Written in the write domain, read combinationally in the read domain.
// Intentionally unreset: emptiness is defined by the pointers, a single write
// driver keeps it synthesisable, and no reset allows RAM inference.
reg [bw-1:0] fifo [depth-1:0];

// One bit wider than the address to separate full from empty.
reg [addr:0] wr_ptr, rd_ptr;

wire [addr:0] wr_ptr_gray, rd_ptr_gray;             // in their own domains
wire [addr:0] wr_ptr_gray_cdc, rd_ptr_gray_cdc;     // after crossing
wire [addr:0] wr_ptr_cdc, rd_ptr_cdc;               // converted back to binary

//////////////////////////////////////////////////
// Gray and binary conversion functions
function [addr:0] bin2gray (input [addr:0] bin);
    begin
        bin2gray = (bin >> 1) ^ bin;
    end
endfunction

function [addr:0] gray2bin (input [addr:0] gray);
    integer i;
    begin
        gray2bin[addr] = gray[addr];
        for (i=addr-1; i>=0; i=i-1)
            gray2bin[i] = gray2bin[i+1] ^ gray[i];
    end
endfunction
//////////////////////////////////////////////////

assign wr_ptr_gray = bin2gray(wr_ptr);
assign rd_ptr_gray = bin2gray(rd_ptr);

sync_mb #(.bw(addr)) sync_mb_wr_to_rd (
    .clk(rd_clk),
    .reset(rd_rst),
    .in(wr_ptr_gray),
    .out(wr_ptr_gray_cdc)
);

sync_mb #(.bw(addr)) sync_mb_rd_to_wr (
    .clk(wr_clk),
    .reset(wr_rst),
    .in(rd_ptr_gray),
    .out(rd_ptr_gray_cdc)
);

assign wr_ptr_cdc = gray2bin(wr_ptr_gray_cdc);
assign rd_ptr_cdc = gray2bin(rd_ptr_gray_cdc);

// Write side
always @(posedge wr_clk or posedge wr_rst) begin
    if (wr_rst) begin
        wr_ptr <= 0;
    end
    else if (wr_en & ~full) begin
        wr_ptr <= wr_ptr + 1;
        fifo[wr_ptr[addr-1:0]] <= wr_data;
    end
end

// MSB differs, lower bits match => pointers one lap apart.
assign full = (wr_ptr[addr] != rd_ptr_cdc[addr]) && (wr_ptr[addr-1:0] == rd_ptr_cdc[addr-1:0]);

// Read side
always @(posedge rd_clk or posedge rd_rst) begin
    if (rd_rst) begin
        rd_ptr <= 0;
    end
    else if (rd_en & ~empty) begin
        rd_ptr <= rd_ptr + 1;
    end
end

assign empty = (rd_ptr == wr_ptr_cdc);

assign rd_data = fifo[rd_ptr[addr-1:0]];

endmodule
