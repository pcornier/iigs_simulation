
module vdc (
input clk,
input ce_pix,
input[9:0] H,
input[8:0] V,
output reg [7:0] R,
output reg [7:0] G,
output reg [7:0] B,
output [22:0] video_addr,
input [7:0] video_data,
input [7:0] TEXTCOLOR,
input [3:0] BORDERCOLOR
);


// TEXTCOLOR -- 7:4 text color 3:0 background



reg [11:0] BORGB;
always @(*) begin
	case (BORDERCOLOR)
		4'h0: BORGB = 12'h000;          /* 0x0 black */
		4'h1: BORGB = 12'hd03;          /* 0x1 deep red */
		4'h2: BORGB = 12'h009;          /* 0x2 dark blue */
		4'h3: BORGB = 12'hd0d;          /* 0x3 purple */
		4'h4: BORGB = 12'h070;          /* 0x4 dark green */
		4'h5: BORGB = 12'h555;          /* 0x5 dark gray */
		4'h6: BORGB = 12'h22f;          /* 0x6 medium blue */
		4'h7: BORGB = 12'h6af;          /* 0x7 light blue */
		4'h8: BORGB = 12'h852;          /* 0x8 brown */
		4'h9: BORGB = 12'hf60;          /* 0x9 orange */
		4'ha: BORGB = 12'haaa;          /* 0xa light gray */
		4'hb: BORGB = 12'hf98;          /* 0xb pink */
		4'hc: BORGB = 12'h0d0;          /* 0xc green */
		4'hd: BORGB = 12'hff0;          /* 0xd yellow */
		4'he: BORGB = 12'h0f9;          /* 0xe aquamarine */
		4'hf: BORGB = 12'hfff;          /* 0xf white */
	endcase
end
reg [11:0] TRGB;
always @(*) begin
	case (TEXTCOLOR[7:4])
		4'h0: TRGB = 12'h000;          /* 0x0 black */
		4'h1: TRGB = 12'hd03;          /* 0x1 deep red */
		4'h2: TRGB = 12'h009;          /* 0x2 dark blue */
		4'h3: TRGB = 12'hd0d;          /* 0x3 purple */
		4'h4: TRGB = 12'h070;          /* 0x4 dark green */
		4'h5: TRGB = 12'h555;          /* 0x5 dark gray */
		4'h6: TRGB = 12'h22f;          /* 0x6 medium blue */
		4'h7: TRGB = 12'h6af;          /* 0x7 light blue */
		4'h8: TRGB = 12'h852;          /* 0x8 brown */
		4'h9: TRGB = 12'hf60;          /* 0x9 orange */
		4'ha: TRGB = 12'haaa;          /* 0xa light gray */
		4'hb: TRGB = 12'hf98;          /* 0xb pink */
		4'hc: TRGB = 12'h0d0;          /* 0xc green */
		4'hd: TRGB = 12'hff0;          /* 0xd yellow */
		4'he: TRGB = 12'h0f9;          /* 0xe aquamarine */
		4'hf: TRGB = 12'hfff;          /* 0xf white */
	endcase
end

reg [11:0] BRGB;
always @(*) begin
	case (TEXTCOLOR[3:0])
		4'h0: BRGB = 12'h000;          /* 0x0 black */
		4'h1: BRGB = 12'hd03;          /* 0x1 deep red */
		4'h2: BRGB = 12'h009;          /* 0x2 dark blue */
		4'h3: BRGB = 12'hd0d;          /* 0x3 purple */
		4'h4: BRGB = 12'h070;          /* 0x4 dark green */
		4'h5: BRGB = 12'h555;          /* 0x5 dark gray */
		4'h6: BRGB = 12'h22f;          /* 0x6 medium blue */
		4'h7: BRGB = 12'h6af;          /* 0x7 light blue */
		4'h8: BRGB = 12'h852;          /* 0x8 brown */
		4'h9: BRGB = 12'hf60;          /* 0x9 orange */
		4'ha: BRGB = 12'haaa;          /* 0xa light gray */
		4'hb: BRGB = 12'hf98;          /* 0xb pink */
		4'hc: BRGB = 12'h0d0;          /* 0xc green */
		4'hd: BRGB = 12'hff0;          /* 0xd yellow */
		4'he: BRGB = 12'h0f9;          /* 0xe aquamarine */
		4'hf: BRGB = 12'hfff;          /* 0xf white */
	endcase
