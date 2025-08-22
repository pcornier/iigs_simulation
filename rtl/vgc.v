
module vgc (
input CLK_28M,
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
input AN3,
input STORE80,
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



// Apple IIgs color palette (16 colors)
reg [11:0] palette_rgb_r[0:15] = '{
    12'h000, // 0   Black
    12'hd03, // 1   Deep Red
    12'h009, // 2   Dark Blue
    12'hd2d, // 3   Purple
    12'h072, // 4   Dark Green
    12'h555, // 5   Dark Gray   
    12'h22f, // 6   Medium Blue
    12'h6af, // 7   Light Blue
    12'h850, // 8   Brown
    12'hf60, // 9   Orange
    12'haaa, // 10  Light Gray
    12'hf98, // 11  Pink
    12'h1d0, // 12  Light Green
    12'hff0, // 13  Yellow
    12'h4f9, // 14  Aquamarine
    12'hfff  // 15  White
};

// Apple II color artifact table from MAME, reduced to 4 bits
reg [3:0] artifact_r[0:127] = '{
    4'h0,4'h0,4'h0,4'h0,4'h8,4'h0,4'h0,4'h0,4'h1,4'h1,4'h5,4'h1,4'h9,4'h9,4'hd,4'hf,
    4'h2,4'h2,4'h6,4'h6,4'ha,4'ha,4'he,4'he,4'h3,4'h3,4'h3,4'h3,4'hb,4'hb,4'hf,4'hf,
    4'h0,4'h0,4'h4,4'h4,4'hc,4'hc,4'hc,4'hc,4'h5,4'h5,4'h5,4'h5,4'h9,4'h9,4'hd,4'hf,
    4'h0,4'h2,4'h6,4'h6,4'he,4'ha,4'he,4'he,4'h7,4'h7,4'h7,4'h7,4'hf,4'hf,4'hf,4'hf,
    4'h0,4'h0,4'h0,4'h0,4'h8,4'h8,4'h8,4'h8,4'h1,4'h1,4'h5,4'h1,4'h9,4'h9,4'hd,4'hf,
    4'h0,4'h2,4'h6,4'h6,4'ha,4'ha,4'ha,4'ha,4'h3,4'h3,4'h3,4'h3,4'hb,4'hb,4'hf,4'hf,
    4'h0,4'h0,4'h4,4'h4,4'hc,4'hc,4'hc,4'hc,4'h1,4'h1,4'h5,4'h5,4'h9,4'h9,4'hd,4'hd,
    4'h0,4'h2,4'h6,4'h6,4'he,4'ha,4'he,4'he,4'hf,4'hf,4'hf,4'h7,4'hf,4'hf,4'hf,4'hf
};

// Color lookup functions using IIgs palette
wire [11:0] BORGB = palette_rgb_r[BORDERCOLOR];
wire [11:0] TRGB = palette_rgb_r[TEXTCOLOR[7:4]];
wire [11:0] BRGB = palette_rgb_r[TEXTCOLOR[3:0]];
// Authentic Apple II NTSC Color Artifacting Algorithm  
// Based on apple2hack reference implementation
// Uses 6-pixel shift register and color basis vectors

// Apple II color basis vectors (RGB values from reference)
reg [7:0] basis_r[0:3];
reg [7:0] basis_g[0:3]; 
reg [7:0] basis_b[0:3];

// Initialize color basis vectors for Apple II NTSC colors
initial begin
    basis_r[0] = 8'h88; basis_g[0] = 8'h22; basis_b[0] = 8'h2C; // Color 0
    basis_r[1] = 8'h38; basis_g[1] = 8'h24; basis_b[1] = 8'hA0; // Color 1  
    basis_r[2] = 8'h07; basis_g[2] = 8'h67; basis_b[2] = 8'h2C; // Color 2
    basis_r[3] = 8'h38; basis_g[3] = 8'h52; basis_b[3] = 8'h07; // Color 3
end

// 6-pixel shift register for authentic Apple II color detection
reg [5:0] apple2_shift_reg;

