`timescale 1ns / 1ps
/*============================================================================
===========================================================================*/

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [48:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	//if VIDEO_ARX[12] or VIDEO_ARY[12] is set then [11:0] contains scaled size instead of aspect ratio.
	output [12:0] VIDEO_ARX,
	output [12:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output [1:0]  VGA_SL,
	output        VGA_SCALER, // Force VGA scaler
	output        VGA_DISABLE, // analog out is off

	input  [11:0] HDMI_WIDTH,
	input  [11:0] HDMI_HEIGHT,
	output        HDMI_FREEZE,
	output        HDMI_BLACKOUT,
	output        HDMI_BOB_DEINT,

`ifdef MISTER_FB
	// Use framebuffer in DDRAM
	// FB_FORMAT:
	//    [2:0] : 011=8bpp(palette) 100=16bpp 101=24bpp 110=32bpp
	//    [3]   : 0=16bits 565 1=16bits 1555
	//    [4]   : 0=RGB  1=BGR (for 16/24/32 modes)
	//
	// FB_STRIDE either 0 (rounded to 256 bytes) or multiple of pixel size (in bytes)
	output        FB_EN,
	output  [4:0] FB_FORMAT,
	output [11:0] FB_WIDTH,
	output [11:0] FB_HEIGHT,
	output [31:0] FB_BASE,
	output [13:0] FB_STRIDE,
	input         FB_VBL,
	input         FB_LL,
	output        FB_FORCE_BLANK,

`ifdef MISTER_FB_PALETTE
	// Palette control for 8bit modes.
	// Ignored for other video modes.
	output        FB_PAL_CLK,
	output  [7:0] FB_PAL_ADDR,
	output [23:0] FB_PAL_DOUT,
	input  [23:0] FB_PAL_DIN,
	output        FB_PAL_WR,
`endif
`endif

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	// I/O board button press simulation (active high)
	// b[1]: user button
	// b[0]: osd button
	output  [1:0] BUTTONS,

	input         CLK_AUDIO, // 24.576 MHz
	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)

	//ADC
	inout   [3:0] ADC_BUS,

	//SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

`ifdef MISTER_DUAL_SDRAM
	//Secondary SDRAM
	//Set all output SDRAM_* signals to Z ASAP if SDRAM2_EN is 0
	input         SDRAM2_EN,
	output        SDRAM2_CLK,
	output [12:0] SDRAM2_A,
	output  [1:0] SDRAM2_BA,
	inout  [15:0] SDRAM2_DQ,
	output        SDRAM2_nCS,
	output        SDRAM2_nCAS,
	output        SDRAM2_nRAS,
	output        SDRAM2_nWE,
