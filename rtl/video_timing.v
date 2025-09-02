

module video_timing(

  input clk_vid,
  input ce_pix,

  output hsync,
  output vsync,
  output hblank,
  output vblank,

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
// Layout: |Left Border(32px)|Active Display(640px)|Right Border(32px)|H-Sync|
parameter BORDER_WIDTH = 32;
parameter ACTIVE_WIDTH = 640;
parameter HFP = ACTIVE_WIDTH + 2*BORDER_WIDTH; // Total visible area (704 pixels)
parameter HSP = HFP + 48;   // Start horizontal sync (752)
parameter HBP = HSP + 64;   // End horizontal sync (816)
parameter HWL = HBP + 96;   // Total line width (912 pixels)

// Vertical Timing (262 lines total - NTSC standard)
// Layout: |Top Border(32)|Active Display(200)|Bottom Border(30)| = 262 total
parameter V_TOP_BORDER = 32;    // Top border lines
parameter V_ACTIVE = 200;       // Active display lines (Super Hi-Res)
parameter V_BOTTOM_BORDER = 30; // Bottom border lines

parameter VFP = V_TOP_BORDER + V_ACTIVE;        // 232 - End of active display
parameter VSP = VFP + (V_BOTTOM_BORDER/2);     // 247 - Start vertical sync
parameter VBP = VSP + 3;                       // 250 - End vertical sync  
parameter VWL = V_TOP_BORDER + V_ACTIVE + V_BOTTOM_BORDER; // 262 - Total frame

assign hsync = ~((hcount >= HSP) && (hcount < HBP));
assign vsync = ~((vcount >= VSP) && (vcount < VBP));

assign hblank = hcount >= HFP;
assign vblank = vcount >= 232;  // VBlank starts at line 232 (after active display)

always @(posedge clk_vid) if (ce_pix) begin
  hcount <= hcount + 11'd1;
  if (hcount == HWL) hcount <= 0;
end

always @(posedge clk_vid) if (ce_pix) begin
  if (hcount == HWL) begin
    if (vcount == VWL)
      vcount <= 0;
    else
      vcount <= vcount + 10'd1;
  end
end


endmodule

