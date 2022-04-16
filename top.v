
module top(
  input reset,
  input clk_sys,
  input ce_pix,
  output [7:0] R,
  output [7:0] G,
  output [7:0] B,
  output HBlank,
  output VBlank,
  output HS,
  output VS
);

wire [7:0] bank;
wire [15:0] addr;
wire [7:0] dout;
wire we;

reg [2:0] clk_div;
always @(posedge clk_sys)
  clk_div <= clk_div + 3'd1;

wire fast_clk = clk_div == 0;


iigs core(

  .reset(reset),
  .clk_sys(clk_sys),
  .fast_clk(fast_clk),
  .slow_clk(),

  .bank(bank),
  .addr(addr),
  .dout(dout),
  .din(din),
  .we(we),
  .TEXTCOLOR(TEXTCOLOR)

);

parameter RAMSIZE = 16; // 16x64k = 1MB, max = 127x64k = 8MB

wire [7:0] TEXTCOLOR;

wire [7:0] rom1_dout, rom2_dout;
wire [7:0] fastram_dout;
wire [7:0] slowram_dout;
wire rom1_ce = bank == 8'hfe;
wire rom2_ce = (bank == 8'h0 && addr >= 16'hc100) || bank == 8'hff;
wire fastram_ce = bank < RAMSIZE; // bank[7] == 0;
wire slowram_ce = bank == 8'he0 || bank == 8'he1;

wire [7:0] din =
  rom1_ce ? rom1_dout :
  rom2_ce ? rom2_dout :
  fastram_ce ? fastram_dout :
  slowram_ce ? slowram_dout :
  8'hff;

rom #(.memfile("rom1.mem")) rom1(
  .clock(clk_sys),
  .address(addr),
  .q(rom1_dout),
  .ce(rom1_ce)
);

rom #(.memfile("rom2.mem")) rom2(
  .clock(clk_sys),
  .address(addr),
  .q(rom2_dout),
  .ce(rom2_ce)
);

// 8M 2.5MHz fast ram
/*
fastram fastram(
  .clk(clk_sys),
  .addr({ bank[6:0], addr }),
  .din(dout),
  .dout(fastram_dout),
  .wr(we),
  .ce(fastram_ce)
);
*/

dpram #(.widthad_a(23)) fastram
(
	.clock_a(clk_sys),
	.address_a({ bank[6:0], addr }),
	.data_a(dout),
	.q_a(fastram_dout),
	.wren_a(we),
	.ce_a(fastram_ce),

	.clock_b(clk_sys),
	.address_b(video_addr),
	.data_b(0),
	.q_b(video_data),
	.wren_b(1'b0)

	//.ce_b(1'b1)
);


// 128k 1MHz slow ram
// TODO: when 00-01 shadows on E0-E1, there's a copy mechanism 0x->Ex and it is
// supposed to slow down the CPU during memory accesses.
// Does CPU also slow down when it reads or writes on E0-E1?

slowram slowram(
  .clk(clk_sys),
  .addr({ bank[0], addr }),
  .din(dout),
  .dout(slowram_dout),
  .wr(we),
  .ce(slowram_ce)
);

wire [9:0] H;
wire [8:0] V;

jtframe_vtimer vtimer(
    .clk(clk_sys),
    .pxl_cen(ce_pix),
    .H(H),
    .vdump(V),
   .LHBL(hblank_n),
   .LVBL(vblank_n),
   .HS(HS),
   .VS(VS)
);

wire hblank_n;
wire vblank_n;

assign HBlank = ~hblank_n;
assign VBlank = ~vblank_n;

wire [22:0] video_addr;
wire [7:0] video_data;

vdc vdc(
        .clk(clk_sys),
        .ce_pix(ce_pix),
        .H(H),
        .V(V),
        .R(R),
        .G(G),
        .B(B),
        .video_addr(video_addr),
        .video_data(video_data),
	.TEXTCOLOR(TEXTCOLOR)
);


endmodule
