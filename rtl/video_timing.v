

module video_timing(

  input clk_vid,
  input ce_pix,

  output reg hsync,
  output reg vsync,
  output reg hblank,
  output reg vblank,

  output reg mega2_vbl, // Legacy vblank state at $C019

  output [10:0] hpos,
  output [9:0] vpos

);

assign hpos = hcount;
assign vpos = vcount;

reg [10:0] hcount;
reg [9:0] vcount;


//https://www.improwis.com/tables/video.webt
//                                                                             pixel     front       back   front       back
//                                            Htotal Vtotal     hsync   vsync   clock     porch hsync porch  porch vsync porch
//    mode       name      res                pixels lines      kHz  pol pol     MHz       pix   pix   pix   lines lines lines
//a   arcade monitor        512x240@60.0       632    262      15.7199 - -       9.935        8    47   65      1    3   18        arcade/game modelines; fixed hsync freq arcade monitor
// Apple IIgs Video Timing (Super Hi-Res compatible)
// Based on: 640x200 active display, 912x262 total frame, ~60Hz NTSC
// Visible area: 640x200 pixels with proper borders
// Total frame: 912x262 (NTSC standard)

// Horizontal Timing (912 pixels total)
// Layout: |Left Border(44px)|Active Display(640px)|Right Border(60px)|H-Sync|
parameter H_BORDER = 104;
parameter H_ACTIVE = 640;
parameter HFP = H_ACTIVE + H_BORDER - 1; // Total visible area (744 pixels)
parameter HSP = HFP + 14;                // Start horizontal sync (758)
parameter HBP = HSP + 56;                // End horizontal sync (814)
parameter HWL = HBP + 98;                // Total line width (count 911, 912 pixels)

// Vertical Timing (262 lines total - NTSC standard)
// Layout: |Top Border(19)|Active Display(200)|Bottom Border(21)|Blanking(22)| = 262 total
parameter B_BORDER = 21;   // Bottom border lines
parameter V_ACTIVE = 200;  // Active display lines (Super Hi-Res)
parameter V_BLANKING = 22; // Blanking lines

// This uses the legacy Apple II V counter scheme, which counts from
// 250 to 511 rather than 0 to 261. This count is visible to the CPU
// at $C02E/F, and structured so that V[7:0] is the current line
// during the buffer scanout period. The main downside is that this
// causes the counter reset to occur during the top border period
// rather than at a transition.
parameter V_LOAD = 250;                           // remainder of top border
parameter V_SCAN = 256;                           // Buffer scanout
parameter VFP = V_SCAN + B_BORDER + V_ACTIVE - 1; // Front porch
parameter VSP = VFP + 3;                          // vsync
parameter VBP = VSP + 4;                          // back porch
parameter VTB = VBP + 15;                         // top border
parameter V_END = 10'd511;                        // counter resets

parameter V_M2_VBL = V_SCAN + 191;

always @(posedge clk_vid) if (ce_pix) begin
  hcount <= hcount + 11'd1;

  case (hcount)
    HFP: hblank <= 1;
    HSP: hsync <= 0;
    HBP: hsync <= 1;
    HWL: begin hblank <= 0; hcount <= 0; end
  endcase // case (hcount)
end

always @(posedge clk_vid) if (ce_pix && hcount == HWL) begin
  vcount <= vcount + 10'd1;

  case (vcount)
    V_M2_VBL: mega2_vbl <= 1;
    V_SCAN: mega2_vbl <= 0;
    VFP: vblank <= 1;
    VSP: vsync <= 0;
    VBP: vsync <= 1;
    VTB: vblank <= 0;
    V_END: vcount <= V_LOAD;
  endcase // case (vcount)
end

endmodule

