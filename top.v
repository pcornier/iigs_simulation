module top(
  input reset,
  input CLK_14M,
  input clk_vid,
  input cpu_wait,
  input ce_pix,
  input [32:0] timestamp,

  output phi2,
  output phi0,
  output clk_7M,
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
  input         HDD_RAM_WE,

  // FLOPPY SIGNALS
    output [5:0]  TRACK1,
output [12:0] TRACK1_ADDR,
output [7:0]    TRACK1_DI,
input [7:0]     TRACK1_DO,
output  TRACK1_WE,
input   TRACK1_BUSY,
output [5:0]    TRACK2,
output [12:0]   TRACK2_ADDR,
output [7:0]    TRACK2_DI,
input [7:0]     TRACK2_DO,
output  TRACK2_WE,
input   TRACK2_BUSY,

  input [3:0] DISK_READY,

  // Floppy write-protect (sim global)
   input              floppy_wp,


  // fastram sdram
  output [22:0] fastram_address,
  output [7:0] fastram_datatoram,
  input  [7:0] fastram_datafromram,
  output       fastram_we,
  output       fastram_ce,

  input [10:0] ps2_key
  ,
  // Floppy write-protect (from sim)
  input        FLOPPY_WP

);




wire [7:0] bank;
wire [7:0] shadow;
wire [15:0] addr;
wire [7:0] dout;
wire we;
wire slowram_ce;
  wire rom1_ce;
  wire rom2_ce;
wire inhibit_cxxx;

// Clock enables from the new clock divider
wire clk_14M_en;
wire clk_7M_en; 
wire ph0_en;
wire ph2_en;
wire q3_en;
wire ph0_state;
wire ph2_state;


// Map clock enables to Apple IIgs standard names
assign phi2 = ph2_en;
assign phi0 = ph0_en;
assign clk_7M = clk_7M_en;

wire scanline_irq;

  iigs core
    (
     .reset(reset),
     .CLK_14M(CLK_14M),
     .clk_7M_en(clk_7M_en),
     .timestamp(timestamp),
     .cpu_wait(cpu_wait),
     .phi2(phi2),
     .phi0(phi0),
     .q3_en(q3_en),
     .slow_clk(),

     .bank(bank),
     .addr(addr),
     .shadow(shadow),
     .dout(dout),
     .we(we),
     .slowram_ce(slowram_ce),

     .fastram_address(fastram_address),
     .fastram_datatoram(fastram_datatoram),
     .fastram_datafromram(fastram_datafromram),
     .fastram_we(fastram_we),
     .fastram_ce(fastram_ce),


     .rom1_ce(rom1_ce),
     .rom2_ce(rom2_ce),
     .romc_ce(romc_ce),
     .romd_ce(romd_ce),
     .VBlank(VBlank),
     .TEXTCOLOR(TEXTCOLOR),
     .BORDERCOLOR(BORDERCOLOR),
     .HIRES_MODE(HIRES_MODE),
     .ALTCHARSET(ALTCHARSET),
     .EIGHTYCOL(EIGHTYCOL),
     .PAGE2(PAGE2),
     .TEXTG(TEXTG),
     .MIXG(MIXG),
     .NEWVIDEO(NEWVIDEO),
     .IO(IO),
     .CYAREG(CYAREG),
     .VPB(VPB),
     .SLTROMSEL(SLTROMSEL),
     .CXROM(CXROM),
     .RDROM(RDROM),
     .LC_WE(LC_WE),
     .LCRAM2(LCRAM2),

     .ps2_key(ps2_key),
     .floppy_wp(FLOPPY_WP),

     .inhibit_cxxx(inhibit_cxxx),

        /* hard drive */
        .HDD_SECTOR(HDD_SECTOR),
        .HDD_READ(HDD_READ),
        .HDD_WRITE(HDD_WRITE),
        .HDD_MOUNTED(HDD_MOUNTED),
        .HDD_PROTECT(HDD_PROTECT),
        .HDD_RAM_ADDR(HDD_RAM_ADDR),
        .HDD_RAM_DI(HDD_RAM_DI),
        .HDD_RAM_DO(HDD_RAM_DO),
        .HDD_RAM_WE(HDD_RAM_WE),

      // 5.25" drive track buses
     .TRACK1(TRACK1),
     .TRACK1_ADDR(TRACK1_ADDR),
     .TRACK1_DI(TRACK1_DI),
     .TRACK1_DO(TRACK1_DO),
     .TRACK1_WE(TRACK1_WE),
     .TRACK1_BUSY(TRACK1_BUSY),
     .TRACK2(TRACK2),
     .TRACK2_ADDR(TRACK2_ADDR),
     .TRACK2_DI(TRACK2_DI),
     .TRACK2_DO(TRACK2_DO),
     .TRACK2_WE(TRACK2_WE),
     .TRACK2_BUSY(TRACK2_BUSY)
     ,
     // Disk ready lines to IWM (D1..D4)
     .DISK_READY(DISK_READY)

     );


wire VPB;

wire CXROM;
wire LC_WE;
wire RDROM;
wire LCRAM2;
wire [7:0] CYAREG;
wire [7:0] TEXTCOLOR;
wire [3:0] BORDERCOLOR;
wire  HIRES_MODE;
wire ALTCHARSET;
wire EIGHTYCOL;
wire  PAGE2;
wire  TEXTG;
wire  MIXG;
wire [7:0] NEWVIDEO;
wire IO;
wire [7:0] SLTROMSEL;

wire [7:0] rom1_dout, rom2_dout, romc_dout, romd_dout;
wire [7:0] fastram_dout;
wire [7:0] slowram_dout;



//wire slot_ce =  bank == 8'h0 && addr >= 'hc400 && addr < 'hc800 && ~is_internal;
wire slot_ce =  (bank == 8'h0 || bank == 8'h1 || bank == 8'he0 || bank == 8'he1) && addr >= 'hc100 && addr < 'hc800 && ~is_internal && ~inhibit_cxxx;
wire is_internal =   ~SLTROMSEL[addr[10:8]];
wire is_internal_io =   ~SLTROMSEL[addr[6:4]];
//wire slot_internalrom_ce =  bank == 8'h0 && addr >= 'hc400 && addr < 'hc800 && is_internal;
wire slot_internalrom_ce =  (bank == 8'h0 || bank == 8'h1 || bank == 8'he0 || bank == 8'he1) && addr >= 'hc100 && addr < 'hc800 && is_internal && ~inhibit_cxxx;

// try to setup flags for traditional iie style slots
reg [7:0] device_select;
reg [7:0] io_select;



endmodule