`endif

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT,

	input         OSD_STATUS
);

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
//assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign UART_DTR = UART_DSR;

assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;  
assign SDRAM_CKE = 1;

assign VGA_SL = 0;
assign VGA_F1 = 0;
assign VGA_SCALER = 0;
assign VGA_DISABLE = 0;

assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign AUDIO_S = 1;
// AUDIO_R now comes from iigs module (was hardcoded to 0)
assign AUDIO_MIX = 3;

assign LED_DISK = 0;
assign LED_POWER = 0;
assign LED_USER = 0;
assign BUTTONS = 0;

//////////////////////////////////////////////////////////////////

wire [1:0] ar = status[9:8];

assign VIDEO_ARX = (!ar) ? 12'd4 : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? 12'd3 : 12'd0;

`include "build_id.v" 
localparam CONF_STR = {
	"Apple-IIgs;UART19200:9600:4800:2400:1200:300;",
	"-;",
	"S0,HDVPO ;",
	"S1,HDVPO ;",
	"S2,WOZ,WOZ 3.5;",
	"S3,WOZ,WOZ 5.25;",
	"-;",
	"OA,Force Self Test,OFF,ON;",
	"OB,ROM Version,ROM3,ROM1;",
	"-;",

	"R0,Warm Reset;",
	"R1,Cold Reset;",
	"JA,Fire 1,Fire 2,Fire 3;",
	"jn,A|P,B,Y;",
	"jp,Y|P,B,Y;",
	"V,v",`BUILD_DATE
};

wire forced_scandoubler;
wire  [1:0] buttons;
wire [31:0] status;

wire [31:0] sd_lba[4];
reg   [3:0] sd_rd;
reg   [3:0] sd_wr;
wire  [3:0] sd_ack;
wire  [8:0] sd_buff_addr;
wire  [7:0] sd_buff_dout;
wire  [7:0] sd_buff_din[4];
wire        sd_buff_wr;
wire  [3:0] img_mounted;
wire        img_readonly;
wire [63:0] img_size;    


wire [32:0] TIMESTAMP;
wire [15:0] joystick_0;
//wire [15:0] joystick_a0;
wire [15:0] joystick_l_analog_0;
wire [15:0] joystick_l_analog_1;
wire  [7:0] paddle_0;

wire [10:0] ps2_key;
wire [24:0] ps2_mouse;

wire ioctl_download;
wire ioctl_wr;
wire [26:0] ioctl_addr;
wire [7:0] ioctl_dout;
wire [15:0] ioctl_index;

hps_io #(.CONF_STR(CONF_STR),.VDNUM(4)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(),

	.forced_scandoubler(forced_scandoubler),

	.sd_lba(sd_lba),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr),
	.img_mounted(img_mounted),
	.img_readonly(img_readonly),
	.img_size(img_size),
	
	.TIMESTAMP(TIMESTAMP),
	
	.buttons(buttons),
	.status(status),
	.status_menumask({status[5]}),
	
	.ps2_key(ps2_key),
	.ps2_mouse(ps2_mouse),
	.joystick_0(joystick_0),
	.joystick_l_analog_0(joystick_l_analog_0),
	.joystick_l_analog_1(joystick_l_analog_1),
	.paddle_0(paddle_0),

	.ioctl_download(ioctl_download),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_index(ioctl_index)

);

///////////////////////   CLOCKS   ///////////////////////////////

wire clk_mem,clk_sys,clk_vid,locked,clk_28;
wire clk_57;
wire clk_114;
wire clk_71;

assign clk_mem=clk_114;
assign clk_vid = clk_28;
pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_114),//114.545456
	.outclk_1(clk_71),//70
	.outclk_2(clk_57),//57.272728
	.outclk_3(clk_28),//28.636364
	.outclk_4(clk_sys),//14.318181
	.locked(locked)
);

// Reset logic - status[0] = Warm Reset, status[1] = Cold Reset
// Keyboard reset signals come from iigs module (Ctrl+F11, Ctrl+OpenApple+F11)
wire keyboard_reset;
wire keyboard_cold_reset;

// Combine all reset sources
// Include ~locked to hold reset until PLL is stable (critical for FPGA)
wire warm_reset_trigger = status[0] | keyboard_reset;
wire cold_reset_trigger = status[1] | keyboard_cold_reset | rom_switch_reset;
wire reset = RESET | ~locked | warm_reset_trigger | cold_reset_trigger | buttons[1];

// cold_reset is 1 for power-on (RESET/~locked) or explicit cold reset or ROM switch, 0 for warm reset
wire cold_reset = RESET | ~locked | cold_reset_trigger;

wire selftest_override = status[10];
wire rom_select = status[11];  // 0=ROM3, 1=ROM1

// Detect ROM version change and trigger cold reset
reg rom_select_prev;
always @(posedge clk_sys) rom_select_prev <= rom_select;
wire rom_switch_reset = (rom_select != rom_select_prev);

wire phi2;
wire phi0;
wire clk_7M;

iigs iigs (
	.reset(reset),
	.cold_reset(cold_reset),
	.CLK_28M(clk_28),
	.CLK_14M(clk_sys),
	.clk_vid(clk_vid),
	.ce_pix(ce_pix),
	.phi2(phi2),
	.phi0(phi0),
	.clk_7M(clk_7M),
	.timestamp(TIMESTAMP),
	.floppy_wp(1'b1),
	.R(VGA_R),
	.G(VGA_G),
	.B(VGA_B),
	.HBlank(hblank),
	.VBlank(vblank),
	.HS(hsync),
	.VS(vsync),
	.AUDIO_L(AUDIO_L),
	.AUDIO_R(AUDIO_R),
	/* hard drive (supports 2 units - ProDOS limit) */
	.HDD_SECTOR(hdd_sector),
	.HDD_READ(hdd_read),
	.HDD_WRITE(hdd_write),
	.HDD_UNIT(hdd_unit),
	.HDD_MOUNTED(hdd_mounted),
	.HDD_PROTECT(hdd_protect),
	.HDD0_SIZE(hdd0_size),
	.HDD1_SIZE(hdd1_size),
	.HDD_RAM_ADDR(sd_buff_addr),
	.HDD_RAM_DI(sd_buff_dout),
	.HDD_RAM_DO(hdd_ram_do),
	.HDD_RAM_WE(sd_buff_wr & hdd_ack),
	.HDD_ACK(sd_ack[1:0]),
	//-- WOZ bit interfaces for flux-based IWM
	// 3.5" drive 1
	.WOZ_TRACK3(WOZ_TRACK3),
	.WOZ_TRACK3_BIT_ADDR(WOZ_TRACK3_BIT_ADDR),
	.WOZ_TRACK3_STABLE_SIDE(WOZ_TRACK3_STABLE_SIDE),
	.WOZ_TRACK3_BIT_DATA(WOZ_TRACK3_BIT_DATA),
	.WOZ_TRACK3_BIT_COUNT(WOZ_TRACK3_BIT_COUNT),
	.WOZ_TRACK3_LOAD_COMPLETE(WOZ_TRACK3_LOAD_COMPLETE),
	.WOZ_TRACK3_IS_FLUX(WOZ_TRACK3_IS_FLUX),
	.WOZ_TRACK3_FLUX_SIZE(WOZ_TRACK3_FLUX_SIZE),
	.WOZ_TRACK3_FLUX_TOTAL_TICKS(WOZ_TRACK3_FLUX_TOTAL_TICKS),
	.WOZ_TRACK3_READY(WOZ_TRACK3_READY),
	.WOZ_TRACK3_DATA_VALID(WOZ_TRACK3_DATA_VALID),
	.WOZ_TRACK3_BIT_DATA_IN(WOZ_TRACK3_BIT_DATA_IN),
	.WOZ_TRACK3_BIT_WE(WOZ_TRACK3_BIT_WE),
	.WOZ_TRACK3_BIT_WR_ADDR(WOZ_TRACK3_BIT_WR_ADDR),
	// 5.25" drive 1
	.WOZ_TRACK1(WOZ_TRACK1),
	.WOZ_TRACK1_BIT_ADDR(WOZ_TRACK1_BIT_ADDR),
	.WOZ_TRACK1_BIT_DATA(WOZ_TRACK1_BIT_DATA),
	.WOZ_TRACK1_BIT_COUNT(WOZ_TRACK1_BIT_COUNT),
	.WOZ_TRACK1_LOAD_COMPLETE(WOZ_TRACK1_LOAD_COMPLETE),
	.WOZ_TRACK1_IS_FLUX(WOZ_TRACK1_IS_FLUX),
	.WOZ_TRACK1_FLUX_SIZE(WOZ_TRACK1_FLUX_SIZE),
	.WOZ_TRACK1_FLUX_TOTAL_TICKS(WOZ_TRACK1_FLUX_TOTAL_TICKS),
	.WOZ_TRACK1_BIT_DATA_IN(WOZ_TRACK1_BIT_DATA_IN),
	.WOZ_TRACK1_BIT_WE(WOZ_TRACK1_BIT_WE),
	.WOZ_TRACK1_BIT_WR_ADDR(WOZ_TRACK1_BIT_WR_ADDR),
	// Disk ready to IWM (all 4 drives)
	.DISK_READY(DISK_READY),
	// Floppy motor status
	.floppy_motor_on(floppy_motor_on),
	.floppy35_motor_on(floppy35_motor_on),
	.top_addr(addr_bus),
	.rom_bankaddr(rom_bankaddr),
	.top_din(sdram_dout),
	.top_dout(iigs_dout),
	.we(we),
	.fastram_ce(fastram_ce),
	.rom_ce(rom_ce),
	.rom_select(rom_select),
	.ps2_key(ps2_key),
	.ps2_mouse(ps2_mouse),
	.selftest_override(selftest_override),

	.FLOPPY_WP(1'b1),

	// Joystick and paddle inputs
	.joystick_0(joystick_0),
	// .joystick_1(joystick_1),
	 .joystick_l_analog_0(joystick_l_analog_0),
	 .joystick_l_analog_1(joystick_l_analog_1),
	.paddle_0(paddle_0),
	// .paddle_1(paddle_1),
	// .paddle_2(paddle_2),
	// .paddle_3(paddle_3)

	.UART_TXD(UART_TXD),
	.UART_RXD(UART_RXD),
	.UART_RTS(UART_RTS),
	.UART_CTS(UART_CTS),

	// Keyboard-triggered reset outputs (Ctrl+F11, Ctrl+OpenApple+F11)
	.keyboard_reset(keyboard_reset),
	.keyboard_cold_reset(keyboard_cold_reset)
);

wire [23:0] addr_bus;
wire [23:0] sdram_addr;
wire [7:0] sdram_din;
wire [1:0] rom_bankaddr;
wire [7:0] iigs_dout;
wire [7:0] sdram_dout;
wire we;
wire fastram_ce;
wire rom_ce;
wire fast_clk;
wire fast_clk_delayed;
wire fast_clk_delayed_mem;

// ROM3 (256KB) loaded at FC0000 via boot.rom  (ioctl_index[15:6]==0)
// ROM1 (128KB) loaded at F80000 via boot1.rom (ioctl_index[15:6]==1)
wire rom3_loading = ioctl_download && (ioctl_index[15:6] == 10'd0);
wire rom1_loading = ioctl_download && (ioctl_index[15:6] != 10'd0);

assign sdram_addr = rom3_loading                  ? {6'b111111, ioctl_addr[17:0]} :
                    rom1_loading                  ? {7'b1111100, ioctl_addr[16:0]} :
                    (rom_ce & ~we & ~rom_select)  ? {6'b111111, rom_bankaddr, addr_bus[15:0]} :
                    (rom_ce & ~we &  rom_select)  ? {7'b1111100, rom_bankaddr[0], addr_bus[15:0]} :
                    {1'b0, addr_bus[22:0]};

assign sdram_din = ioctl_download ? ioctl_dout : iigs_dout;
logic [7:0] ram_data;
/*
dpram #(.widthad_a(23),.prefix("fast")) fastram
(
        .clock_a(clk_sys),
        .address_a( addr_bus ),
        .data_a(iigs_dout),
        .q_a(ram_data),
        .wren_a(we & fastram_ce),
        .ce_a(fastram_ce)
);
wire ch0_busy = 1'b0;
*/


wire ch0_busy;
wire fastram_datafromramback;
/*
sdram sdram
(
	.*,
	.init(~locked),
	.clk(clk_mem),
	.addr({2'b00, addr_bus}),
	.wtbt(0),
	.dout(iigs_dout),
	.din(iigs_dout),
	.rd(phi2 & ~we & fastram_ce),
	.we(phi2 & we & fastram_ce),
	.ready()
);
*/
/*
  sdram sdram
  (
  	.*,  // Connect all SDRAM_* signals automatically
  	.init(~locked),
  	.clk(clk_mem),

  	// Channel 0: CPU fast RAM
	.ch0_addr({2'b00, addr_bus}),  // Pad to 25 bits
	.ch0_rd(phi2 & ~we & fastram_ce),
	.ch0_wr(phi2 & we & fastram_ce),
	.ch0_din(iigs_dout),
	.ch0_dout(iigs_dout),
	.ch0_busy(ch0_busy),

  	// Channel 1: Video system (if needed)
  	.ch1_addr(25'h0),    // Unused for now
  	.ch1_rd(1'b0),
  	.ch1_wr(1'b0),
  	.ch1_din(8'h00),
  	.ch1_dout(),         // Unconnected
  	.ch1_busy(),         // Unconnected

  	// Channel 2: Future expansion
  	.ch2_addr(25'h0),    // Unused
  	.ch2_rd(1'b0),
  	.ch2_wr(1'b0),
  	.ch2_din(8'h00),
  	.ch2_dout(),         // Unconnected
  	.ch2_busy()          // Unconnected
  );
  */

 sdram sdram
  (
	.sd_clk         ( SDRAM_CLK                ),
	.sd_data        ( SDRAM_DQ                 ),
	.sd_addr        ( SDRAM_A                  ),
	.sd_dqm         ( {SDRAM_DQMH, SDRAM_DQML} ),
	.sd_cs          ( SDRAM_nCS                ),
	.sd_ba          ( SDRAM_BA                 ),
	.sd_we          ( SDRAM_nWE                ),
	.sd_ras         ( SDRAM_nRAS               ),
	.sd_cas         ( SDRAM_nCAS               ),

  	.init(~locked),
  	.clk_8x(clk_mem),
  	.clk(clk_sys),

  	// Channel 0: CPU fast RAM
	.addr(sdram_addr),
	.oe((phi2 & ~we & (fastram_ce | rom_ce))),
	.we(((phi2 & we & fastram_ce) | ioctl_wr)),
	.din(sdram_din),
	.dout(sdram_dout),
	.ds(2'b11)
  );

/*

//wire ch0_busy = 1'b0;

bram #(.widthad_a(15)) slowram
(
        .clock_a(clk_sys),
        .address_a(addr_bus),
        .data_a(iigs_dout),
        .q_a(fastram_datafromramback),
        .wren_a(we & fastram_ce),
`ifdef VERILATOR
        .ce_a(fastram_ce),
`else
		  .enable_a(fastram_ce)
`endif
);
*/
/*
reg ce_pix;
always @(posedge clk_vid) begin
	reg [1:0] div;
	
	div <= div + 1'd1;
	ce_pix <= !div;
end
*/
reg ce_pix;
always @(posedge clk_vid) begin	
	ce_pix <= ~ce_pix;
