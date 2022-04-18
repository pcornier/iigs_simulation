

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
//Ch  CGA                   640x200@59.923     912    262      15.6998 + +      14.31818    112    64   96     25    3   34        [ref]
//t   "NTSC-59.94i"         768x483i@29.971    912    525      15.7346          14.35        40    56   48      2    6   34        MythTV modelines, DTV-PCTweakedModes
parameter HFP = 640;    // front porch
parameter HSP = HFP+64; // sync pulse
parameter HBP = HSP+96; // back porch
parameter HWL = HBP+112; // whole line
parameter VFP = 231;    // front porch
parameter VSP = VFP+3; // sync pulse
parameter VBP = VSP+3;  // back porch
parameter VWL = VBP+25; // whole line

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

