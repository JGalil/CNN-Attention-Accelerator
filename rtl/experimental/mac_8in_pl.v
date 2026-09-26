// 3 Cycle MAC
//0.45ns (2.22 Ghz) with 0 WNS with typical corner
//10.6632 mw power, 9.7683 mW Internal, 0.8345 Switching, 0.060417 Leakage, 86.21% Register Power, 13.79% Combinational Power
//10843.92 Area, 7019.64 Combinational, 512.28 Buf/Inv, 3824.28 Register
module mac_8in_pl (clk, reset, out, mac_en, a, b);

parameter bw = 8;
parameter bw_psum = 2*bw+4;
parameter pr = 8; // parallel factor: number of inputs = 64

input clk, reset;

output [bw_psum-1:0] out;
input  [pr*bw-1:0] a;
input  [pr*bw-1:0] b;

input mac_en;


wire    	[2*bw-1:0]	product0	;
wire		[2*bw-1:0]	product1	;
wire		[2*bw-1:0]	product2	;
wire		[2*bw-1:0]	product3	;
wire		[2*bw-1:0]	product4	;
wire		[2*bw-1:0]	product5	;
wire		[2*bw-1:0]	product6	;
wire		[2*bw-1:0]	product7	;

reg		[2*bw-1:0]	product0_q	;
reg		[2*bw-1:0]	product1_q	;
reg		[2*bw-1:0]	product2_q	;
reg		[2*bw-1:0]	product3_q	;
reg		[2*bw-1:0]	product4_q	;
reg		[2*bw-1:0]	product5_q	;
reg		[2*bw-1:0]	product6_q	;
reg		[2*bw-1:0]	product7_q	;


wire		[2*bw+1:0]	add_0_3		;
wire		[2*bw+1:0]	add_4_7		;

reg		[2*bw+1:0]	add_0_3_q	;
reg		[2*bw+1:0]	add_4_7_q	;

reg mac_en_q;
reg mac_en_q2;
reg mac_en_q3;




genvar i;

assign	product0	=	{{(bw){a[bw*	1	-1]}},	a[bw*	1	-1:bw*	0	]}	*	{{(bw){b[bw*	1	-1]}},	b[bw*	1	-1:	bw*	0	]};
assign	product1	=	{{(bw){a[bw*	2	-1]}},	a[bw*	2	-1:bw*	1	]}	*	{{(bw){b[bw*	2	-1]}},	b[bw*	2	-1:	bw*	1	]};
assign	product2	=	{{(bw){a[bw*	3	-1]}},	a[bw*	3	-1:bw*	2	]}	*	{{(bw){b[bw*	3	-1]}},	b[bw*	3	-1:	bw*	2	]};
assign	product3	=	{{(bw){a[bw*	4	-1]}},	a[bw*	4	-1:bw*	3	]}	*	{{(bw){b[bw*	4	-1]}},	b[bw*	4	-1:	bw*	3	]};
assign	product4	=	{{(bw){a[bw*	5	-1]}},	a[bw*	5	-1:bw*	4	]}	*	{{(bw){b[bw*	5	-1]}},	b[bw*	5	-1:	bw*	4	]};
assign	product5	=	{{(bw){a[bw*	6	-1]}},	a[bw*	6	-1:bw*	5	]}	*	{{(bw){b[bw*	6	-1]}},	b[bw*	6	-1:	bw*	5	]};
assign	product6	=	{{(bw){a[bw*	7	-1]}},	a[bw*	7	-1:bw*	6	]}	*	{{(bw){b[bw*	7	-1]}},	b[bw*	7	-1:	bw*	6	]};
assign	product7	=	{{(bw){a[bw*	8	-1]}},	a[bw*	8	-1:bw*	7	]}	*	{{(bw){b[bw*	8	-1]}},	b[bw*	8	-1:	bw*	7	]};


assign add_0_3 = 
                {{(2){product0_q[2*bw-1]}},product0_q	}
	+	{{(2){product1_q[2*bw-1]}},product1_q	}
	+	{{(2){product2_q[2*bw-1]}},product2_q	}
	+	{{(2){product3_q[2*bw-1]}},product3_q	};

assign add_4_7 = 
               	{{(2){product4_q[2*bw-1]}},product4_q	}
	+	{{(2){product5_q[2*bw-1]}},product5_q	}
	+	{{(2){product6_q[2*bw-1]}},product6_q	}
	+	{{(2){product7_q[2*bw-1]}},product7_q	};




assign out = mac_en_q3 ? {{(5){add_0_3_q[2*bw]}},add_0_3_q	} + {{(5){add_4_7_q[2*bw]}},add_4_7_q	} : 0;
// assign out = {{(5){add_0_3_q[2*bw]}},add_0_3_q	} + {{(5){add_4_7_q[2*bw]}},add_4_7_q	} ;

wire s1_clk;
wire s2_clk;

assign s1_clk = mac_en_q && clk;
assign s2_clk = mac_en_q2 && clk;

always @ (negedge clk) begin
	
	mac_en_q <= mac_en;
	mac_en_q2 <= mac_en_q;
	mac_en_q3 <= mac_en_q2;
end

always @ (posedge s1_clk) begin
	if (reset) begin
		product0_q <= 0;
		product1_q <= 0;
		product2_q <= 0;
		product3_q <= 0;
		product4_q <= 0;
		product5_q <= 0;
		product6_q <= 0;
		product7_q <= 0;

		add_0_3_q <= 0;
		add_4_7_q <= 0;
	end
	else begin
		// if (mac_en_q3 == 0) $display ("MAC GATING");
		product0_q <= product0;
		product1_q <= product1;
		product2_q <= product2;
		product3_q <= product3;
		product4_q <= product4;
		product5_q <= product5;
		product6_q <= product6;
		product7_q <= product7;

	end

	//Mult - Add Stage
end

always @ (posedge s2_clk) begin
	if (reset) begin
		add_0_3_q <= 0;
		add_4_7_q <= 0;
	end
	else begin
		// if (mac_en_q3 == 0) $display ("MAC GATING");
		add_0_3_q <= add_0_3;
		add_4_7_q <= add_4_7;

	end

	//Add - Add Stage
	
end








endmodule