// Horizontal pixel counter for authentic Apple II color phase (modulo 4)
// Use H counter with offset to maintain proper phase relationship
reg [10:0] pixel_counter;
wire [1:0] color_phase = H[1:0]; // Use original H-based approach

// Authentic Apple II tint consistency check
wire consistent_tint = (apple2_shift_reg[0] == apple2_shift_reg[4]) & 
                       (apple2_shift_reg[5] == apple2_shift_reg[1]);

// Apple II color generation logic
reg [7:0] apple2_r, apple2_g, apple2_b;
always @(*) begin
    if (hires_mode) begin
        // Start with black background
        apple2_r = 8'h00;
        apple2_g = 8'h00; 
        apple2_b = 8'h00;
        
        if (consistent_tint) begin
            // Tint is consistent: display color using basis vectors
            // Add contributions from 4 adjacent pixels
            if (apple2_shift_reg[3]) begin
                apple2_r = apple2_r + basis_r[(color_phase + 1) & 2'b11];
                apple2_g = apple2_g + basis_g[(color_phase + 1) & 2'b11];
                apple2_b = apple2_b + basis_b[(color_phase + 1) & 2'b11];
            end
            if (apple2_shift_reg[4]) begin
                apple2_r = apple2_r + basis_r[(color_phase + 2) & 2'b11];
                apple2_g = apple2_g + basis_g[(color_phase + 2) & 2'b11];
                apple2_b = apple2_b + basis_b[(color_phase + 2) & 2'b11];
            end
            if (apple2_shift_reg[1]) begin
                apple2_r = apple2_r + basis_r[(color_phase + 3) & 2'b11];
                apple2_g = apple2_g + basis_g[(color_phase + 3) & 2'b11];
                apple2_b = apple2_b + basis_b[(color_phase + 3) & 2'b11];
            end
            if (apple2_shift_reg[2]) begin
                apple2_r = apple2_r + basis_r[color_phase];
                apple2_g = apple2_g + basis_g[color_phase];
                apple2_b = apple2_b + basis_b[color_phase];
            end
        end else begin
            // Tint is changing: display only black, gray, or white  
            case (apple2_shift_reg[3:2])
                2'b11: begin apple2_r = 8'hFF; apple2_g = 8'hFF; apple2_b = 8'hFF; end // White
                2'b01, 2'b10: begin apple2_r = 8'h80; apple2_g = 8'h80; apple2_b = 8'h80; end // Gray
                default: begin apple2_r = 8'h00; apple2_g = 8'h00; apple2_b = 8'h00; end // Black
            endcase
        end
    end else begin
        // Not hi-res mode: use existing lores logic
        apple2_r = 8'h00;
        apple2_g = 8'h00;
        apple2_b = 8'h00;
    end
end

// Graphics RGB calculation - different for lores vs hires
wire [3:0] final_graphics_color = lores_mode ? graphics_color : hires_artifact_color;
wire [11:0] graphics_rgb = lores_mode ? palette_rgb_r[final_graphics_color] : 
                                       {apple2_r[7:4], apple2_g[7:4], apple2_b[7:4]};

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
//wire [2:0] chpos_y = V[2:0];
reg [5:0] chram_x;
//wire [12:0] chram_y = BASEADDR;


//  in EIGHTCOL mode we need each pixel, in 40 we pixel double
// Apple II character ROM: 7 pixels wide (bits 0-6), bit 7 unused for text
// In 80-column mode: xpos 0-6 maps directly to character bits 0-6
// In 40-column mode: xpos 0-13 maps to character bits 0-6 (pixel doubled)
// Ensure we don't access bit 7 which may be undefined
wire [2:0] char_bit_80 = (xpos[2:0] > 6) ? 3'd6 : xpos[2:0];
wire [2:0] char_bit_40 = (xpos[3:1] > 6) ? 3'd6 : xpos[3:1];
wire  textpixel = EIGHTYCOL ? chrom_data_out[char_bit_80] : chrom_data_out[char_bit_40];

    // Regular Hires - Apple II hi-res: 7 pixels per byte (bits 0-6), bit 7 is color/palette
    // Return only the 7 pixel bits in correct order: bit 0 first, then 1, 2, 3, 4, 5, 6
    // Bit 7 (color bit) should NOT be included in pixel stream
    function automatic bit [7:0] expandHires40([7:0] vd);
        reg [7:0] vs;
        vs = {1'b0, vd[6:0]};  // 7 pixel bits in correct order, pad with 0
        return vs;
    endfunction

    // Double Hires
    function automatic bit [6:0] expandHires80([7:0] vd);
        reg [6:0] vs;
        vs = vd[6:0];
        return vs;
    endfunction

    // Regular Text
    function automatic bit [6:0] expandText40([7:0] vd);
        reg [6:0] vs;
        vs = vd[6:0];
        return vs;
    endfunction

    // Regular Lores
    function automatic bit [6:0] expandLores40([7:0] vd, bit seg);
        reg [6:0] vs;
        case (seg)
            1'b0: vs = {
                vd[3],vd[2],vd[1],vd[0],
                vd[3],vd[2],vd[1]
            };
            1'b1: vs = {
                vd[7],vd[6],vd[5],vd[4],
                vd[7],vd[6],vd[5]
            };
        endcase
        return vs;
    endfunction


        // Double Lores
    function automatic bit [6:0] expandLores80([7:0] vd, bit seg);
        reg [6:0] vs;
        case (seg)
            1'b0: vs = {
                vd[3],vd[2],vd[1],vd[0],
                vd[3],vd[2],vd[1]
            };
            1'b1: vs = {
                vd[7],vd[6],vd[5],vd[4],
                vd[7],vd[6],vd[5]
            };
        endcase
        return vs;
    endfunction

    // Memory address generation, per Sather
    function automatic bit [15:0] lineaddr([9:0] y);
        reg [15:0] a;
        a[2:0] = 3'b0;
        a[6:3] = ({ 1'b1, y[6], 1'b1, 1'b1}) +
                 ({ y[7], 1'b1, y[7], 1'b1}) +
                 ({ 3'b000,           y[6]});
        a[9:7] = y[5:3];
        a[14:10] = (HIRES_MODE & GR) == 1'b0 ?
            {2'b00, 1'b0, PAGE2 &  ~STORE80, ~(PAGE2 &  ~STORE80)} :
            {PAGE2 &  ~STORE80, ~(PAGE2 &  ~STORE80), y[2:0]};
        a[15] = 1'b0;
        return a;
    endfunction

    localparam [2:0] TEXT40_LINE = 0;
    localparam [2:0] TEXT80_LINE = 1;
    localparam [2:0] LORES40_LINE = 4;
    localparam [2:0] LORES80_LINE = 5;
    localparam [2:0] HIRES40_LINE = 6;
    localparam [2:0] HIRES80_LINE = 7;


        wire [2:0] line_type_w = (!GR & !EIGHTYCOL) ? TEXT40_LINE :
        (!GR & EIGHTYCOL) ? TEXT80_LINE :
        (GR & !HIRES_MODE & !EIGHTYCOL) ? LORES40_LINE :         // Standard Apple II lores
        (GR & !HIRES_MODE & EIGHTYCOL & !AN3) ? LORES80_LINE :   // IIgs double lores  
        (GR & HIRES_MODE & !EIGHTYCOL) ? HIRES40_LINE :          // Standard Apple II hires
        (GR & HIRES_MODE & EIGHTYCOL & !AN3) ? HIRES80_LINE :    // IIgs double hires
        TEXT40_LINE;

//
// Apple II Graphics Mode Support - Pixel Buffer System
//

// Pixel buffer system (inspired by apple_video.sv but adapted for vgc.v memory timing)
reg [7:0] graphics_pix_shift;    // Shifts out one pixel per clock
reg [3:0] graphics_color;        // Current pixel color
reg graphics_pixel;              // Current pixel value
reg buffer_needs_reload;         // Flag to reload buffer when chram_x increments

// Color artifacting for hires mode (simplified version of apple2hack logic)
reg [3:0] hires_artifact_color;  // Color from artifacting logic (legacy - for lores fallback)

// Current mode detection using existing line_type_w
wire lores_mode = (line_type_w == LORES40_LINE) | (line_type_w == LORES80_LINE);
wire hires_mode = (line_type_w == HIRES40_LINE) | (line_type_w == HIRES80_LINE);
wire graphics_mode = lores_mode | hires_mode;

//
// Text Mode chars are 7 bits wide, not 8
//

// LDPS_N equivalent for memory loading control (inspired by Apple IIe timing)
// This signal controls when to load new character/graphics data
wire ldps_load;
//wire text80_mode = (!GR & EIGHTYCOL);
assign ldps_load = (NEWVIDEO[7]) ? 
                   // SHRG mode timing
                   ((H >= 28 && H < 32) || (H >= 32 && ((EIGHTYCOL && (xpos == 3)) || (!EIGHTYCOL && (xpos == 11))))) :
                   // Apple II mode timing  
                   ((H >= 68 && H < 72) || (H >= 72 && ((EIGHTYCOL && (xpos == 3)) || (!EIGHTYCOL && (xpos == 11)))));

reg [3:0] xpos;
reg [16:0] aux;
always @(posedge clk_vid) 
begin
   if (ce_pix)
   begin
	if ((NEWVIDEO[7] && H<32) || (!NEWVIDEO[7] && H<72))
	begin
		// Early character loading during border period
		// Different timing for SHRG vs Apple II modes
		if (NEWVIDEO[7]) begin
			// SHRG mode: start loading at H=28
			if (H == 26) begin
				if (EIGHTYCOL) begin
					chram_x <= 0;
					aux[16] <= 1'b1;
				end else begin
					chram_x <= 0;
					aux <= 0;
				end
			end else if (H == 28) begin
				buffer_needs_reload <= 1'b1;
			end else if (H == 30) begin
				buffer_needs_reload <= 1'b1;
			end
		end else begin
			// Apple II modes: start loading at H=68
			if (H == 68) begin
				if (EIGHTYCOL) begin
					chram_x <= 0;
					aux[16] <= 1'b1;
				end else begin
					chram_x <= 0;
					aux <= 0;
				end
			end else if (H == 70) begin
				buffer_needs_reload <= 1'b1;
			end
		end
		
		xpos<=0;
		graphics_pix_shift <= 8'b0;
		graphics_color <= 4'b0;
		apple2_shift_reg <= 6'b0;
		pixel_counter <= 11'b0;
	end
	else
	begin
		// Graphics pixel buffer system - coordinate with memory timing
		if (H >= 32 && H <= 100 && V == 16)
			$display("  DEBUG CONDITION: graphics_mode=%b GR=%b line_type=%d condition=%b", graphics_mode, GR, line_type_w, (graphics_mode && GR));
		if (graphics_mode && GR) begin
			// Reload buffer when chram_x changes (new memory data available)
			if (buffer_needs_reload) begin
				if (lores_mode) begin
					// Lores: expand nibbles based on line position
					graphics_pix_shift <= {expandLores40(video_data, window_y_w[2]), 1'b0};
					graphics_color <= window_y_w[2] ? video_data[7:4] : video_data[3:0];
					if (H >= 32 && H <= 100 && V == 16) 
						$display("  LORES RELOAD: H=%d video_data=%h expanded=%b color=%h", H, video_data, {expandLores40(video_data, window_y_w[2]), 1'b0}, window_y_w[2] ? video_data[7:4] : video_data[3:0]);
				end else if (hires_mode) begin
					// Hires: expand pixel bits (0-6), store color bit (7) separately
					graphics_pix_shift <= expandHires40(video_data);
					graphics_color <= {3'b0, video_data[7]};  // Store color/palette bit
					if (H >= 32 && H <= 100 && V == 16) 
						$display("  HIRES RELOAD: H=%d video_data=%h expanded=%b color_bit=%b", H, video_data, expandHires40(video_data), video_data[7]);
				end
				buffer_needs_reload <= 1'b0;
			end else begin
				// Shift pixels out: every clock in 80-col, every 2 clocks in 40-col (pixel doubling)
				// In 40-col mode: shift on odd xpos (1,3,5,7,9,11,13) so each pixel displays twice
				if (EIGHTYCOL || xpos[0] == 1'b1) begin
					graphics_pix_shift <= {1'b0, graphics_pix_shift[7:1]};
					if (H >= 32 && H <= 100 && V == 16) 
						$display("  PIXEL SHIFT: H=%d xpos=%d shift_before=%b shift_after=%b pixel_out=%b", H, xpos, graphics_pix_shift, {1'b0, graphics_pix_shift[7:1]}, graphics_pix_shift[0]);
				end else begin
					// Hold pixel for doubling in 40-column mode
					if (H >= 32 && H <= 100 && V == 16) 
						$display("  PIXEL HOLD: H=%d xpos=%d shift=%b pixel_out=%b", H, xpos, graphics_pix_shift, graphics_pix_shift[0]);
				end
			end
			graphics_pixel <= graphics_pix_shift[0];
			
			// Update Apple II 6-pixel shift register for color artifacting
			apple2_shift_reg <= {graphics_pixel, apple2_shift_reg[5:1]};
			
			// Increment pixel counter for color phase (during active video)
			// Mode-dependent boundaries: SHRG uses full width, Apple II modes are centered
			if (NEWVIDEO[7]) begin
				// SHRG mode: use full 640-pixel width
				if (H >= 32 && H < 672 && V >= 16 && V < 208)
					pixel_counter <= pixel_counter + 1'b1;
				else if (H < 32)
					pixel_counter <= 11'b0; // Reset at start of each line
			end else begin
				// Apple II modes: use centered 560-pixel area with borders
				if (H >= 72 && H < 632 && V >= 16 && V < 208)
					pixel_counter <= pixel_counter + 1'b1;
				else if (H < 72)
					pixel_counter <= 11'b0; // Reset at start of each line
			end
		end

		xpos<=xpos+1'b1;
		if (EIGHTYCOL) begin
		  if (xpos=='d5) begin
		    // Advance memory loading earlier in 80-column mode
		    aux[16]<=~aux[16];                    // Toggle between main/aux every character
		    if (aux[16]==1'b0)                    // Only increment memory address every 2 characters
		      chram_x<=chram_x+1'b1;              // (each memory location holds 2 characters)
		  end
		  if (xpos=='d6) begin
			xpos<=0;
                  end
		end else if (xpos=='d13) begin
			// Advance memory loading earlier in 40-column mode too
			xpos<=0;
			chram_x<=chram_x+1'b1;
		end else if (xpos=='d13) begin
			xpos<=0;
		end
		
		// Use LDPS equivalent for buffer reload timing - but only trigger on edges
		if (ldps_load && !buffer_needs_reload) begin
			buffer_needs_reload <= 1'b1;
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



// Mode-dependent border generation
// Outside total screen area OR inside Apple II mode margin areas
if ((H < 'd32 || H > 'd671 || V < 'd16 || V > 'd207) ||
    (!NEWVIDEO[7] && ((H >= 'd32 && H < 'd72) || (H >= 'd632 && H <= 'd671))))
begin
R <= {BORGB[11:8],BORGB[11:8]};
G <= {BORGB[7:4],BORGB[7:4]};
B <= {BORGB[3:0],BORGB[3:0]};
end
else
begin
    if (NEWVIDEO[7]) begin
        // SHRG mode
        R <= {shrg_r_pix,shrg_r_pix};
        G <= {shrg_g_pix,shrg_g_pix};
        B <= {shrg_b_pix,shrg_b_pix};
    end else if (GR) begin
        // Graphics mode (lores/hires)
        R <= {graphics_rgb[11:8],graphics_rgb[11:8]};
        G <= {graphics_rgb[7:4],graphics_rgb[7:4]};
        B <= {graphics_rgb[3:0],graphics_rgb[3:0]};
    end else begin
        // Text mode
        R <= ~textpixel ? {TRGB[11:8],TRGB[11:8]} : {BRGB[11:8],BRGB[11:8]};
        G <= ~textpixel ? {TRGB[7:4],TRGB[7:4]} : {BRGB[7:4],BRGB[7:4]};
        B <= ~textpixel ? {TRGB[3:0],TRGB[3:0]} : {BRGB[3:0],BRGB[3:0]};
    end
end
end


//assign a = chrom_data_out[chpos_x[2:0]];
// Window coordinates derived from H and V
//wire [9:0] window_x_w = (H >= 32) ? H - 32 : 10'b0;
wire [9:0] window_y_w = (V >= 16) ? V - 16 : 10'b0;

// GR signal calculation for mixed mode support
wire GR = ~(TEXTG | (window_y_w[5] & window_y_w[7] & MIXG));

// Apple II address generation using lineaddr() function
wire [15:0] lineaddr_result = lineaddr(window_y_w);
wire [22:0] video_addr_ii_base = {7'b0, lineaddr_result} + chram_x;

// Text80 mode needs aux memory bank switching
wire text80_mode = (!GR & EIGHTYCOL);
wire use_aux_bank = text80_mode & aux[16];
wire [22:0] video_addr_ii = use_aux_bank ? video_addr_ii_base + 23'h10000 : video_addr_ii_base;

// Character Y position within 8-pixel character cell
wire [2:0] chpos_y = window_y_w[2:0];
assign chrom_addr = { ALTCHARSET,video_data[7:0], chpos_y};


always @(posedge clk_vid) if (ce_pix)
begin
    // Debug text80 and graphics modes - show initial frames only  
    if (H == 32 && V == 16) begin
        $display("MODE: H=%d V=%d TEXTG=%b EIGHTYCOL=%b GR=%b HIRES_MODE=%b AN3=%b text80=%b graphics=%b line_type=%d",
                 H, V, TEXTG, EIGHTYCOL, GR, HIRES_MODE, AN3, text80_mode, graphics_mode, line_type_w);
        $display("Graphics debug: lores_mode=%b hires_mode=%b graphics_color=%h final_graphics_color=%h graphics_pixel=%b",
                 lores_mode, hires_mode, graphics_color, final_graphics_color, graphics_pixel);
        $display("Apple II color: consistent_tint=%b shift_reg=%b color_phase=%d apple2_rgb=%h%h%h",
                 consistent_tint, apple2_shift_reg, color_phase, apple2_r[7:4], apple2_g[7:4], apple2_b[7:4]);
        $display("Video data: video_data=%h video_addr=%h chram_x=%d xpos=%d",
                 video_data, video_addr_ii, chram_x, xpos);
        $display("Pixel timing: graphics_pix_shift=%b buffer_needs_reload=%b",
                 graphics_pix_shift, buffer_needs_reload);
        $display("Text debug: window_y_w=%d chpos_y=%d chrom_addr=%h chrom_data_out=%h textpixel=%b",
                 window_y_w, chpos_y, chrom_addr, chrom_data_out, textpixel);
    end
    
    // Debug character ROM and text pixel output - extensive debugging for a few pixels
    if (H >= 32 && H <= 100 && V == 16 && !GR) begin
        $display("  TEXT PIXEL: H=%d video_data=%h chrom_addr=%h chrom_data=%h xpos=%d textpixel=%b", 
                 H, video_data, chrom_addr, chrom_data_out, xpos, textpixel);
    end
//	$display("V %x oldV %x chram_y %x base_y %x offset %x video_addr %x video_data %x video_data %x %c %x \n",V[8:3],oldV,chram_y,base_y,offset,video_addr,video_data,video_data[6:0],video_data[6:0],chrom_data_out);
end


endmodule
