
module vgc (
input CLK_28M,
input CLK_14M,
input clk_vid,
input ce_pix,
input[9:0] H,
input[8:0] V,
output reg scanline_irq,

output vbl_irq,
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
// NEWVIDEO[6] controls CPU memory mapping, but VGC always uses linear addressing for SHR video
// When NEWVIDEO[7]=1 (SHR mode), the video buffer is always $2000-$9CFF with SCBs at $9D00
wire linear_mode = 1'b1;

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
	// load SCB - For display, V=32 uses SCB[1], V=33 uses SCB[2], etc.
	// The +1 offset means SCB[0] is read at V=31 (for interrupt check only)
	if (H=='h38c) begin
		if (linear_mode)
		begin
			video_addr_shrg <= 'h19D00+(V-'d32+1);
		end
		else
		begin
		// Non-linear mode: odd/even scanlines use different banks
		// Scanline N maps to: odd->$9D00+N/2, even->$5D00+N/2
		// Since V=32 is scanline 0, index = (V-32)>>1
		if (V[0])
			video_addr_shrg <= 'h19D00+((V-'d32)>>1);  // Odd scanlines
		else
			video_addr_shrg <= 'h15D00+((V-'d32)>>1);  // Even scanlines
		end
	end
	else if (H=='h38e) begin
		scb <= video_data;
		// Check for scanline interrupt: SCB bit 6, SHR mode enabled, valid scanline range
		// V >= 31 allows SCB[0] interrupt to fire at V=31 (just before scanline 0 displays at V=32)
		if (video_data[6] && NEWVIDEO[7] && V >= 'd31 && V < 'd206)
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
			// Note: Due to address pre-increment at H=0x390, first read is at ODD address
			// So odd addresses are read first for each color entry
			if (video_addr_shrg[0]) begin
		                //$display("GB PALETTE = %x addr %x  color index %x",video_data,video_addr_shrg,pal_counter);
				b_shrg[pal_counter]<=video_data[3:0];
				g_shrg[pal_counter]<=video_data[7:4];
			end else begin
		                //$display("R PALETTE = %x addr %x color index %x",video_data,video_addr_shrg,pal_counter);
				r_shrg[pal_counter]<=video_data[3:0];
				pal_counter<=pal_counter+1;
			end
			video_addr_shrg <= video_addr_shrg + 1'b1;
			video_addr_shrg_1 <= video_addr_shrg_1 +1'b1;
		end
		else begin
			// Non-linear mode palette reading
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
				video_addr_shrg_1 <= 'h12000 + ((V-32) * 'd160);  // AJS REMOVE MULTIPLY??
				video_addr_shrg <= 'h12000 + ((V-32) * 'd160);  // AJS REMOVE MULTIPLY??
				video_addr_shrg_2 <= 'h11fff + ((V-32) * 'd160);  // AJS REMOVE MULTIPLY??
			end
			else
			begin
				//$display("NONLINEAR NEWVIDEO 6 MODE");
				video_addr_shrg_1 <= 'h12000 + ((V-32) * 'd80);  // AJS REMOVE MULTIPLY??
				video_addr_shrg <= 'h12000 + ((V-32) * 'd80);  // AJS REMOVE MULTIPLY??
				video_addr_shrg_2 <= 'h16000 + ((V-32) * 'd80);  // AJS REMOVE MULTIPLY??
			end
			h_counter<=0;
			base_toggle<=0;
		end
	end else if (H < ('d32+640)) begin
		h_counter<=h_counter+1'b1;
		// Only advance address for first 159 advances (byte 0->159), skip the 160th
		// With 1-cycle display shift, advance #159 happens at H=667, so skip advance at H>=668
		if (h_counter==2'd2 && H < 'd668)
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

// Flash counter for blinking text (~2Hz, toggles every ~0.25 seconds)
reg [22:0] flash_cnt;
always @(posedge clk_vid) if (ce_pix) flash_cnt <= flash_cnt + 1'b1;
wire flash_state = flash_cnt[21];

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
// Color phase for NTSC artifact colors - needs to be aligned with actual Apple II timing
// The base phase comes from H position with an offset for correct alignment.
// Bit 7 of the hires byte (stored in graphics_color[0]) shifts the phase by 1,
// selecting between violet/green (bit7=0) and blue/orange (bit7=1) palettes.
wire [1:0] color_phase_base = (H[1:0] + 2'b11) & 2'b11; // Offset by 3 for base alignment
wire [1:0] color_phase = (color_phase_base + {1'b0, graphics_color[0]}) & 2'b11;

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

        // Use NTSC color artifacting for ALL hires modes (including DHIRES)
        // The dhires_mode monochrome rendering was breaking games like 8bit-Slicks
        // that run in standard HIRES but with EIGHTYCOL left set by menu software.
        // True DHIRES color (16-color) mode would need different handling.
        if (consistent_tint) begin
            // Regular hires with consistent tint: display color using basis vectors
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
wire  [ 4:0] vert = V[7:3]-5'h04;  // Changed from 5'h02 (V-16) to 5'h04 (V-32)
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
// KEGS font data: 1 = foreground pixel, 0 = background pixel
// No inversion needed for KEGS-based chr.mem
wire [7:0] chrom_data_inv = chrom_data_out;
wire [11:0] chram_addr;
wire [11:0] chrom_addr;

// Text mode shift register for FPGA-compatible timing
// The character ROM has 1-cycle latency, so we need to pre-fetch and buffer
// Load the ROM data into a shift register, then shift out pixels
reg [6:0] text_shift_reg;
reg [7:0] video_data_text;  // Latched video data for character ROM addressing
reg text_load_pending;      // Flag to load shift register when ROM data is ready

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
// Text pixel output from shift register (FPGA-compatible with sync ROM)
wire textpixel = text_shift_reg[0];

    // Regular Hires - Apple II hi-res: 7 pixels per byte (bits 0-6), bit 7 is color/palette
    // Emit 7 pixel bits LSB-first and replicate the last pixel into the pad bit.
    // This prevents a black seam if an extra shift occurs before the next reload.
    function automatic bit [7:0] expandHires40([7:0] vd);
        reg [7:0] vs;
        vs = {vd[6], vd[6:0]};  // replicate last pixel instead of zero padding
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


        // Line type detection for Apple II video modes
// AN3 controls whether EIGHTYCOL selects double-width modes:
// - AN3=1: Standard Apple II modes (40-column), EIGHTYCOL ignored for graphics
// - AN3=0: IIgs double modes (80-column) when EIGHTYCOL=1
// For text modes, EIGHTYCOL always controls 40/80 column selection
wire [2:0] line_type_w = (!GR & !EIGHTYCOL) ? TEXT40_LINE :
        (!GR & EIGHTYCOL) ? TEXT80_LINE :
        (GR & !HIRES_MODE & (AN3 | !EIGHTYCOL)) ? LORES40_LINE :  // Standard Apple II lores (AN3=1 OR EIGHTYCOL=0)
        (GR & !HIRES_MODE & !AN3 & EIGHTYCOL) ? LORES80_LINE :    // IIgs double lores (AN3=0 AND EIGHTYCOL=1)
        (GR & HIRES_MODE & (AN3 | !EIGHTYCOL)) ? HIRES40_LINE :   // Standard Apple II hires (AN3=1 OR EIGHTYCOL=0)
        (GR & HIRES_MODE & !AN3 & EIGHTYCOL) ? HIRES80_LINE :     // IIgs double hires (AN3=0 AND EIGHTYCOL=1)
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

// Current graphics pixel output (combinational for immediate display, no pipeline delay)
// During buffer reload, output the first pixel of the new byte directly
// For lores mode, bit 0 of expanded data is the high nibble bit 0 (upper half) or low nibble bit 0 (lower half)
// For hires mode, bit 0 of video_data is first pixel (LSB-first)
// Note: expandLores40 returns {nibble[3],nibble[2],nibble[1],nibble[0],nibble[3],nibble[2],nibble[1]}
// so bit 0 is nibble[1], but we just need any valid pixel - use nibble bit directly
wire lores_reload_pixel = window_y_w[2] ? video_data[5] : video_data[1];  // bit 1 of active nibble
wire graphics_pixel_out = buffer_needs_reload ?
    (lores_mode ? lores_reload_pixel : video_data[0]) :
    graphics_pix_shift[0];

//
// Text Mode chars are 7 bits wide, not 8
//

// LDPS_N equivalent for memory loading control (inspired by Apple IIe timing)
// This signal controls when to load new character/graphics data
wire ldps_load;
//wire text80_mode = (!GR & EIGHTYCOL);
// ldps_load triggers buffer reload. For 40-col mode, we need 2+ cycles between
// chram_x increment and reload for memory latency:
// - xpos=10: ldps_load triggers buffer_needs_reload
// - xpos=11: chram_x increments (address changes, registered)
// - xpos=12: video_addr_ii updates (combinational from new chram_x)
// - xpos=13: video_data valid (after memory latency)
// - xpos=0 (next char): reload from valid video_data
// So ldps_load at xpos=10 gives us reload at xpos=11, which is still too early.
// We need reload to happen AFTER video_data is valid at xpos=13.
// Solution: change ldps_load to xpos=12 so reload happens at xpos=13 when data is ready.
assign ldps_load = (NEWVIDEO[7]) ?
                   // SHRG mode timing
                   ((H >= 28 && H < 32) || (H >= 32 && ((EIGHTYCOL && (xpos == 3)) || (!EIGHTYCOL && (xpos == 12))))) :
                   // Apple II mode timing
                   ((H >= 68 && H < 72) || (H >= 72 && ((EIGHTYCOL && (xpos == 3)) || (!EIGHTYCOL && (xpos == 12)))));

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
			// Pre-fetch timing: chram_x=0 at H=68, reload at H=71, data ready at H=72
			if (H == 68) begin
				if (EIGHTYCOL) begin
					chram_x <= 0;
					aux[16] <= 1'b1;
				end else begin
					chram_x <= 0;
					aux <= 0;
				end
			end else if (H == 71) begin
				// Pre-load the shift register at H=71 so first pixel is ready at H=72
				// This is the ONLY place where we load during the init block
				if (hires_mode) begin
					graphics_pix_shift <= expandHires40(video_data);
					graphics_color <= {3'b0, video_data[7]};
				end else if (lores_mode) begin
					graphics_pix_shift <= {expandLores40(video_data, window_y_w[2]), 1'b0};
					graphics_color <= window_y_w[2] ? video_data[7:4] : video_data[3:0];
				end
			end
		end

		xpos<=0;
		// Only clear graphics shift register early in the line (before pre-load)
		if (H < 71) begin
			graphics_pix_shift <= 8'b0;
			graphics_color <= 4'b0;
		end
		apple2_shift_reg <= 6'b0;
		graphics_pixel <= 1'b0;
		pixel_counter <= 11'b0;
		text_shift_reg <= 7'b0;
		text_load_pending <= 1'b0;
	end
	else
	begin
		// Graphics pixel buffer system - coordinate with memory timing
		// Debug start and end of line to check horizontal alignment
		if (((H >= 70 && H <= 90) || (H >= 620 && H <= 640)) && V == 100 && hires_mode)
			$display("HPIX: H=%d xpos=%d chram_x=%d reload=%b shift=%b pixel=%b video_data=%h",
			         H, xpos, chram_x, buffer_needs_reload, graphics_pix_shift, graphics_pix_shift[0], video_data);
		if (graphics_mode && GR) begin
			// Reload buffer when chram_x changes (new memory data available)
			if (buffer_needs_reload) begin
				if (lores_mode) begin
					// Lores: expand nibbles based on line position
					graphics_pix_shift <= {expandLores40(video_data, window_y_w[2]), 1'b0};
					graphics_color <= window_y_w[2] ? video_data[7:4] : video_data[3:0];
`ifdef VGC_DEBUG
					if (H >= 32 && H <= 100 && V == 32) 
						$display("  LORES RELOAD: H=%d video_data=%h expanded=%b color=%h", H, video_data, {expandLores40(video_data, window_y_w[2]), 1'b0}, window_y_w[2] ? video_data[7:4] : video_data[3:0]);
`endif
				end else if (hires_mode) begin
					// Hires: expand pixel bits (0-6), store color bit (7) separately
					// Always store bit 7 for color phase - even in "DHIRES" mode since
					// games like 8bit-Slicks run with EIGHTYCOL set but still need color
					graphics_pix_shift <= expandHires40(video_data);
					graphics_color <= {3'b0, video_data[7]};  // Store color/palette bit
				end
				buffer_needs_reload <= 1'b0;
			end else begin
				// Shift pixels out: every clock in 80-col, every 2 clocks in 40-col (pixel doubling)
				// In 40-col mode: shift on odd xpos (1,3,5,7,9,11,13) so each pixel displays twice
                if (EIGHTYCOL || xpos[0] == 1'b1) begin
                    // Shift with last-pixel fill to avoid introducing black seams
                    graphics_pix_shift <= {graphics_pix_shift[0], graphics_pix_shift[7:1]};
`ifdef VGC_DEBUG
                    if (H >= 32 && H <= 100 && V == 32) 
                        $display("  PIXEL SHIFT: H=%d xpos=%d shift_before=%b shift_after=%b pixel_out=%b", H, xpos, graphics_pix_shift, {graphics_pix_shift[0], graphics_pix_shift[7:1]}, graphics_pix_shift[0]);
`endif
                end else begin
					// Hold pixel for doubling in 40-column mode
`ifdef VGC_DEBUG
					if (H >= 32 && H <= 100 && V == 32) 
						$display("  PIXEL HOLD: H=%d xpos=%d shift=%b pixel_out=%b", H, xpos, graphics_pix_shift, graphics_pix_shift[0]);
`endif
				end
			end
			graphics_pixel <= graphics_pix_shift[0];
			
			// Update Apple II 6-pixel shift register for color artifacting
			apple2_shift_reg <= {graphics_pixel, apple2_shift_reg[5:1]};
			
			// Increment pixel counter for color phase (during active video)
			// Mode-dependent boundaries: SHRG uses full width, Apple II modes are centered
			if (NEWVIDEO[7]) begin
				// SHRG mode: use full 640-pixel width (within 704 visible area)
				if (H >= 32 && H < 672 && V >= 32 && V < 232)
					pixel_counter <= pixel_counter + 1'b1;
				else if (H < 32)
					pixel_counter <= 11'b0; // Reset at start of each line
			end else begin
				// Apple II modes: 192 lines starting at V=32 (scanline 0 to 191)
				if (H >= 72 && H < 632 && V >= 32 && V < 224)
					pixel_counter <= pixel_counter + 1'b1;
				else if (H < 72)
					pixel_counter <= 11'b0; // Reset at start of each line
			end
		end

		xpos<=xpos+1'b1;

		// Text mode shift register management (FPGA-compatible sync ROM timing)
		// ROM has 1-cycle latency, so we pre-fetch and buffer in shift register
		if (!GR) begin
			if (EIGHTYCOL) begin
				// 80-column text mode: 7 pixels per character (xpos 0-6)
				// Timing: xpos=4: set address, xpos=5: video_data ready, xpos=6: ROM ready
				// At xpos=0: load shift register with pre-fetched ROM data
				if (xpos == 'd0) begin
					// Load shift register with ROM data (ready from pre-fetch)
					text_shift_reg <= chrom_data_inv[6:0];
					// Latch video_data for this character's ROM addressing
					video_data_text <= video_data;
				end else begin
					// Shift out pixels LSB first (shift right, read bit 0)
					text_shift_reg <= {1'b0, text_shift_reg[6:1]};
				end
			end else begin
				// 40-column text mode: 14 pixels per character (xpos 0-13), pixel doubled
				// Each pixel displays twice (even xpos shows pixel, odd xpos shifts to next)
				if (xpos == 'd0) begin
					// Load shift register with ROM data
					text_shift_reg <= chrom_data_inv[6:0];
					video_data_text <= video_data;
				end else if (xpos[0] == 1'b0 && xpos != 'd0) begin
					// Shift on EVEN xpos (2,4,6,8,10,12) for pixel doubling
					// This way: xpos 0-1 show bit0, xpos 2-3 show bit1, etc.
					text_shift_reg <= {1'b0, text_shift_reg[6:1]};
				end
				// Odd xpos (1,3,5,7,9,11,13): hold for pixel doubling
			end
		end

		if (EIGHTYCOL) begin
		  if (xpos=='d4) begin
		    // Pre-fetch: advance memory 1 cycle earlier for sync ROM timing
		    // This gives memory 1 cycle to respond, then ROM 1 cycle
		    aux[16]<=~aux[16];                    // Toggle between main/aux every character
		    if (aux[16]==1'b0)                    // Only increment memory address every 2 characters
		      chram_x<=chram_x+1'b1;              // (each memory location holds 2 characters)
		  end
		  if (xpos=='d6) begin
			xpos<=0;
                  end
        end else if (xpos=='d11 && !EIGHTYCOL) begin
            // Pre-fetch for 40-column mode: increment address 2 cycles early
            // xpos=11: address changes, xpos=12: video_data ready, xpos=13: ROM ready
            // This gives memory + ROM time to respond before xpos=0
            chram_x<=chram_x+1'b1;
        end else if (xpos=='d13) begin
            // 40-column mode: wrap xpos at end of character (no chram_x inc here)
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

// VBL starts at end of active display (line 232)




// Mode-dependent border generation (704-pixel visible area, H=0-703)
// Apple II TEXT modes: |Left Border(72px)|Active Display(560px)|Right Border(72px)| = 704 total
//   Text has minimal pipeline latency, uses original timing
// Apple II GFX modes:  |Left Border(77px)|Active Display(560px)|Right Border(67px)| = 704 total
//   Graphics has 5-pixel pipeline latency (apple2_shift_reg), shift border right
// SHRG modes:          |Left Border(32px)|Active Display(640px)|Right Border(32px)| = 704 total
// Border generation:
// Apple II TEXT: active display H=72-631 (560 pixels), V=32-223 (192 lines)
// Apple II GFX:  active display H=77-636 (560 pixels), V=32-223 (192 lines)
// SHRG modes:    active display H=32-671 (640 pixels), V=32-231 (200 lines)
if ((!NEWVIDEO[7] && GR && ((H < 'd77 || H > 'd636) || (V < 'd32 || V >= 'd224))) ||
    (!NEWVIDEO[7] && !GR && ((H < 'd72 || H > 'd631) || (V < 'd32 || V >= 'd224))) ||
    (NEWVIDEO[7] && ((H < 'd32 || H >= 'd672 || V < 'd32 || V >= 'd232))))
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
        // Text mode - textpixel is inverted at ROM level (like a2fpga)
        // textpixel=1 means foreground/text color, textpixel=0 means background
        R <= textpixel ? {TRGB[11:8],TRGB[11:8]} : {BRGB[11:8],BRGB[11:8]};
        G <= textpixel ? {TRGB[7:4],TRGB[7:4]} : {BRGB[7:4],BRGB[7:4]};
        B <= textpixel ? {TRGB[3:0],TRGB[3:0]} : {BRGB[3:0],BRGB[3:0]};
    end
end
end


//assign a = chrom_data_out[chpos_x[2:0]];
// Window coordinates derived from H and V
// Apple II modes: Active display H=72-632 (560 pixels for 40 chars × 14 pixels)
// SHRG modes: Active display H=32-672 (640 pixels)
wire [9:0] window_x_w = NEWVIDEO[7] ? 
    ((H >= 32) ? H - 32 : 10'b0) :          // SHRG: start at H=32
    ((H >= 72) ? H - 72 : 10'b0);           // Apple II: start at H=72
wire [9:0] window_y_w = (V >= 32) ? V - 32 : 10'b0;  // Apple II display starts at V=32 (scanline 0)

// Apple II coordinate mapping: Now properly centered, window_y_w is 0-191 (192 lines)
// No clamping needed since we're properly centered within the 200-line area
wire [7:0] apple_ii_y_clamped = window_y_w[7:0];

// GR signal calculation for mixed mode support  
// Mixed mode should switch to text at y=160 in Apple II coordinates (192-line system)
wire mixed_mode_active = (apple_ii_y_clamped >= 160) & MIXG;
wire GR = ~(TEXTG | mixed_mode_active);

// Apple II address generation using lineaddr() function with clamped coordinates
wire [15:0] lineaddr_result = lineaddr({2'b0, apple_ii_y_clamped});
wire [22:0] video_addr_ii_base = {7'b0, lineaddr_result} + chram_x;

// 80-column modes (text80 and double hi-res) need aux memory bank switching
wire text80_mode = (!GR & EIGHTYCOL);
wire dhires_mode = (GR & HIRES_MODE & EIGHTYCOL & !AN3);  // Double Hi-Res mode
wire use_aux_bank = (text80_mode | dhires_mode) & aux[16];
wire [22:0] video_addr_ii = use_aux_bank ? video_addr_ii_base + 23'h10000 : video_addr_ii_base;

// Character Y position within 8-pixel character cell (using clamped coordinates)
wire [2:0] chpos_y = apple_ii_y_clamped[2:0];

// Character ROM address calculation with proper attribute handling (a2fpga-style)
// The Apple II character set uses bits 6-7 for display attributes:
//   $00-$3F (bit 7=0, bit 6=0): Inverse characters
//   $40-$7F (bit 7=0, bit 6=1): Flash (primary) or MouseText (alternate charset)
//   $80-$FF (bit 7=1): Normal characters
// ROM address format (12 bits total):
//   bit 11: always 0
//   bit 10: normal char OR (flash char AND flash_state AND primary charset)
//   bit 9:  flash/mousetext bit AND (ALTCHARSET OR normal char)
//   bits 8:3: character code lower 6 bits (video_data[5:0])
//   bits 2:0: row within character (chpos_y)
wire chrom_bit10 = video_data[7] | (video_data[6] & flash_state & ~ALTCHARSET);
wire chrom_bit9 = video_data[6] & (ALTCHARSET | video_data[7]);
assign chrom_addr = {1'b0, chrom_bit10, chrom_bit9, video_data[5:0], chpos_y};

// Debug: trace MouseText character rendering
// Uncomment to see what's happening with specific characters
`define DEBUG_MOUSETEXT 1
`ifdef DEBUG_MOUSETEXT
always @(posedge clk_vid) if (ce_pix) begin
    // Trace any MouseText character (0x40-0x5F range with ALTCHARSET)
    if (H >= 72 && H <= 200 && V >= 80 && V <= 88 && !GR && text80_mode &&
        ALTCHARSET && video_data >= 8'h40 && video_data < 8'h60 && xpos == 0) begin
        $display("MT: H=%d V=%d chpos_y=%d vdata=%h addr=%h data=%h bits=%b%b%b%b%b%b%b",
                 H, V, chpos_y, video_data, chrom_addr, chrom_data_out,
                 chrom_data_out[6], chrom_data_out[5], chrom_data_out[4],
                 chrom_data_out[3], chrom_data_out[2], chrom_data_out[1], chrom_data_out[0]);
    end
end
`endif

always @(posedge clk_vid) if (ce_pix)
begin
    // Debug text80 and graphics modes - show initial frames only
    if (H == 32 && V == 32) begin
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
    
    // Debug disabled
    // if (H >= 72 && H <= 130 && V == 56 && !GR && text80_mode) begin
    //     $display("  80COL: H=%d V=%d video_data=%h aux=%b chram_x=%d xpos=%d addr=%h use_aux=%b",
    //              H, V, video_data, aux[16], chram_x, xpos, video_addr_ii, use_aux_bank);
    // end
//	$display("V %x oldV %x chram_y %x base_y %x offset %x video_addr %x video_data %x video_data %x %c %x \n",V[8:3],oldV,chram_y,base_y,offset,video_addr,video_data,video_data[6:0],video_data[6:0],chrom_data_out);
end



`ifdef SIMULATION
/*
    reg [8:0] V_d;
    always @(posedge clk_vid) if(ce_pix) begin
        V_d <= V;
        if (V != V_d) begin
            $display("VGC_DEBUG @ %0t: V counter changed to %d", $time, V);
        end
    end
*/
`endif


// VBL Pulse Generation
// Generate a single-cycle pulse at the start of the vertical blanking interval
// to avoid IRQ storms.
wire v_blank = (V >= 199);
reg v_blank_d;
always @(posedge clk_vid) if(ce_pix) v_blank_d <= v_blank;
assign vbl_irq = v_blank & ~v_blank_d;

endmodule
