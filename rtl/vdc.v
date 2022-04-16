
module vdc (
input clk,
input ce_pix,
input[9:0] H,
input[8:0] V,
output [7:0] R,
output [7:0] G,
output [7:0] B,
output [22:0] video_addr,
input [7:0] video_data,
input [7:0] TEXTCOLOR
);


// TEXTCOLOR -- 7:4 text color 3:0 background



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
wire [2:0] chpos_x = 3'd7 - H[2:0];
wire [2:0] chpos_y = V[2:0];
wire [5:0] chram_x = H[8:3];

//wire [5:0] chram_y = V[4:3]*'h28+{offset,4'b0};
wire [22:0] chram_y = base_y+offset;


reg [22:0] base_y;
reg [5:0] oldV;
reg [22:0] offset;
always @(posedge clk) if (ce_pix)
begin
        oldV<=V[8:3];
	if (V==0) begin
		base_y<='h400;
		offset<=0;
	end
	else
	begin
		if (oldV!=V[8:3]) begin
			$display("*** add 80");
		base_y<=base_y+'h80;
		if (!(V[8:3] % 'd8))
		begin
			base_y<='h400;
			offset<=offset+'h28;
		end
	end
	end
end



//assign a = H > 'd511 ? 1'b0 : V > 'd255 ? 1'b0 : chrom_data_out[chpos_x[2:0]];
wire  a = chrom_data_out['h7-chpos_x[2:0]];

assign R = a ? {TRGB[11:8],TRGB[11:8]} : {BRGB[11:8],BRGB[11:8]}  ;
assign G = a ? {TRGB[7:4],TRGB[7:4]} :  {BRGB[7:4],BRGB[7:4]};
assign B = a ? {TRGB[3:0],TRGB[3:0]} :  {BRGB[3:0],BRGB[3:0]};

//assign a = chrom_data_out[chpos_x[2:0]];
assign video_addr = {chram_y, chram_x} + 'h400 ;
assign chrom_addr = {1'b0, 1'b0,video_data[7:0], chpos_y};


always @(posedge clk) if (ce_pix)
begin
	$display("V %x oldV %x chram_y %x base_y %x offset %x video_addr %x video_data %x video_data %x %c %x \n",V[8:3],oldV,chram_y,base_y,offset,video_addr,video_data,video_data[6:0],video_data[6:0],chrom_data_out);
end


endmodule
