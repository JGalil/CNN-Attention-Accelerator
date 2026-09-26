module async_gray_fifo (wr_clk, wr_rst, wr_en, wr_data, rd_clk, rd_rst, rd_en, rd_data, empty, full);

parameter bw = 20;
parameter addr = 3; // 2^4 = 16 fifo depth

input wr_clk, wr_rst, wr_en;
input rd_clk, rd_rst, rd_en;
output empty, full;
input [bw-1:0] wr_data;
output [bw-1:0] rd_data;


// fifo array
reg [bw-1:0] fifo [(1<<addr)-1:0]; // 2^addr_bits

// original binary pointers
reg [addr:0] wr_ptr, rd_ptr; // use one more bit for full comparison as seen in 260B lecture

// gray-code pointers --> in the original clk domains
wire [addr:0] wr_ptr_gray, rd_ptr_gray;

// gray code pointers --> after crossing clock domains
wire [addr:0] wr_ptr_gray_cdc, rd_ptr_gray_cdc;

// converted back binary pointers after cdc
wire [addr:0] wr_ptr_cdc, rd_ptr_cdc;

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

// convert original binary to gray
assign wr_ptr_gray = bin2gray(wr_ptr);
assign rd_ptr_gray = bin2gray(rd_ptr);

// pass gray pointers through synchronizer
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

// convert back to binary
assign wr_ptr_cdc = gray2bin(wr_ptr_gray_cdc);
assign rd_ptr_cdc = gray2bin(rd_ptr_gray_cdc);


// wr_ptr update logic
always @(posedge wr_clk or posedge wr_rst) begin
    if(wr_rst)begin
        wr_ptr <= 0;
    end
    else if (wr_en & ~full)begin
        wr_ptr <= wr_ptr + 1;
        fifo[wr_ptr[addr-1:0]] <= wr_data;
    end
end

// full flag
assign full = (wr_ptr[addr] != rd_ptr_cdc[addr]) && (wr_ptr[addr-1:0] == rd_ptr_cdc[addr-1:0]);
// MSB not equal and all other bits equal implies full (260b slides on cdc)

integer i;

// rd_ptr update logic
always @(posedge rd_clk or posedge rd_rst) begin
    if(rd_rst)begin
        rd_ptr <= 0;
        for (i = 0; i < (1<<addr); i = i + 1) begin
            fifo[i] <= {bw{1'b0}};
        end
    end
    else if (rd_en & ~empty)begin
        rd_ptr <= rd_ptr + 1;
    end
end

// empty flag
assign empty = (rd_ptr == wr_ptr_cdc);

// Output logic
assign rd_data = fifo[rd_ptr[addr-1:0]];

endmodule