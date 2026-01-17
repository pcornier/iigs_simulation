

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
// Layout: |Left Border(44px)|Active Display(640px)|Right Border(60px)|H-Sync|
parameter H_BORDER = 104;
parameter H_ACTIVE = 640;
parameter HFP = H_ACTIVE + H_BORDER; // Total visible area (744 pixels)
parameter HSP = HFP + 14;            // Start horizontal sync (758)
parameter HBP = HSP + 56;            // End horizontal sync (814)
parameter HWL = HBP + 98 - 1;        // Total line width (count 911, 912 pixels)

// Vertical Timing (262 lines total - NTSC standard)
// Layout: |Top Border(19)|Active Display(200)|Bottom Border(21)|Blanking(22)| = 262 total
parameter V_BORDER = 40;   // Top/bottom border lines (total)
parameter V_ACTIVE = 200;  // Active display lines (Super Hi-Res)
parameter V_BLANKING = 22; // Blanking lines

parameter VFP = V_BORDER + V_ACTIVE;                  // 240 - End of active display
parameter VSP = VFP + 3;                              // 243 - Start vertical sync
parameter VBP = VSP + 4;                              // 246 - End vertical sync
parameter VWL = V_ACTIVE + V_BORDER + V_BLANKING - 1; // 261 - Total frame

assign hsync = ~((hcount >= HSP) && (hcount < HBP));
assign vsync = ~((vcount >= VSP) && (vcount < VBP));

assign hblank = hcount >= HFP;
assign vblank = vcount >= VFP;

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

