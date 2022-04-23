
module top(
  input reset,
  input clk_sys,
  input clk_vid,
  input ce_pix,
  output [7:0] R,
  output [7:0] G,
  output [7:0] B,
  output HBlank,
  output VBlank,
  output HS,
  output VS,

    // HDD control
    output [15:0] HDD_SECTOR,
    output        HDD_READ,
    output        HDD_WRITE,
    input         HDD_MOUNTED,
    input         HDD_PROTECT,
    input [8:0]   HDD_RAM_ADDR,
    input [7:0]   HDD_RAM_DI,
    output [7:0]  HDD_RAM_DO,
    input         HDD_RAM_WE

);

wire [7:0] bank;
wire [15:0] addr;
wire [7:0] dout;
wire we;
reg [2:0] clk_div;
always @(posedge clk_sys)
  clk_div <= clk_div + 3'd1;

wire fast_clk = clk_div == 0;
wire fast_clk_delayed = clk_div ==1;

iigs core(

  .reset(reset),
  .clk_sys(clk_sys),
  .fast_clk(fast_clk_delayed),
  .fast_clk_delayed(fast_clk),
  .slow_clk(),

  .bank(bank),
  .addr(addr),
  .dout(dout),
  .din(din),
  .we(we),
  .VBlank(VBlank),
  .TEXTCOLOR(TEXTCOLOR),
  .BORDERCOLOR(BORDERCOLOR),
  .SLTROMSEL(SLTROMSEL),
  .H(H),
  .V(V)

);

`ifdef VERILATOR
//parameter RAMSIZE = 127; // 16x64k = 1MB, max = 127x64k = 8MB
parameter RAMSIZE = 20; // 16x64k = 1MB, max = 127x64k = 8MB
`else
parameter RAMSIZE = 2; // 16x64k = 1MB, max = 127x64k = 8MB
`endif

wire [7:0] TEXTCOLOR;
wire [3:0] BORDERCOLOR;
wire [7:0] SLTROMSEL;

wire [7:0] rom1_dout, rom2_dout;
wire [7:0] fastram_dout;
wire [7:0] slowram_dout;
wire rom1_ce = bank == 8'hfe;
wire rom2_ce = (bank == 8'h0 && addr >= 16'hc100) || bank == 8'hff;
wire fastram_ce = bank < RAMSIZE; // bank[7] == 0;
wire slowram_ce = bank == 8'he0 || bank == 8'he1;
//wire slot_ce =  bank == 8'h0 && addr >= 'hc400 && addr < 'hc800 && ~is_internal;
wire slot_ce =  (bank == 8'h0 || bank == 8'h1 || bank == 8'he0 || bank == 8'he1) && addr >= 'hc400 && addr < 'hc800 && ~is_internal;
wire is_internal =   ~SLTROMSEL[addr[10:8]];
//wire slot_internalrom_ce =  bank == 8'h0 && addr >= 'hc400 && addr < 'hc800 && is_internal;
wire slot_internalrom_ce =  (bank == 8'h0 || bank == 8'h1 || bank == 8'he0 || bank == 8'he1) && addr >= 'hc400 && addr < 'hc800 && is_internal;

// try to setup flags for traditional iie style slots
reg [7:0] device_select;
reg [7:0] io_select;


always @(posedge clk_sys)
begin
   device_select<=8'h0;   
   io_select<=8'h0;   
   if ((bank == 8'h0 || bank == 8'h1 || bank == 8'he0 || bank == 8'he1) && addr >= 'hc090 && addr < 'hc100 && ~is_internal)
   begin
	   $display("device_select addr[10:8] %x %x ",addr[10:8],din);
	  device_select[addr[6:4]]<=1'b1;
  end
   if ((bank == 8'h0 || bank == 8'h1 || bank == 8'he0 || bank == 8'he1) && addr >= 'hc400 && addr < 'hc800 && ~is_internal)
   begin
	   $display("io_select addr[10:8] %x din %x",addr[10:8],din);
	  io_select[addr[10:8]]<=1'b1;
  end
end




always @(posedge clk_sys)
begin
        if (fast_clk)
        begin
                $display("bank %x addr %x rom1_ce %x rom2_ce %x fastram_ce %x slot_internalrom_ce %x slowram_ce %x slot_ce %x rom2_dout %x din %x SLOTROMSEL %x",
			bank,addr,rom1_ce,rom2_ce,fastram_ce,slot_internalrom_ce,slowram_ce,slot_ce,rom2_dout,din,SLTROMSEL);
        end
end



wire [7:0] din =
  (io_select[7] == 1'b1 | device_select[7] == 1'b1) ? HDD_DO :
  rom1_ce ? rom1_dout :
  rom2_ce ? rom2_dout :
  fastram_ce ? fastram_dout :
  slot_internalrom_ce ?  rom2_dout :
  slowram_ce ? slowram_dout :
  slot_ce ? slot_dout :
  8'h80;

wire [7:0] slot_dout = HDD_DO;
wire [7:0] HDD_DO;

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
  .ce(rom2_ce|slot_internalrom_ce)
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

`ifdef VERILATOR
dpram #(.widthad_a(23)) fastram
`else
dpram #(.widthad_a(16)) fastram
`endif
(
	.clock_a(clk_sys),
	.address_a({ bank[6:0], addr }),
	.data_a(dout),
	.q_a(fastram_dout),
	.wren_a(we),
	.ce_a(fastram_ce),

	.clock_b(clk_vid),
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

video_timing video_timing(
.clk_vid(clk_vid),
.ce_pix(ce_pix),
.hsync(HS),
.vsync(VS),
.hblank(HBlank),
.vblank(VBlank),
.hpos(H),
.vpos(V)
);




wire [22:0] video_addr;
wire [7:0] video_data;

vdc vdc(
        .clk(clk_sys),
        .clk_vid(clk_vid),
        .ce_pix(ce_pix),
        .H(H),
        .V(V),
        .R(R),
        .G(G),
        .B(B),
        .video_addr(video_addr),
        .video_data(video_data),
	.TEXTCOLOR(TEXTCOLOR),
	.BORDERCOLOR(BORDERCOLOR)
);


    hdd hdd(
        .CLK_14M(clk_sys),
        .PHASE_ZERO(fast_clk),
        .IO_SELECT(io_select[7]),
        .DEVICE_SELECT(device_select[7]),
        .RESET(reset),
        .A(addr),
        .RD(we),
        .D_IN(dout),
        .D_OUT(HDD_DO),
        .sector(HDD_SECTOR),
        .hdd_read(HDD_READ),
        .hdd_write(HDD_WRITE),
        .hdd_mounted(HDD_MOUNTED),
        .hdd_protect(HDD_PROTECT),
        .ram_addr(HDD_RAM_ADDR),
        .ram_di(HDD_RAM_DI),
        .ram_do(HDD_RAM_DO),
        .ram_we(HDD_RAM_WE)
    );

endmodule
