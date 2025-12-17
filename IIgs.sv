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

assign VGA_SL = 0;
assign VGA_F1 = 0;
assign VGA_SCALER = 0;
assign VGA_DISABLE = 0;

assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign AUDIO_S = 1;
assign AUDIO_R = 0;
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
	"IIgs;UART19200:9600:4800:2400:1200:300;",
	"-;",
	"S0,HDVPO ;",
	"S1,HDVPO ;",
	"S2,DSK;",
	"S3,DSK;",
	"-;",
	"OA,Force Self Test,OFF,ON;",
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
	.paddle_0(paddle_0)
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
wire cold_reset_trigger = status[1] | keyboard_cold_reset;
wire reset = RESET | ~locked | warm_reset_trigger | cold_reset_trigger | buttons[1];

// cold_reset is 1 for power-on (RESET/~locked) or explicit cold reset, 0 for warm reset
wire cold_reset = RESET | ~locked | cold_reset_trigger;

wire selftest_override = status[10];

wire phi2;
wire phi0;
wire clk_7M;

iigs iigs (
	.reset(reset),
	.cold_reset(cold_reset),
	.CLK_28M(clk_28),
	.CLK_14M(clk_sys),
	.clk_vid(clk_vid),
	.cpu_wait(cpu_wait_hdd/*|ch0_busy*/),
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
	/* hard drive (supports 2 units - ProDOS limit) */
	.HDD_SECTOR(hdd_sector),
	.HDD_READ(hdd_read),
	.HDD_WRITE(hdd_write),
	.HDD_UNIT(hdd_unit),
	.HDD_MOUNTED(hdd_mounted),
	.HDD_PROTECT(hdd_protect),
	.HDD_RAM_ADDR(sd_buff_addr),
	.HDD_RAM_DI(sd_buff_dout),
	.HDD_RAM_DO(hdd_ram_do),
	.HDD_RAM_WE(sd_buff_wr & hdd_ack),
	//-- track buffer interface for disk 1
	.TRACK1(TRACK1),
	.TRACK1_ADDR(TRACK1_RAM_ADDR),
	.TRACK1_DO(TRACK1_RAM_DO),
	.TRACK1_DI(TRACK1_RAM_DI),
	.TRACK1_WE(TRACK1_RAM_WE),
	.TRACK1_BUSY(TRACK1_RAM_BUSY),
	//-- track buffer interface for disk 2
	.TRACK2(TRACK2),
	.TRACK2_ADDR(TRACK2_RAM_ADDR),
	.TRACK2_DO(TRACK2_RAM_DO),
	.TRACK2_DI(TRACK2_RAM_DI),
	.TRACK2_WE(TRACK2_RAM_WE),
	.TRACK2_BUSY(TRACK2_RAM_BUSY),
	// Disk ready to IWM (pad to 4 bits)
	.DISK_READY({2'b00, DISK_READY}),
	.fastram_address(fastram_address),
	.fastram_datatoram(fastram_datatoram),
	.fastram_datafromram(fastram_datafromram),
	.fastram_we(fastram_we),
	.fastram_ce(fastram_ce),
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

wire [22:0] fastram_address;
wire [7:0] fastram_datatoram;
wire [7:0] fastram_datafromram;
wire fastram_we;
wire fastram_ce;
wire fast_clk;
wire fast_clk_delayed;
wire fast_clk_delayed_mem;

logic [7:0] ram_data;
/*
dpram #(.widthad_a(23),.prefix("fast")) fastram
(
        .clock_a(clk_sys),
        .address_a( fastram_address ),
        .data_a(fastram_datatoram),
        .q_a(ram_data),
        .wren_a(fastram_we & fastram_ce),
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
	.addr({2'b00, fastram_address}),
	.wtbt(0),
	.dout(fastram_datafromram),
	.din(fastram_datatoram),
	.rd(phi2 & ~fastram_we & fastram_ce),
	.we(phi2 & fastram_we & fastram_ce),
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
  	.ch0_addr({2'b00, fastram_address}),  // Pad to 25 bits
  	.ch0_rd(phi2 & ~fastram_we & fastram_ce),
  	.ch0_wr(phi2 & fastram_we & fastram_ce),
  	.ch0_din(fastram_datatoram),
  	.ch0_dout(fastram_datafromram),
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
  	.clk_64(clk_mem),
  	.clk_8(clk_sys),

  	// Channel 0: CPU fast RAM
  	.addr({2'b00, fastram_address}),  // Pad to 25 bits
  	.oe(phi2 & ~fastram_we & fastram_ce),
  	.we(phi2 & fastram_we & fastram_ce),
  	.din(fastram_datatoram),
  	.dout(fastram_datafromram),
	.ds(2'b11),


  );
  
 
/*

//wire ch0_busy = 1'b0;

bram #(.widthad_a(15)) slowram
(
        .clock_a(clk_sys),
        .address_a(fastram_address),
        .data_a(fastram_datatoram),
        .q_a(fastram_datafromramback),
        .wren_a(fastram_we & fastram_ce),
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
reg  cpu_wait_hdd = 0;

// HDD unit being served (latched when operation starts)
reg hdd_active_unit = 1'b0;

// Both HDD units share the same sector (routed to their block device indices)
assign sd_lba[0] = {16'b0, hdd_sector};  // Unit 0
assign sd_lba[1] = {16'b0, hdd_sector};  // Unit 1

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
	end
	if (img_mounted[1]) begin
		hdd_mounted[1] <= img_size != 0;
		hdd_protect[1] <= img_readonly;
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
	sd_rd[0] = sd_rd_hd & (hdd_active_unit == 1'b0);
	sd_rd[1] = sd_rd_hd & (hdd_active_unit == 1'b1);
	sd_wr[0] = sd_wr_hd & (hdd_active_unit == 1'b0);
	sd_wr[1] = sd_wr_hd & (hdd_active_unit == 1'b1);
end


    wire TRACK1_RAM_BUSY;
wire [12:0] TRACK1_RAM_ADDR;
wire [7:0] TRACK1_RAM_DI;
wire [7:0] TRACK1_RAM_DO;
wire TRACK1_RAM_WE;
wire [5:0] TRACK1;

wire TRACK2_RAM_BUSY;
wire [12:0] TRACK2_RAM_ADDR;
wire [7:0] TRACK2_RAM_DI;
wire [7:0] TRACK2_RAM_DO;
wire TRACK2_RAM_WE;
wire [5:0] TRACK2;




wire fd_disk_1;
wire fd_disk_2;

wire [1:0] DISK_READY;
reg [1:0] DISK_CHANGE;
reg [1:0]disk_mount;



always @(posedge clk_sys) begin
        if (img_mounted[2]) begin
                disk_mount[0] <= img_size != 0;
                DISK_CHANGE[0] <= ~DISK_CHANGE[0];
                //disk_protect <= img_readonly;
        end
end
always @(posedge clk_sys) begin
        if (img_mounted[3]) begin
                disk_mount[1] <= img_size != 0;
                DISK_CHANGE[1] <= ~DISK_CHANGE[1];
                //disk_protect <= img_readonly;
        end
end

floppy_track floppy_track_1
(
   .clk(clk_sys),
   .reset(reset),

   .ram_addr(TRACK1_RAM_ADDR),
   .ram_di(TRACK1_RAM_DI),
   .ram_do(TRACK1_RAM_DO),
   .ram_we(TRACK1_RAM_WE),


   .track (TRACK1),
   .busy  (TRACK1_RAM_BUSY),
   .change(DISK_CHANGE[0]),
   .mount (img_mounted[2]),
   .ready  (DISK_READY[0]),
   .active (fd_disk_1),

   .sd_buff_addr (sd_buff_addr),
   .sd_buff_dout (sd_buff_dout),
   .sd_buff_din  (sd_buff_din[2]),
   .sd_buff_wr   (sd_buff_wr),

   .sd_lba       (sd_lba[2] ),
   .sd_rd        (sd_rd[2]),
   .sd_wr       ( sd_wr[2]),
   .sd_ack       (sd_ack[2])
);


floppy_track floppy_track_2
(
   .clk(clk_sys),
   .reset(reset),

   .ram_addr(TRACK2_RAM_ADDR),
   .ram_di(TRACK2_RAM_DI),
   .ram_do(TRACK2_RAM_DO),
   .ram_we(TRACK2_RAM_WE),

   .track (TRACK2),
   .busy  (TRACK2_RAM_BUSY),
   .change(DISK_CHANGE[1]),
   .mount (disk_mount[1]),
   .ready  (DISK_READY[1]),
   .active (fd_disk_2),

   .sd_buff_addr (sd_buff_addr),
   .sd_buff_dout (sd_buff_dout),
   .sd_buff_din  (sd_buff_din[3]),
   .sd_buff_wr   (sd_buff_wr),

   .sd_lba       (sd_lba[3] ),
   .sd_rd        (sd_rd[3]),
   .sd_wr       ( sd_wr[3]),
   .sd_ack       (sd_ack[3])
);



endmodule
