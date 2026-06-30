

module video_timing(

  input clk_vid,
  input ce_pix,

  output reg hsync,
  output reg vsync,
  output reg hblank,
  output reg vblank,

  output reg mega2_vbl, // Legacy vblank state at $C019

  output [10:0] hpos,
  output [9:0] vpos,
  output [6:0] hchar,   // Mega II horizontal counter for $C02F (TN.IIGS.039)

  // PH0-phase export for the FPI/clock_divider (see doc/core-timing-plan.md).
  // One Mega II char (14 pixels) == one PH0 period; hsub (0..13) IS the PH0
  // phase, and a strobe at the first pixel of each char IS the PH0 boundary.
  // These let the CPU clock slave its PH0/SYNC alignment to the real video
  // beam position (incl. the per-line NTSC stretch the char counter absorbs),
  // exactly as the real FPI "recreates PH0 from VGC STRETCH".
  output [3:0] ph0_phase, // = hsub (0..13): sub-char pixel phase
  output       ph0_stb    // 1-ce_pix strobe at the first pixel of each new char

);

assign hpos = hcount;
assign vpos = vcount;
assign ph0_phase = hsub;
assign ph0_stb   = (hsub == 4'd0);

reg [10:0] hcount;
reg [9:0] vcount;

// --- Mega II horizontal counter (per TN.IIGS.039 / $C02F) ---
// The 7-bit horizontal counter reads the sequence $00, $40, $41, ... $7F (65
// one-microsecond positions per line); active video is $58..$7F (40 columns).
// We model it as a char index hidx (0..64) with a 0..13 pixel phase (hsub).
// Encoding: index 0 -> $00, index n(1..64) -> $3F+n. Anchor: the active display
// starts at char $58 (index 25) at pixel HACTIVE_PIX, so the index at pixel 0 is
// 25 - HACTIVE_PIX/14. The 2-pixel NTSC line stretch (912 = 65*14 + 2) is absorbed
// by the reset at the line boundary (the wrap char spans the line edge).
localparam [10:0] HACTIVE_PIX = 11'd84;   // pixel where active display begins
// Mega II horizontal counter anchor. The Mega II H counter reads $00 at the line
// boundary (horz=0) -- the same point where the vertical counter increments --
// then $40..$7F across the line, exactly as GSS/hardware (get_hcounter, horz=0 at
// the V-transition). Our V counter increments at the hcount wrap (hcount=HWL->0),
// so hidx must be 0 at hcount=0 for $C02F to match hardware: a beam-racing demo
// (textfunk) that reads $C02F right after the vsync spin then sees the same H_CHAR
// hardware does (char 9 / $48), not 19 chars off. NOTE: hidx feeds ONLY the
// $C02E/$C02F reads; the display uses vgc.v's separate chram_x, so this does not
// move the picture. (Was 19, which put active display at $58 but mis-anchored the
// counter vs the V-transition -> textfunk garble.)
localparam [6:0]  HIDX_AT_H0  = 7'd0;
reg [6:0] hidx;
reg [3:0] hsub;
assign hchar = (hidx == 7'd0) ? 7'h00 : (7'h3F + hidx);


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

  // Mega II horizontal counter: one char every 14 pixels; realign at the line
  // boundary so the 2-pixel stretch is absorbed there (not in the active area).
  if (hcount == HWL) begin
    hidx <= HIDX_AT_H0;
    hsub <= 4'd0;
  end else if (hsub == 4'd13) begin
    hsub <= 4'd0;
    hidx <= (hidx == 7'd64) ? 7'd0 : hidx + 7'd1;
  end else begin
    hsub <= hsub + 4'd1;
  end
`ifdef DEBUG_HCHAR
  if (vcount == 10'd300 && hsub == 4'd0)
    $display("HCHAR: H=%0d hchar=%02x", hcount, hchar);
`endif
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

