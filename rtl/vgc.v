
module vgc (
input CLK_14M,
input clk_vid,
input ce_pix,
input[9:0] H,
input[8:0] V,
output reg scanline_irq,
output reg vbl_irq,
output reg [7:0] R,
output reg [7:0] G,
output reg [7:0] B,
output [22:0] video_addr,
input [7:0] video_data,
input [7:0] TEXTCOLOR,
input [3:0] BORDERCOLOR,
input HIRES_MODE,
input ALTCHARSET,
input EIGHTYCOL,
input PAGE2,
input TEXTG,
input MIXG,
input [7:0] NEWVIDEO

);


// TEXTCOLOR -- 7:4 text color 3:0 background


// if NEWVIDEO[7] == 1 then we are in SHRG mode

assign video_addr = NEWVIDEO[7] ? video_addr_shrg : video_addr_ii;
//wire linear_mode = ~NEWVIDEO[6];
wire linear_mode =1'b1;

/* SHRG */
reg [22:0] video_addr_shrg_1;
reg [22:0] video_addr_shrg_2;
reg [22:0] video_addr_shrg;
reg [3:0] r_shrg[16];
reg [3:0] g_shrg[16];
reg [3:0] b_shrg[16];


// debug with a fixed palette
/*
initial begin
r_shrg[0]=0;
g_shrg[0]=0;
b_shrg[0]=0;
r_shrg[1]=4'hd;
g_shrg[1]=4'h0;
b_shrg[1]=4'h3;
r_shrg[2]=4'h0;
g_shrg[2]=4'h0;
b_shrg[2]=4'h9;
r_shrg[3]=4'hd;
g_shrg[3]=4'h0;
b_shrg[3]=4'hd;
r_shrg[4]=4'h0;
g_shrg[4]=4'h7;
b_shrg[4]=4'h0;
r_shrg[5]=0;
g_shrg[5]=0;
b_shrg[5]=0;
r_shrg[6]=4'hd;
g_shrg[6]=4'h0;
b_shrg[6]=4'h3;
r_shrg[7]=4'h0;
g_shrg[7]=4'h0;
b_shrg[7]=4'h9;
r_shrg[8]=4'hd;
g_shrg[8]=4'h0;
b_shrg[8]=4'hd;
r_shrg[9]=4'hf;
g_shrg[9]=4'hf;
b_shrg[9]=4'hf;
r_shrg[10]=4'h5;
g_shrg[10]=4'h5;
b_shrg[10]=4'h5;
r_shrg[11]=0;
g_shrg[11]=0;
b_shrg[11]=0;
r_shrg[12]=4'hd;
g_shrg[12]=4'h0;
b_shrg[12]=4'h3;
r_shrg[13]=4'h0;
g_shrg[13]=4'h0;
b_shrg[13]=4'h9;
r_shrg[14]=4'hd;
g_shrg[14]=4'h0;
b_shrg[14]=4'hd;
r_shrg[15]=4'h7;
g_shrg[15]=4'h7;
b_shrg[15]=4'h0;
end
*/

