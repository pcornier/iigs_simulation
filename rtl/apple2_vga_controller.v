//-----------------------------------------------------------------------------
//
// A VGA line-doubler for an Apple ][
//
// Stephen A. Edwards, sedwards@cs.columbia.edu
//
//
// FIXME: This is all wrong
//
// The Apple ][ uses a 14.31818 MHz master clock.  It outputs a new
// horizontal line every 65 * 14 + 2 = 912 14M cycles.  The extra two
// are from the "extended cycle" used to keep the 3.579545 MHz
// colorburst signal in sync.  Of these, 40 * 14 = 560 are active video.
//
// In graphics mode, the Apple effectively generates 140 four-bit pixels
// output serially (i.e., with 3.579545 MHz pixel clock).  In text mode,
// it generates 280 one-bit pixels (i.e., with a 7.15909 MHz pixel clock).
//
// We capture 140 four-bit nibbles for each line and interpret them in
// one of the two modes.  In graphics mode, each is displayed as a
// single pixel of one of 16 colors.  In text mode, each is displayed
// as two black or white pixels.
// 
//-----------------------------------------------------------------------------

module vga_controller(
    CLK_14M,
    VIDEO,
    COLOR_LINE,
    SCREEN_MODE,
    HBL,
    VBL,
    VGA_HS,
    VGA_VS,
    VGA_HBL,
    VGA_VBL,
    VGA_R,
    VGA_G,
    VGA_B,
    BRGB
);
    input            CLK_14M;		// 14.31818 MHz master clock
    
    input            VIDEO;		// from the Apple video generator
    input            COLOR_LINE;
    input [1:0]      SCREEN_MODE;		// 00: Color, 01: B&W, 10: Green, 11: Amber
    input            HBL;
    input            VBL;
    
    output reg       VGA_HS;
    output reg       VGA_VS;
    output           VGA_HBL;
    output           VGA_VBL;
    output reg [7:0] VGA_R;
    output reg [7:0] VGA_G;
    output reg [7:0] VGA_B;
    input      [11:0] BRGB; 
    
    // RGB values from Linards Ticmanis (posted on comp.sys.apple2 on 29-Sep-2005)
    // https://groups.google.com/g/comp.sys.apple2/c/uILy74pRsrk/m/G9XDxQhWi1AJ
    
    /*
    parameter [7:0]  basis_r[0:3] = {8'h88, 8'h38, 8'h07, 8'h38};
    parameter [7:0]  basis_g[0:3] = {8'h22, 8'h24, 8'h67, 8'h52};
    parameter [7:0]  basis_b[0:3] = {8'h2C, 8'hA0, 8'h2C, 8'h07};
    */
    reg [7:0]  basis_r[0:3];
    reg [7:0]  basis_g[0:3];
    reg [7:0]  basis_b[0:3];
    
    reg [5:0]        shift_reg;		// Last six pixels
    
    reg              last_hbl;
    reg [10:0]       hcount;
    reg [5:0]        vcount;
    
    parameter        VGA_HSYNC = 68;
    parameter        VGA_ACTIVE = 282 * 2;
    parameter        VGA_FRONT_PORCH = 130;
    
    parameter        VBL_TO_VSYNC = 33;
    parameter        VGA_VSYNC_LINES = 3;
    
    reg              vbl_delayed;
    reg [17:0]       de_delayed;
    
    
    always @(posedge CLK_14M)
        
        begin
            if (last_hbl == 1'b1 & HBL == 1'b0)		// Falling edge
            begin
                hcount <= {11{1'b0}};
                vbl_delayed <= VBL;
                if (VBL == 1'b1)
                    vcount <= vcount + 1;
                else
                    vcount <= {6{1'b0}};
            end
            else
                hcount <= hcount + 1;
            last_hbl <= HBL;
        end
    
    
    always @(posedge CLK_14M)
        
        begin
            if (hcount == VGA_ACTIVE + VGA_FRONT_PORCH)
            begin
                VGA_HS <= 1'b1;
                if (vcount == VBL_TO_VSYNC)
                    VGA_VS <= 1'b1;
                else if (vcount == VBL_TO_VSYNC + VGA_VSYNC_LINES)
                    VGA_VS <= 1'b0;
            end
            else if (hcount == VGA_ACTIVE + VGA_FRONT_PORCH + VGA_HSYNC)
                VGA_HS <= 1'b0;
        end
    
        initial begin
    basis_r[0] = 8'h88;
    basis_g[0] = 8'h22;
    basis_b[0] = 8'h2C;
    basis_r[1] = 8'h38;
    basis_g[1] = 8'h24;
    basis_b[1] = 8'hA0;
    basis_r[2] = 8'h07;
    basis_g[2] = 8'h67;
    basis_b[2] = 8'h2C;
    basis_r[3] = 8'h38;
    basis_g[3] = 8'h52;
    basis_b[3] = 8'h07;
	end	
    
    always @(posedge CLK_14M)
    begin: xhdl0
        reg [7:0]        r;
        reg [7:0]        g;
        reg [7:0]        b;
        begin
            shift_reg <= {VIDEO, shift_reg[5:1]};
            
            r = 8'h00;
            g = 8'h00;
            b = 8'h00;
            
            // alternate background for monochrome modes
            case (SCREEN_MODE)
                2'b00 :		// color mode background
                    begin
			r = {BRGB[11:8],BRGB[11:8]};
			g = {BRGB[7:4],BRGB[7:4]};
			b = {BRGB[3:0],BRGB[3:0]};
                        //r = 8'h00;
                        //g = 8'h00;
                        //b = 8'h00;
                    end
                2'b01 :		// B&W mode background
                    begin
                        r = 8'h00;
                        g = 8'h00;
                        b = 8'h00;
                    end
                2'b10 :		// green mode background color
                    begin
                        r = 8'h00;
                        g = 8'h0F;
                        b = 8'h01;
                    end
                2'b11 :		// amber mode background color
                    begin
                        r = 8'h20;
                        g = 8'h08;
                        b = 8'h01;
                    end
                default :
                    ;
            endcase
            
            if (COLOR_LINE == 1'b0)		// Monochrome mode
            begin
                
                if (shift_reg[2] == 1'b1)
                    // handle green/amber color modes
                    case (SCREEN_MODE)
                        2'b00 :		// white (color mode)
                            begin
                                r = 8'hFF;
                                g = 8'hFF;
                                b = 8'hFF;
                            end
                        2'b01 :		// white (B&W mode)
                            begin
                                r = 8'hFF;
                                g = 8'hFF;
                                b = 8'hFF;
                            end
                        2'b10 :		// green
                            begin
                                r = 8'h00;
                                g = 8'hC0;
                                b = 8'h01;
                            end
                        2'b11 :		// amber 
                            begin
                                r = 8'hFF;
                                g = 8'h80;
                                b = 8'h01;
                            end
                        default :
                            ;
                    endcase
            end
            else if (shift_reg[0] == shift_reg[4] & shift_reg[5] == shift_reg[1])
            begin
                
                // Tint of adjacent pixels is consistent : display the color
                if (shift_reg[3] == 1'b1)
                begin
                    r = r + basis_r[(hcount + 1)];
                    g = g + basis_g[(hcount + 1)];
                    b = b + basis_b[(hcount + 1)];
                end
                if (shift_reg[4] == 1'b1)
                begin
                    r = r + basis_r[(hcount + 2)];
                    g = g + basis_g[(hcount + 2)];
                    b = b + basis_b[(hcount + 2)];
                end
                if (shift_reg[1] == 1'b1)
                begin
                    r = r + basis_r[(hcount + 3)];
                    g = g + basis_g[(hcount + 3)];
                    b = b + basis_b[(hcount + 3)];
                end
                if (shift_reg[2] == 1'b1)
                begin
                    r = r + basis_r[hcount];
                    g = g + basis_g[hcount];
                    b = b + basis_b[hcount];
                end
            end
            else
                
                // Tint is changing: display only black, gray, or white
                case (shift_reg[3:2])
                    2'b11 :
                        begin
                            r = 8'hFF;
                            g = 8'hFF;
                            b = 8'hFF;
                        end
                    2'b01, 2'b10 :
                        begin
                            r = 8'h80;
                            g = 8'h80;
                            b = 8'h80;
                        end
                    default :
                        begin
                            r = 8'h00;
                            g = 8'h00;
                            b = 8'h00;
                        end
                endcase
            
            VGA_R <= r;
            VGA_G <= g;
            VGA_B <= b;
            
            de_delayed <= {de_delayed[16:0], last_hbl};
        end
    end
    
    assign VGA_VBL = vbl_delayed;
    assign VGA_HBL = de_delayed[9] & de_delayed[17];
    
endmodule
