`timescale 1ns / 1ps
/*============================================================================
===========================================================================*/

module emu
(
	`include "sys/emu_ports.vh"
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
// AUDIO_R now comes from iigs module (was hardcoded to 0)
assign AUDIO_MIX = 1;

assign LED_DISK = 0;
assign LED_POWER = 0;
assign LED_USER = 0;
assign BUTTONS = 0;

//////////////////////////////////////////////////////////////////

wire [1:0] ar = status[122:121];

assign VIDEO_ARX = (!ar) ? 12'd4 : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? 12'd3 : 12'd0;

`include "build_id.v" 
localparam CONF_STR = {
	"Apple-IIgs;UART19200:9600:4800:2400:1200:300;",
	"-;",
	"O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"-;",
	"S0,HDVPO 2MG;",
	"S1,HDVPO 2MG;",
	"S2,WOZPO 2MG,WOZ 3.5;",
	"S3,WOZDSKDO PO NIB2MG,WOZ 5.25;",
	"-;",
	"OA,Force Self Test,OFF,ON;",
	"OB,ROM Version,ROM1,ROM3;",
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
wire [127:0] status;

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
reg ioctl_wait = 0;

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

	// PS/2 keyboard LEDs (HPS-side passthrough). Bit ordering per MiSTer
	// convention: {scrl_lock, num_lock, caps_lock}. We only own Caps Lock
	// on the IIgs (there's no Num Lock or Scroll Lock on the ADB keyboard),
	// so led_use[0]=1 to take ownership of that LED and leave the others to
	// the HPS. The status bit is fed from the ADB's caps_lock_state output.
	.ps2_kbd_led_status({2'b00, capslock_led}),
	.ps2_kbd_led_use(3'b001),

	.joystick_0(joystick_0),
	.joystick_l_analog_0(joystick_l_analog_0),
	.joystick_l_analog_1(joystick_l_analog_1),
	.paddle_0(paddle_0),

	.ioctl_download(ioctl_download),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_index(ioctl_index),
	.ioctl_wait(ioctl_wait)

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

// Caps Lock LED passthrough from the ADB to HPS PS/2 keyboard LEDs
wire capslock_led;

// Combine all reset sources
// Include ~locked to hold reset until PLL is stable (critical for FPGA)
wire warm_reset_trigger = status[0] | keyboard_reset;
// ioctl_download: hold the machine in cold reset while ROM is uploading so
// CPU SDRAM traffic can't collide with the upload channel
wire cold_reset_trigger = status[1] | keyboard_cold_reset | rom_switch_reset | ioctl_download;
wire reset = RESET | ~locked | warm_reset_trigger | cold_reset_trigger | buttons[1];

// cold_reset is 1 for power-on (RESET/~locked) or explicit cold reset or ROM switch, 0 for warm reset
wire cold_reset = RESET | ~locked | cold_reset_trigger;

wire selftest_override = status[10];
wire rom_select = ~status[11];  // 1=ROM3, 0=ROM1

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
	.HDD_READ({sd_rd[1:0]}),
	.HDD_WRITE(sd_wr[1:0]),
	.HDD_MOUNTED(img_mounted[1:0]),
	.img_readonly(img_readonly),
	.img_size(img_size),
	.HDD_RAM_ADDR(sd_buff_addr),
	.HDD_RAM_DI(sd_buff_dout),
	.HDD_RAM_DO(hdd_ram_do),
	.HDD_RAM_WE(sd_buff_wr & (|sd_ack[1:0])),
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
	.WOZ_TRACK3_WP(WOZ_TRACK3_WP),
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
	.WOZ_TRACK1_WP(WOZ_TRACK1_WP),
	.WOZ_TRACK1_BIT_DATA_IN(WOZ_TRACK1_BIT_DATA_IN),
	.WOZ_TRACK1_BIT_WE(WOZ_TRACK1_BIT_WE),
	.WOZ_TRACK1_BIT_WR_ADDR(WOZ_TRACK1_BIT_WR_ADDR),
	// Disk ready to IWM (all 4 drives)
	.DISK_READY(DISK_READY),
	// Floppy motor status
	.floppy_motor_on(floppy_motor_on),
	.floppy35_motor_on(floppy35_motor_on),
	.floppy35_eject(floppy35_eject),
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
	.keyboard_cold_reset(keyboard_cold_reset),
	.capslock(capslock_led)
);

wire [23:0] addr_bus;
wire [1:0] rom_bankaddr;
wire [7:0] iigs_dout;
wire we;
wire fastram_ce;
wire rom_ce;

// ROM3 (256KB) loaded at FC0000 via boot.rom  (ioctl_index[15:6]==0)
// ROM1 (128KB) loaded at F80000 via boot1.rom (ioctl_index[15:6]==1)
wire rom3_loading = ioctl_download && (ioctl_index[15:6] == 10'd0);

// CPU byte address into the 16MB SDRAM map (fast RAM low, ROM at top)
wire [23:0] cpu_sdram_addr =
                    (rom_ce & ~we & ~rom_select)  ? {6'b111111, rom_bankaddr, addr_bus[15:0]} :
                    (rom_ce & ~we &  rom_select)  ? {7'b1111100, rom_bankaddr[0], addr_bus[15:0]} :
                    {1'b0, addr_bus[22:0]};

// SDRAM write channel (ch0, highest priority): commit the closing cycle's
// write at the phi2 edge, sampling address/data just before the bus moves
// on -- the same point in the cycle where the real 65816 bus latches write
// data at the PHI2 fall. This matters for the HDD DMA engine, whose
// combinational DMA_ADDR advances at the phi2 edge while its data pipeline
// (sector BRAM + registered readback) lags by a cycle: address and data
// only describe the same byte at the END of the window. Writes go on the
// higher-priority channel so the read of the following CPU cycle can never
// be served ahead of them (write-then-read-same-address hazard).
reg         wr_req = 0;
wire        wr_ack;
reg  [24:1] wr_addr;
reg         wr_wrl, wr_wrh;
reg  [15:0] wr_din;

// SDRAM read channel (ch1): launch one clk_sys cycle after the phi2 edge,
// once the new cycle's address has settled. The req/ack round trip through
// the 114MHz controller completes in 2-3 clk_sys cycles, so read data is
// registered here well before the next phi2 pulse samples it through the
// CPU's D_IN mux.
reg         rd_req = 0;
wire        rd_ack;
reg  [24:1] rd_addr;
reg         rd_bsel;
wire [15:0] rd_dout;
reg  [7:0]  sdram_dout;

reg phi2_d;
always @(posedge clk_sys) begin
	phi2_d <= phi2;

	if (phi2 & we & fastram_ce) begin
		wr_addr <= {2'b00, addr_bus[22:1]};
		wr_din  <= {iigs_dout, iigs_dout};
		wr_wrl  <= ~addr_bus[0];
		wr_wrh  <=  addr_bus[0];
		wr_req  <= ~wr_req;
	end

	if (phi2_d & ~we & (fastram_ce | rom_ce)) begin
		rd_addr <= {1'b0, cpu_sdram_addr[23:1]};
		rd_bsel <= cpu_sdram_addr[0];
		rd_req  <= ~rd_req;
	end

	// rd_dout transitions only while a read is in flight and is stable from
	// ack onward, at least a full clk_sys cycle before the CPU consumes it
	sdram_dout <= rd_bsel ? rd_dout[15:8] : rd_dout[7:0];
end

// SDRAM upload channel (ch2): HPS ROM upload, throttled via ioctl_wait
reg         up_req = 0;
wire        up_ack;
reg  [24:1] up_addr;
reg         up_wrl, up_wrh;
reg  [15:0] up_din;

wire [23:0] ioctl_sdram_addr = rom3_loading ? {6'b111111, ioctl_addr[17:0]}
                                            : {7'b1111100, ioctl_addr[16:0]};
always @(posedge clk_sys) begin
	if (ioctl_wr & ioctl_download) begin
		up_addr    <= {1'b0, ioctl_sdram_addr[23:1]};
		up_din     <= {ioctl_dout, ioctl_dout};
		up_wrl     <= ~ioctl_sdram_addr[0];
		up_wrh     <=  ioctl_sdram_addr[0];
		up_req     <= ~up_req;
		ioctl_wait <= 1;
	end
	else if (up_req == up_ack) ioctl_wait <= 0;
end
sdram sdram
(
	.SDRAM_DQ(SDRAM_DQ),
	.SDRAM_A(SDRAM_A),
	.SDRAM_DQML(SDRAM_DQML),
	.SDRAM_DQMH(SDRAM_DQMH),
	.SDRAM_BA(SDRAM_BA),
	.SDRAM_nCS(SDRAM_nCS),
	.SDRAM_nWE(SDRAM_nWE),
	.SDRAM_nRAS(SDRAM_nRAS),
	.SDRAM_nCAS(SDRAM_nCAS),
	.SDRAM_CLK(SDRAM_CLK),
	.SDRAM_CKE(SDRAM_CKE),

	.init(~locked),
	.clk(clk_mem),

	.addr0(wr_addr), .wrl0(wr_wrl), .wrh0(wr_wrh), .din0(wr_din), .dout0(), .req0(wr_req), .ack0(wr_ack),
	.addr1(rd_addr), .wrl1(1'b0), .wrh1(1'b0), .din1(16'd0), .dout1(rd_dout), .req1(rd_req), .ack1(rd_ack),
	.addr2(up_addr), .wrl2(up_wrl), .wrh2(up_wrh), .din2(up_din), .dout2(), .req2(up_req), .ack2(up_ack)
);
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

// Both HDD units share the same sector (routed to their block device indices)
assign sd_lba[0] = {16'b0, hdd_sector};  // Unit 0
assign sd_lba[1] = {16'b0, hdd_sector};  // Unit 1
assign sd_lba[2] = woz_sd_lba;
assign sd_lba[3] = woz_sd_525_lba;

// HDD RAM output - shared buffer routed to both HDD unit indices
wire [7:0] hdd_ram_do;
assign sd_buff_din[0] = hdd_ram_do;  // Unit 0
assign sd_buff_din[1] = hdd_ram_do;  // Unit 1

// Route sd_rd/sd_wr to the correct index based on active unit
always @(*) begin
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
wire        WOZ_TRACK3_WP;
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
wire        WOZ_TRACK1_WP;
wire [7:0]  WOZ_TRACK1_BIT_DATA_IN;  // Write byte from IWM to BRAM
wire        WOZ_TRACK1_BIT_WE;       // Write enable from IWM
wire [15:0] WOZ_TRACK1_BIT_WR_ADDR;  // Write address (latched)

// Floppy motor state (for dirty track flush on motor-off)
wire        floppy_motor_on;
wire        floppy35_motor_on;
wire        floppy35_eject;       // 3.5" drive 1 GS/OS eject pulse (from iigs)
reg         ejected35 = 1'b0;     // latched: 3.5" disk ejected via OS, cleared on re-mount

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
	// 3.5" eject latch (mirrors MacLC clearing its inserted flag): a GS/OS eject
	// drops DISK_READY[2] so the drive reports "no disk" and the Finder removes
	// the icon. Re-mounting the image from the OSD clears the latch and re-inserts.
	if (floppy35_eject) ejected35 <= 1'b1;
	if (~img_mounted2_d & img_mounted[2]) begin
		ejected35 <= 1'b0;
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
assign DISK_READY[2] = woz_ctrl_disk_mounted && !ejected35;  // eject latch drops presence
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
	.disk_type_mismatch(),

	// Write-protect flag from WOZ INFO chunk
	.disk_write_protected(WOZ_TRACK3_WP)
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
	.disk_type_mismatch(),

	// Write-protect flag from WOZ INFO chunk
	.disk_write_protected(WOZ_TRACK1_WP)
);

endmodule