reg [3:0] shrg_r_pix;
reg [3:0] shrg_g_pix;
reg [3:0] shrg_b_pix;
// one cycle before the end of the left border, pull down the scp
reg [7:0] scb;
reg [1:0] h_counter;
reg base_toggle;
reg [3:0] last_pixel;
reg [3:0] pal_counter;
always @(posedge clk_vid) if(ce_pix)
begin
//$display("video_data = %x video_addr = %x video_addr_shrg %x video_addr_ii %x  H %x V %x NEWVIDEO[6] %x NEWVIDEO[7]",video_data,video_addr,video_addr_shrg,video_addr_ii,H,V,NEWVIDEO[6],NEWVIDEO[7]);
	// load SCB
	if (H=='h38c) begin
		if (linear_mode)
		begin
			video_addr_shrg <= 'h19D00+(V-'d16+1);
		end
		else
		begin
		if (V[0])
			video_addr_shrg <= 'h19D00+((V-'d16+1)>>1);
		else
			video_addr_shrg <= 'h15D00+((V-'d16+1)>>1);
		end
	end
	else if (H=='h38e) begin
		scb <= video_data;
		// might need to move the scanline interrupt..
		if (video_data[6] && NEWVIDEO[7] && V > 'd15 && V < 'd206)
			scanline_irq<=1;	
		
		//$display("SCB = %x video_addr %x",video_data,video_addr);
		//video_addr_shrg <= 'h19E00 + {video_data[3:0],5'b00000};
		base_toggle<=0;
		if (linear_mode)
		begin
			// linear mode
			//$display("NONWORKING NEWVIDEO 6 MODE - LINEAR data: %x offset: %x", video_data[3:0],{video_data[3:0],5'b0000} );
			video_addr_shrg_1 <= 'h19E00 + {video_data[3:0],5'b00000};
			video_addr_shrg <= 'h19E00 + {video_data[3:0],5'b00000};
			video_addr_shrg_2 <= 'h19Dff + {video_data[3:0],5'b00000};
		end
		else
		begin
			//$display("NONLINEAR NEWVIDEO 6 MODE data: %x newaddroffset: %x",video_data[3:0],{video_data[3:0],4'b0000} );
			video_addr_shrg_1 <= 'h19F00 + {video_data[3:0],4'b0000};
			video_addr_shrg <= 'h19F00 + {video_data[3:0],4'b0000};
			video_addr_shrg_2 <= 'h15F00 + {video_data[3:0],4'b0000};
		end
	end else if (H=='h390) begin
		pal_counter<=0;
		scanline_irq<=0;	
		if (linear_mode)
		begin
			video_addr_shrg <= video_addr_shrg + 1'b1;
			video_addr_shrg_1 <= video_addr_shrg_1 +1'b1;
		end
		else begin
			if (base_toggle)
			begin
				video_addr_shrg <= video_addr_shrg_1;
				video_addr_shrg_2 <= video_addr_shrg_2 +1'b1;
			end
			else
			begin
				video_addr_shrg <= video_addr_shrg_2;
				video_addr_shrg_1 <= video_addr_shrg_1 +1'b1;
			end
		end
	end else if (H < 32) begin
		//video_data;
		//$display("PALETTE = %x",video_data);
		base_toggle<=~base_toggle;
		if (linear_mode)
		begin
			if (video_addr_shrg[0]) begin
		                //$display("R PALETTE = %x addr %x  color index %x color r %x",video_data,video_addr_shrg,pal_counter,video_data[3:0]);
				b_shrg[pal_counter]<=video_data[3:0];
				g_shrg[pal_counter]<=video_data[7:4];
			end else begin
		                //$display("GB PALETTE = %x addr %x color index %x color b %x g %x",video_data,video_addr_shrg,pal_counter,video_data[3:0],video_data[7:4]);
				r_shrg[pal_counter]<=video_data[3:0];
				pal_counter<=pal_counter+1;
			end
			video_addr_shrg <= video_addr_shrg + 1'b1;
			video_addr_shrg_1 <= video_addr_shrg_1 +1'b1;
		end
		else begin
			if (~base_toggle) begin
		                //$display("R PALETTE = %x addr %x base_toggle %x",video_data,video_addr_shrg,base_toggle);
				r_shrg[video_addr_shrg[4:1]]<=video_data[3:0];
			end else begin
		                //$display("GB PALETTE = %x addr %x base_toggle %x",video_data,video_addr_shrg,base_toggle);
				b_shrg[video_addr_shrg[4:1]]<=video_data[3:0];
				g_shrg[video_addr_shrg[4:1]]<=video_data[7:4];
				pal_counter<=pal_counter+1;
			end
			if (base_toggle)
			begin
				video_addr_shrg <= video_addr_shrg_1;
				video_addr_shrg_2 <= video_addr_shrg_2 +1'b1;
			end
			else
			begin
				video_addr_shrg <= video_addr_shrg_2;
				video_addr_shrg_1 <= video_addr_shrg_1 +1'b1;
			end
		end
		if (H==31)
		begin
			if (linear_mode)
			begin
				// linear mode
				//$display("NONWORKING NEWVIDEO 6 MODE - LINEAR");
				video_addr_shrg_1 <= 'h12000 + ((V-16) * 'd160);  // AJS REMOVE MULTIPLY??
				video_addr_shrg <= 'h12000 + ((V-16) * 'd160);  // AJS REMOVE MULTIPLY??
				video_addr_shrg_2 <= 'h11fff + ((V-16) * 'd160);  // AJS REMOVE MULTIPLY??
			end
			else
			begin
				//$display("NONLINEAR NEWVIDEO 6 MODE");
				video_addr_shrg_1 <= 'h12000 + ((V-16) * 'd80);  // AJS REMOVE MULTIPLY??
				video_addr_shrg <= 'h12000 + ((V-16) * 'd80);  // AJS REMOVE MULTIPLY??
				video_addr_shrg_2 <= 'h16000 + ((V-16) * 'd80);  // AJS REMOVE MULTIPLY??
			end
			h_counter<=0;
			base_toggle<=0;
		end
	end else if (H < ('d32+640)) begin
		h_counter<=h_counter+1'b1;
		if (h_counter==2'd2)  
			begin
				base_toggle<=~base_toggle;
				if (linear_mode) begin
					video_addr_shrg <= video_addr_shrg + 1'b1;
					video_addr_shrg_1 <= video_addr_shrg_1 +1'b1;
				end else begin
					if (base_toggle) begin
						video_addr_shrg <= video_addr_shrg_1;
						video_addr_shrg_2 <= video_addr_shrg_2 +1'b1;
					end
					else begin
						video_addr_shrg <= video_addr_shrg_2;
						video_addr_shrg_1 <= video_addr_shrg_1 +1'b1;
					end
				end
			end
		//$display("scb[7]= %x h_counter %x video_addr %x video_data %x",scb[7],h_counter,video_addr,video_data);
		if (scb[7]) begin
			case(h_counter)
				'b00: 
				begin
					shrg_r_pix <= r_shrg[ {2'b10,video_data[7:6]}];
					shrg_g_pix <= g_shrg[ {2'b10,video_data[7:6]}];
					shrg_b_pix <= b_shrg[ {2'b10,video_data[7:6]}];
				end
				'b01:
				begin
					shrg_r_pix <= r_shrg[ {2'b11,video_data[5:4]}];
					shrg_g_pix <= g_shrg[ {2'b11,video_data[5:4]}];
					shrg_b_pix <= b_shrg[ {2'b11,video_data[5:4]}];
				end
				'b10:
				begin
					shrg_r_pix <= r_shrg[ {2'b00,video_data[3:2]}];
					shrg_g_pix <= g_shrg[ {2'b00,video_data[3:2]}];
					shrg_b_pix <= b_shrg[ {2'b00,video_data[3:2]}];
				end
				'b11:
				begin
					shrg_r_pix <= r_shrg[ {2'b01,video_data[1:0]}];
					shrg_g_pix <= g_shrg[ {2'b01,video_data[1:0]}];
					shrg_b_pix <= b_shrg[ {2'b01,video_data[1:0]}];
				end
			endcase
		end else begin
			case(h_counter)
				'b00: 
				begin
					if (video_data[7:4]==4'b0 && scb[5]) begin
					//$display("scb[5] %x use last_pixel %x",scb[5],last_pixel);
						shrg_r_pix <= r_shrg[ last_pixel ];
						shrg_g_pix <= g_shrg[ last_pixel ];
						shrg_b_pix <= b_shrg[ last_pixel ];
					end else begin
					    //$display("scb[5] %x  set last_pixel %x",scb[5],video_data[7:4]);
						last_pixel<=video_data[7:4];
						shrg_r_pix <= r_shrg[  video_data[7:4]];
						shrg_g_pix <= g_shrg[  video_data[7:4]];
						shrg_b_pix <= b_shrg[  video_data[7:4]];
					end
				end
				'b10:
				begin
					if (video_data[3:0]==4'b0 && scb[5]) begin
						shrg_r_pix <= r_shrg[ last_pixel ];
						shrg_g_pix <= g_shrg[ last_pixel ];
						shrg_b_pix <= b_shrg[ last_pixel ];
					end else begin
						last_pixel<=video_data[3:0];
						shrg_r_pix <= r_shrg[  video_data[3:0]];
						shrg_g_pix <= g_shrg[  video_data[3:0]];
						shrg_b_pix <= b_shrg[  video_data[3:0]];
					end
				end
			endcase
		end

	end


end





/* APPLE IIe */



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
  .clock(clk_vid),
  .address(chrom_addr),
  .q(chrom_data_out),
  .ce(1'b1)
);

wire [7:0] chrom_data_out;
wire [11:0] chram_addr;
wire [11:0] chrom_addr;


//
// 40 and 80 column video modes
//
wire [2:0] chpos_y = V[2:0];
reg [5:0] chram_x;
wire [12:0] chram_y = BASEADDR;


//  in EIGHTCOL mode we need each pixel, in 40 we pixel double
wire  textpixel = EIGHTYCOL ? chrom_data_out[xpos[2:0]] : chrom_data_out[xpos[3:1]];


//
// Text Mode chars are 7 bits wide, not 8
//
reg [3:0] xpos;
reg [16:0] aux;
always @(posedge clk_vid) 
begin
   if (ce_pix)
   begin
	if (H<32)
	begin
		xpos<=0;
		chram_x<=0;
		aux<=0;
	end
	else
	begin

		xpos<=xpos+1'b1;
		if (EIGHTYCOL) begin
		  if (xpos=='d5) begin
		    aux[16]<=~aux[16];
		    if (aux[16]==1'b0)
		      chram_x<=chram_x+1'b1;
		  end
		  if (xpos=='d6) begin
			xpos<=0;
                  end
		end else if (xpos=='d13) begin
			xpos<=0;
			chram_x<=chram_x+1'b1;
		end
	end
     end
//$display("xpos[2:0] %x xpos[3:1] %x xpos %x",xpos[2:0],xpos[3:1],xpos);
//$display("chram_x[6:1] %x chram_x %x chrom_data_out %x chrom_addr %x",chram_x[6:1],chram_x,chrom_data_out,chrom_addr);

// VBL is at 192 + border top
if (V == 'd16+'d192)
	vbl_irq<=1;
else
	vbl_irq<=0;



//if (H < 'd32 || H > 'd32+'d560 || V < 'd16 || V > 'd207)
if (H < 'd32 || H > 'd32+'d640 || V < 'd16 || V > 'd207)
begin
R <= {BORGB[11:8],BORGB[11:8]};
G <= {BORGB[7:4],BORGB[7:4]};
B <= {BORGB[3:0],BORGB[3:0]};
end
else
begin
R <= NEWVIDEO[7] ?  {shrg_r_pix,shrg_r_pix}  :   ~textpixel ? {TRGB[11:8],TRGB[11:8]} : {BRGB[11:8],BRGB[11:8]}  ;
G <= NEWVIDEO[7] ?  {shrg_g_pix,shrg_g_pix}  :   ~textpixel ? {TRGB[7:4],TRGB[7:4]} :  {BRGB[7:4],BRGB[7:4]};
B <= NEWVIDEO[7] ?  {shrg_b_pix,shrg_b_pix}  :   ~textpixel ? {TRGB[3:0],TRGB[3:0]} :  {BRGB[3:0],BRGB[3:0]};

end
end


//assign a = chrom_data_out[chpos_x[2:0]];
wire [22:0] video_addr_ii = chram_y + chram_x +23'h400 + aux ;
assign chrom_addr = { ALTCHARSET,video_data[7:0], chpos_y};


always @(posedge clk_vid) if (ce_pix)
begin
//	$display("V %x oldV %x chram_y %x base_y %x offset %x video_addr %x video_data %x video_data %x %c %x \n",V[8:3],oldV,chram_y,base_y,offset,video_addr,video_data,video_data[6:0],video_data[6:0],chrom_data_out);
end


endmodule