end

wire hsync,vsync;
wire hblank,vblank;
assign CE_PIXEL=ce_pix;

assign VGA_HS=hsync;
assign VGA_VS=vsync;

//assign VGA_HB=hblank;
//assign VGA_VB=vblank;
assign VGA_DE =  ~(vblank | hblank);
assign CLK_VIDEO=clk_vid;



// HARD DRIVE PARTS (supports 2 units - ProDOS limit)
wire [15:0] hdd_sector;
wire        hdd_unit;           // Which unit (0-1) is being accessed (from bit 7)

// Per-unit mounted and protect status for 2 HDD units
// Using img_mounted indices: [0]=unit0, [1]=unit1
reg  [1:0] hdd_mounted = 2'b0;
wire hdd_read;
wire hdd_write;
reg  [1:0] hdd_protect = 2'b0;
reg [63:0] hdd0_size;
reg [63:0] hdd1_size;
reg  cpu_wait_hdd = 0;

// HDD unit being served (latched when operation starts)
reg hdd_active_unit = 1'b0;

// Both HDD units share the same sector (routed to their block device indices)
assign sd_lba[0] = {16'b0, hdd_sector};  // Unit 0
assign sd_lba[1] = {16'b0, hdd_sector};  // Unit 1
assign sd_lba[2] = woz_sd_lba;
assign sd_lba[3] = woz_sd_525_lba;

// Route sd_rd/sd_wr to the correct bit based on active unit
reg  sd_rd_hd;
reg  sd_wr_hd;

// Select the ack for the active unit
wire hdd_ack = (hdd_active_unit == 1'b0) ? sd_ack[0] : sd_ack[1];

// HDD RAM output - shared buffer routed to both HDD unit indices
wire [7:0] hdd_ram_do;
assign sd_buff_din[0] = hdd_ram_do;  // Unit 0
assign sd_buff_din[1] = hdd_ram_do;  // Unit 1

always @(posedge clk_sys) begin
	reg old_ack;
	reg hdd_read_pending;
	reg hdd_write_pending;
	reg state;

	old_ack <= hdd_ack;  // Use the muxed ack for active unit
	hdd_read_pending <= hdd_read_pending | hdd_read;
	hdd_write_pending <= hdd_write_pending | hdd_write;

	// Latch hdd_unit when a new request arrives (before state machine picks it up)
	if ((hdd_read | hdd_write) & !state & !(hdd_read_pending | hdd_write_pending)) begin
		hdd_active_unit <= hdd_unit;
	end

	// Handle HDD unit mounts (2 units mapped to img_mounted indices 0, 1)
	if (img_mounted[0]) begin
		hdd_mounted[0] <= img_size != 0;
		hdd_protect[0] <= img_readonly;
		hdd0_size <= img_size;
	end
	if (img_mounted[1]) begin
		hdd_mounted[1] <= img_size != 0;
		hdd_protect[1] <= img_readonly;
		hdd1_size <= img_size;
	end

	if(reset) begin
		state <= 0;
		cpu_wait_hdd <= 0;
		hdd_read_pending <= 0;
		hdd_write_pending <= 0;
		sd_rd_hd <= 0;
		sd_wr_hd <= 0;
	end
	else if(!state) begin
		if (hdd_read_pending | hdd_write_pending) begin
			state <= 1;
			sd_rd_hd <= hdd_read_pending;
			sd_wr_hd <= hdd_write_pending;
			cpu_wait_hdd <= 1;
		end
	end
	else begin
		if (~old_ack & hdd_ack) begin
			sd_rd_hd <= 0;
			sd_wr_hd <= 0;
		end
		else if(old_ack & ~hdd_ack) begin
			state <= 0;
			cpu_wait_hdd <= 0;
			hdd_read_pending <= 0;
			hdd_write_pending <= 0;
		end
	end
end

// Route sd_rd/sd_wr to the correct index based on active unit
always @(*) begin
	sd_rd = 4'b0;
	sd_wr = 4'b0;
	sd_rd[0] = sd_rd_hd & (hdd_active_unit == 1'b0);
	sd_rd[1] = sd_rd_hd & (hdd_active_unit == 1'b1);
	sd_wr[0] = sd_wr_hd & (hdd_active_unit == 1'b0);
	sd_wr[1] = sd_wr_hd & (hdd_active_unit == 1'b1);
	sd_rd[2] = woz_sd_rd;
	sd_wr[2] = woz_sd_wr;
	sd_rd[3] = woz_sd_525_rd;
	sd_wr[3] = woz_sd_525_wr;
end



wire fd_disk_1;
wire fd_disk_2;

// WOZ bit interfaces for flux-based IWM
// 3.5" drive 1 WOZ bit interface
wire [7:0]  WOZ_TRACK3;
wire [15:0] WOZ_TRACK3_BIT_ADDR;  // 16-bit for FLUX tracks up to 64KB
wire        WOZ_TRACK3_STABLE_SIDE;
wire [7:0]  WOZ_TRACK3_BIT_DATA;
wire [31:0] WOZ_TRACK3_BIT_COUNT;
wire        WOZ_TRACK3_LOAD_COMPLETE;
wire        WOZ_TRACK3_IS_FLUX;
wire [31:0] WOZ_TRACK3_FLUX_SIZE;
wire [31:0] WOZ_TRACK3_FLUX_TOTAL_TICKS;
wire        WOZ_TRACK3_READY;
wire        WOZ_TRACK3_DATA_VALID;
wire [7:0]  WOZ_TRACK3_BIT_DATA_IN;  // Write byte from IWM to BRAM
wire        WOZ_TRACK3_BIT_WE;       // Write enable from IWM
wire [15:0] WOZ_TRACK3_BIT_WR_ADDR;  // Write address (latched)

// 5.25" drive 1 WOZ bit interface
wire [5:0]  WOZ_TRACK1;
wire [15:0] WOZ_TRACK1_BIT_ADDR;  // 16-bit for FLUX tracks
wire [7:0]  WOZ_TRACK1_BIT_DATA;
wire [31:0] WOZ_TRACK1_BIT_COUNT;
wire        WOZ_TRACK1_LOAD_COMPLETE;
wire        WOZ_TRACK1_IS_FLUX;
wire [31:0] WOZ_TRACK1_FLUX_SIZE;
wire [31:0] WOZ_TRACK1_FLUX_TOTAL_TICKS;
wire [7:0]  WOZ_TRACK1_BIT_DATA_IN;  // Write byte from IWM to BRAM
wire        WOZ_TRACK1_BIT_WE;       // Write enable from IWM
wire [15:0] WOZ_TRACK1_BIT_WR_ADDR;  // Write address (latched)

// Floppy motor state (for dirty track flush on motor-off)
wire        floppy_motor_on;
wire        floppy35_motor_on;

wire [3:0] DISK_READY;

// WOZ controller outputs
wire        woz_ctrl_ready;
wire        woz_ctrl_disk_mounted;
wire        woz_ctrl_busy;
wire [31:0] woz_ctrl_bit_count;
wire [7:0]  woz_ctrl_bit_data;
wire        woz_ctrl_track_load_complete;
wire [31:0] woz_ctrl_flux_total_ticks;
wire [31:0] woz_sd_lba;
wire        woz_sd_rd;
wire        woz_sd_wr;

// 5.25" WOZ controller outputs
wire        woz_ctrl_525_ready;
wire        woz_ctrl_525_disk_mounted;
wire        woz_ctrl_525_busy;
wire [31:0] woz_ctrl_525_bit_count;
wire [7:0]  woz_ctrl_525_bit_data;
wire        woz_ctrl_525_track_load_complete;
wire        woz_ctrl_525_is_flux;
wire [31:0] woz_ctrl_525_flux_size;
wire [31:0] woz_ctrl_525_flux_total_ticks;
wire [31:0] woz_sd_525_lba;
wire        woz_sd_525_rd;
wire        woz_sd_525_wr;

reg         img_mounted2_d = 0;
reg         woz_ctrl_mount = 0;
reg         woz_ctrl_remount_pending = 0;
reg         woz3_stable_side_reg;

reg         img_mounted3_d = 0;
reg         woz_ctrl_525_mount = 0;
reg         woz_ctrl_525_remount_pending = 0;

always @(posedge clk_sys) begin
	img_mounted2_d <= img_mounted[2];
	if (~img_mounted2_d & img_mounted[2]) begin
		if (woz_ctrl_mount) begin
			// Already mounted: force unmount first, then remount next cycle
			woz_ctrl_mount <= 0;
			woz_ctrl_remount_pending <= (img_size != 0);
		end else begin
			woz_ctrl_mount <= (img_size != 0);
		end
	end else if (woz_ctrl_remount_pending) begin
		// One cycle after unmount: complete the remount
		woz_ctrl_mount <= 1;
		woz_ctrl_remount_pending <= 0;
	end
	woz3_stable_side_reg <= WOZ_TRACK3_STABLE_SIDE;

	img_mounted3_d <= img_mounted[3];
	if (~img_mounted3_d & img_mounted[3]) begin
		if (woz_ctrl_525_mount) begin
			woz_ctrl_525_mount <= 0;
			woz_ctrl_525_remount_pending <= (img_size != 0);
		end else begin
			woz_ctrl_525_mount <= (img_size != 0);
		end
	end else if (woz_ctrl_525_remount_pending) begin
		woz_ctrl_525_mount <= 1;
		woz_ctrl_525_remount_pending <= 0;
	end
end

assign WOZ_TRACK3_BIT_DATA = woz_ctrl_bit_data;
assign WOZ_TRACK3_BIT_COUNT = woz_ctrl_bit_count;
assign WOZ_TRACK3_LOAD_COMPLETE = woz_ctrl_track_load_complete;
assign WOZ_TRACK3_FLUX_TOTAL_TICKS = woz_ctrl_flux_total_ticks;
assign WOZ_TRACK3_READY = woz_ctrl_ready;
assign WOZ_TRACK1_BIT_DATA = woz_ctrl_525_bit_data;
assign WOZ_TRACK1_BIT_COUNT = woz_ctrl_525_bit_count;
assign WOZ_TRACK1_LOAD_COMPLETE = woz_ctrl_525_track_load_complete;
assign WOZ_TRACK1_IS_FLUX = woz_ctrl_525_is_flux;
assign WOZ_TRACK1_FLUX_SIZE = woz_ctrl_525_flux_size;
assign WOZ_TRACK1_FLUX_TOTAL_TICKS = woz_ctrl_525_flux_total_ticks;

assign DISK_READY[0] = woz_ctrl_525_disk_mounted;
assign DISK_READY[1] = 1'b0;
assign DISK_READY[2] = woz_ctrl_disk_mounted;
assign DISK_READY[3] = 1'b0;

woz_floppy_controller #(
	.IS_35_INCH(1)
) woz_ctrl (
	.clk(clk_sys),
	.reset(reset),

	// SD Block Device Interface (index 2)
	.sd_lba(woz_sd_lba),
	.sd_rd(woz_sd_rd),
	.sd_wr(woz_sd_wr),
	.sd_ack(sd_ack[2]),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din[2]),
	.sd_buff_wr(sd_buff_wr),

	// Disk Status
	.img_mounted(woz_ctrl_mount),
	.img_readonly(img_readonly),
	.img_size(img_size),

	// Drive Interface
	.track_id(WOZ_TRACK3),
	.ready(woz_ctrl_ready),
	.disk_mounted(woz_ctrl_disk_mounted),
	.busy(woz_ctrl_busy),
	.active(floppy35_motor_on),  // 3.5" motor state (not 5.25" inertia)

	// Bitstream Interface
	.bit_count(woz_ctrl_bit_count),
	.bit_addr(WOZ_TRACK3_BIT_ADDR),
	.stable_side(woz3_stable_side_reg),
	.bit_data(woz_ctrl_bit_data),
	.bit_data_in(WOZ_TRACK3_BIT_DATA_IN),
	.bit_we(WOZ_TRACK3_BIT_WE),
	.bit_wr_addr(WOZ_TRACK3_BIT_WR_ADDR),

	// Track load notification
	.track_load_complete(woz_ctrl_track_load_complete),

	// FLUX track support (WOZ v3)
	.is_flux_track(WOZ_TRACK3_IS_FLUX),
	.flux_data_size(WOZ_TRACK3_FLUX_SIZE),
	.flux_total_ticks(woz_ctrl_flux_total_ticks),

	// Track data validity (independent of controller state)
	.track_data_valid(WOZ_TRACK3_DATA_VALID),

	// Disk type mismatch
	.disk_type_mismatch()
);

// =========================================================================
// 5.25" WOZ Floppy Controller (SD index 3)
// =========================================================================
woz_floppy_controller #(
	.IS_35_INCH(0)
) woz_ctrl_525 (
	.clk(clk_sys),
	.reset(reset),

	// SD Block Device Interface (index 3)
	.sd_lba(woz_sd_525_lba),
	.sd_rd(woz_sd_525_rd),
	.sd_wr(woz_sd_525_wr),
	.sd_ack(sd_ack[3]),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din[3]),
	.sd_buff_wr(sd_buff_wr),

	// Disk Status
	.img_mounted(woz_ctrl_525_mount),
	.img_readonly(img_readonly),
	.img_size(img_size),

	// Drive Interface
	.track_id({WOZ_TRACK1[5:0], 2'b00}),  // Full track * 4 = quarter-track TMAP index
	.ready(woz_ctrl_525_ready),
	.disk_mounted(woz_ctrl_525_disk_mounted),
	.busy(woz_ctrl_525_busy),
	.active(floppy_motor_on),

	// Bitstream Interface
	.bit_count(woz_ctrl_525_bit_count),
	.bit_addr(WOZ_TRACK1_BIT_ADDR),
	.stable_side(1'b0),                    // 5.25" is single-sided
	.bit_data(woz_ctrl_525_bit_data),
	.bit_data_in(WOZ_TRACK1_BIT_DATA_IN),
	.bit_we(WOZ_TRACK1_BIT_WE),
	.bit_wr_addr(WOZ_TRACK1_BIT_WR_ADDR),

	// Track load notification
	.track_load_complete(woz_ctrl_525_track_load_complete),

	// FLUX track support
	.is_flux_track(woz_ctrl_525_is_flux),
	.flux_data_size(woz_ctrl_525_flux_size),
	.flux_total_ticks(woz_ctrl_525_flux_total_ticks),

	// Track data validity
	.track_data_valid(),

	// Disk type mismatch
	.disk_type_mismatch()
);

endmodule