end

reg [12:0] BASEADDR;
wire  [ 4:0] vert = V[7:3]-5'h02;
always @(*) begin
	case (vert)
		5'h00: BASEADDR= 13'h000;
		5'h01: BASEADDR= 13'h080;
		5'h02: BASEADDR= 13'h100;
		5'h03: BASEADDR= 13'h180;
		5'h04: BASEADDR= 13'h200;
		5'h05: BASEADDR= 13'h280;
		5'h06: BASEADDR= 13'h300;
		5'h07: BASEADDR= 13'h380;

		5'h08: BASEADDR= 13'h028;
		5'h09: BASEADDR= 13'h0A8;
		5'h0A: BASEADDR= 13'h128;
		5'h0B: BASEADDR= 13'h1A8;
		5'h0C: BASEADDR= 13'h228;
		5'h0D: BASEADDR= 13'h2A8;
		5'h0E: BASEADDR= 13'h328;
		5'h0F: BASEADDR= 13'h3A8;

		5'h10: BASEADDR= 13'h050;
		5'h11: BASEADDR= 13'h0D0;
		5'h12: BASEADDR= 13'h150;
		5'h13: BASEADDR= 13'h1D0;
		5'h14: BASEADDR= 13'h250;
		5'h15: BASEADDR= 13'h2D0;
		5'h16: BASEADDR= 13'h350;
		5'h17: BASEADDR= 13'h3D0;
		default: BASEADDR = 13'h000;
	endcase
end

rom #(.memfile("chr.mem"),.AW(12)) charrom(
  .clock(clk),
  .address(chrom_addr),
  .q(chrom_data_out),
  .ce(1'b1)
);

wire [7:0] chrom_data_out;
wire [11:0] chram_addr;
wire [11:0] chrom_addr;


// just do 1 video mode for now
//wire [2:0] chpos_x = 3'd7 - H[2:0];
wire [2:0] chpos_y = V[2:0];
reg [5:0] chram_x;// = H[8:3];

wire [12:0] chram_y = BASEADDR;

//assign a = H > 'd511 ? 1'b0 : V > 'd255 ? 1'b0 : chrom_data_out[chpos_x[2:0]];



wire  a = chrom_data_out[xpos[3:1]];


//
// Text Mode chars are 7 bits wide, not 8
//
reg [3:0] xpos;
always @(posedge clk) if(ce_pix)
begin
	if (H<32)
	begin
		xpos<=0;
		chram_x<=0;
	end
	else
	begin

		xpos<=xpos+1'b1;
		if (xpos=='d13) begin
			xpos<=0;
			chram_x<=chram_x+1'b1;
		end
	end
//$display("xpos[3:1] %x xpos %x",xpos[3:1],xpos);
//$display("chram_x[6:1] %x chram_x %x",chram_x[6:1],chram_x);

if (H < 'd32 || H > 'd32+'d560 || V < 'd16 || V > 'd207)
begin
R <= {BORGB[11:8],BORGB[11:8]};
G <= {BORGB[7:4],BORGB[7:4]};
B <= {BORGB[3:0],BORGB[3:0]};
end
else
begin
R <= ~a ? {TRGB[11:8],TRGB[11:8]} : {BRGB[11:8],BRGB[11:8]}  ;
G <= ~a ? {TRGB[7:4],TRGB[7:4]} :  {BRGB[7:4],BRGB[7:4]};
B <= ~a ? {TRGB[3:0],TRGB[3:0]} :  {BRGB[3:0],BRGB[3:0]};

end
end


//assign a = chrom_data_out[chpos_x[2:0]];
assign video_addr = chram_y + chram_x +23'h400 ;
assign chrom_addr = { 1'b0,video_data[7:0], chpos_y};


always @(posedge clk) if (ce_pix)
begin
//	$display("V %x oldV %x chram_y %x base_y %x offset %x video_addr %x video_data %x video_data %x %c %x \n",V[8:3],oldV,chram_y,base_y,offset,video_addr,video_data,video_data[6:0],video_data[6:0],chrom_data_out);
end


endmodule
