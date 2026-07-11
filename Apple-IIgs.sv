`timescale 1ns / 1ps
// Debug instrumentation for the 14.3 wedge hunt (pixel overlay + ddr_trace).
// NOTE: qsf VERILOG_MACRO does not reach SystemVerilog synthesis in this
// Quartus -- uncomment here to enable. DEPLOY TO /media/fat/Apple-IIgs.rbf
// (the SD ROOT): Main resolves MGL <rbf> from the root before _Computer/.
//`define DEBUG_PIXEL_OVERLAY 1
//`define DEBUG_DDR_TRACE 1
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
`ifdef DEBUG_DDR_TRACE
// DDRAM is driven by the ddr_trace debug recorder (instantiated near the
// memory bridge). wickerwaka's technique (github.com/wickerwaka/ddr_trace):
// on-change signal records stream to HPS DDR3 at 0x30000000; read via
// /dev/mem over SSH, decode offline with trace2vcd.py.
`else
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;
`endif

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
	"O[14:12],CPU Speed,2.8 MHz (Std),3.6 MHz,4.8 MHz,7.2 MHz,14.3 MHz;",
	"P1,Accelerator;",
	"P1-;",
	"P1O[16:15],Card,ZipGS,TransWarp GS,None (OSD speed only);",
	"H0P1O[17],Speaker Delay,Enabled,Disabled;",
	"H0P1O[18],Joystick Delay,Enabled,Disabled;",
	"H0P1O[20],Counter Delay,Enabled,Disabled;",
	"H0P1O[19],Sync to Sys 1MHz (CPS),Off,On;",
	"P2,System;",
	"P2-;",
	"P2O[11],ROM Version,ROM1,ROM3;",
	"P2O[10],Force Self Test,OFF,ON;",
	"P2-;",
	"P2SC4,RAM,PRAM NVRAM;",
	"P2R[21],Save NVRAM;",
	"P2R[22],Load NVRAM;",
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

wire [31:0] sd_lba[5];
reg   [3:0] sd_rd;         // slots 0-3 (disks); slot 4 = bk_sd_rd below
reg   [3:0] sd_wr;
wire  [4:0] sd_ack;
wire  [8:0] sd_buff_addr;
wire  [7:0] sd_buff_dout;
wire  [7:0] sd_buff_din[5];
wire        sd_buff_wr;
wire  [4:0] img_mounted;
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

hps_io #(.CONF_STR(CONF_STR),.VDNUM(5)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(),

	.forced_scandoubler(forced_scandoubler),

	.sd_lba(sd_lba),
	.sd_rd({bk_sd_rd, sd_rd}),
	.sd_wr({bk_sd_wr, sd_wr}),
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
	// bit0: 1 = TransWarp GS selected -> the delay/CPS toggles hide (a real
	// TWGS's slowdowns are automatic and always on; the RTL forces them).
	.status_menumask({15'd0, accel_card == 2'd1}),
	.status_in(status_mirror),
	.status_set(status_mirror_set),

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
wire warm_reset_trigger = status[0] | keyboard_reset | nv_load_reset;
// ioctl_download: hold the machine in cold reset while ROM is uploading so
// CPU SDRAM traffic can't collide with the upload channel
wire cold_reset_trigger = status[1] | keyboard_cold_reset | rom_switch_reset | ioctl_download;
wire reset = RESET | ~locked | warm_reset_trigger | cold_reset_trigger | buttons[1];

// cold_reset is 1 for power-on (RESET/~locked) or explicit cold reset or ROM switch, 0 for warm reset
wire cold_reset = RESET | ~locked | cold_reset_trigger;

wire selftest_override = status[10];
wire rom_select = ~status[11];  // iigs.sv: 0=ROM3, 1=ROM1 (status=0 default -> ROM1)

// OSD CPU speed (shares state with the ZipGS $C058-$C05F software interface):
// 0 = native 2.86 MHz, 1 = 3.58, 2 = 4.77, 3 = 7.16, 4 = 14.32.
// The burst+cache SDRAM path (formerly the ACCEL_SDRAM compile option) is
// always built in; it was hardware-validated at 7.16 MHz (2-FF mem_ack
// synchronizer fix). Default OSD speed is native 2.8 MHz.
wire cache_disable;   // ZipGS $C059 bit 7 -> sdram_cache bypass
// 14.32 MHz (step 4) re-enabled: the 1-tick races the old cap protected
// against are now closed (doc/zipgs-14mhz-plan.md) -- write back-pressure
// into mem_stall, cache write-forwarding, and the clock_divider fast-escape
// gate. Clamp anything above step 4 (3-bit status can encode 5-7).
wire [2:0] host_speed = (status[14:12] > 3'd4) ? 3'd4 : status[14:12];
wire accel_capable = 1'b1;
wire mem_stall;   // driven by the icache (cache miss in flight)
// OSD "Accelerator > Card": which accelerator the software can SEE. Mutually
// exclusive (a real machine holds one card); the OSD CPU Speed above works
// with any of them (it is the card's host/hardware speed, or a footprint-free
// host-only turbo when no card is present).
//   0 = ZipGS (default): $C058-$C05F register interface
//   1 = TransWarp GS:    bank $BC detection ROM + $BC0000 latch + NVRAM
//   2 = None:            OSD speed only, no software-visible accelerator
wire [1:0] accel_card = status[16:15];
wire zip_regs_en  = (accel_card == 2'd0);
wire twgs_present = (accel_card == 2'd1);

// Per-delay OSD toggles. These are VIEWS of the ZipGS delay registers (the
// single source of truth): the OSD value edge-applies into the register, and
// software writes mirror back into these status bits below -- flip either the
// OSD or the Zip Control Panel and both stay in sync. Defaults (all-zero
// status) match the zipgs_regs power-on values: delays enabled, CPS off.
// Hidden + forced-on with the TWGS card (its slowdowns are non-configurable).
wire osd_spkr_delay = ~status[17];  // 0 = Enabled
wire osd_pdl_delay  = ~status[18];  // 0 = Enabled
wire osd_ctr_delay  = ~status[20];  // 0 = Enabled
wire osd_cps_follow =  status[19];  // 0 = Off (deliberate divergence from a
                                    // real Zip's default-on; see iigs.sv)

// OSD status write-back ("the OSD is a live display"): when software (Zip CP
// via $C059/$C05C/$C05D, TWGS via $BC0000) changes the accelerator state, push
// the new values into the MiSTer status word so the menu shows reality. The
// edge-apply guards in zipgs_regs/twgs_regs absorb the resulting status
// change (it equals the card state by construction), so no feedback loop.
wire [2:0] accel_cfg_speed;
wire accel_spkr_delay, accel_pdl_delay, accel_ctr_delay, accel_cps_follow;
wire [127:0] status_mirror_view;
assign status_mirror_view = {status[127:21], ~accel_ctr_delay, accel_cps_follow,
                             ~accel_pdl_delay, ~accel_spkr_delay, status[16:15],
                             accel_cfg_speed, status[11:0]};
reg  [127:0] status_mirror;
reg          status_mirror_set;
reg  [8:0]   mirror_last;   // {ctr,cps,pdl,spkr,card(2),speed(3)} view bits
wire [8:0]   mirror_now = {~accel_ctr_delay, accel_cps_follow, ~accel_pdl_delay,
                           ~accel_spkr_delay, status[16:15], accel_cfg_speed};
wire [8:0]   mirror_osd = {status[20], status[19], status[18],
                           status[17], status[16:15], status[14:12]};
always @(posedge clk_sys) begin
	status_mirror_set <= 1'b0;
	if (reset) begin
		mirror_last <= mirror_osd;   // adopt the OSD state at reset: no push
	end else if (mirror_now != mirror_last) begin
		mirror_last <= mirror_now;
		if (mirror_now != mirror_osd) begin
			status_mirror     <= status_mirror_view;
			status_mirror_set <= 1'b1;   // rising edge = one status update
		end
	end
end

// Detect ROM version change and trigger cold reset
reg rom_select_prev;
always @(posedge clk_sys) rom_select_prev <= rom_select;
wire rom_switch_reset = (rom_select != rom_select_prev);

wire phi2;
wire phi0;
wire clk_7M;
wire drive35_eject_req;
wire [7:0] iigs_r, iigs_g, iigs_b;

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
	.R(iigs_r),
	.G(iigs_g),
	.B(iigs_b),
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
	.WOZ_TRACK1_QTRACK(WOZ_TRACK1_QTRACK),
	.WOZ_TRACK1_DATA_VALID(WOZ_TRACK1_DATA_VALID),
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
	.drive35_eject_req(drive35_eject_req),
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
	.host_speed(host_speed),
	.accel_capable(accel_capable),
	.accel_active(accel_active),
	.zip_regs_en(zip_regs_en),
	.twgs_present(twgs_present),
	.osd_spkr_delay(osd_spkr_delay),
	.osd_pdl_delay(osd_pdl_delay),
	.osd_ctr_delay(osd_ctr_delay),
	.osd_cps_follow(osd_cps_follow),
	.accel_cfg_speed(accel_cfg_speed),
	.accel_spkr_delay(accel_spkr_delay),
	.accel_pdl_delay(accel_pdl_delay),
	.accel_ctr_delay(accel_ctr_delay),
	.accel_cps_follow(accel_cps_follow),
	.nv_addr(nv_addr),
	.nv_wr(nv_wr),
	.nv_din(nv_din),
	.nv_dout(nv_dout),
	.mem_stall(mem_stall),

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
	.capslock(capslock_led),
	.cache_disable(cache_disable)
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

// Speed-selected CPU read path. Confirmed on hardware (textfunk / FTA demo
// bisect, 2026-07-04): the burst+cache miss path is slower than the old
// single-word read and its mem_stall stretches CPU cycles at NATIVE speed,
// breaking cycle-exact beam racing. So:
//   accel_r=0 (native 2.8): ch3 single-word reads, registered byte, NEVER
//     stalls -- identical semantics/latency class to the old rtl/sdram.sv
//     path (data registered ~phi2+3, before the native sample point).
//   accel_r=1 (any fast step): burst-8 (ch1) + line cache + stall-on-miss,
//     as hardware-validated at 7.16 MHz.
// accel_r follows the LIVE speed state from iigs.sv (OSD *and* the ZipGS
// software protocol), registered at phi2 so the path is stable per cycle.
wire        accel_active;
reg         accel_r = 0;

wire        rd_req;
wire        rd_ack;
wire [24:1] rd_addr;
wire [127:0] rd_line;
wire        cache_rd    = phi2_d & ~we & (fastram_ce | rom_ce) & use_cache_path;
wire [24:1] cache_addr  = {1'b0, cpu_sdram_addr[23:1]};
wire [15:0] cache_data;
wire        cache_hit_now;
wire [15:0] cache_data_now;
wire        cache_ready, cache_stall;
// Stall rule with the combinational hit path (accelerated only): hold the
// CPU whenever the current cycle reads fast RAM / ROM and the cache does not
// (yet) hit. A miss launches its fill from the cache_rd strobe, the fill
// lands, hit_now rises, the stall drops and the comb byte is already valid.
// Sampled synchronously by the CPU's RDY, so comb glitches are fine.
//
// Write back-pressure (the 14.3 MHz killer -- doc/zipgs-14mhz-plan.md, A):
// the write channel is fire-and-forget, but one controller write takes
// ~9 clk_mem (~78.6ns) while a 1-tick CPU can commit one write per 69.8ns.
// Without back-pressure a second wr_req toggle lands while the first write
// is in flight and the controller's "ack0 <= req0" silently absorbs it --
// the write never reaches SDRAM (the cache snoop masks it until the line is
// evicted: delayed corruption under load). So: hold the CPU on an
// accelerated fastram WRITE while the previously posted write is still
// unacknowledged. wr_ack toggles in clk_mem; 2-FF sync like mem_ack in
// sdram_cache (31bf1a lesson). Native (accel_r=0) is untouched: a write
// retires in ~1.2 ticks, far inside the 5-tick cycle.
reg         wr_ack_s1, wr_ack_s2;
wire        wr_pending = (wr_req != wr_ack_s2);
// Keyed on use_cache_path (== accel_r, extended 2 cycles past a datapath
// switch): during the switch guard, reads are served by the cache, so misses
// must stall exactly as when accelerated.
assign mem_stall = use_cache_path & ( (~we & (fastram_ce | rom_ce) & ~cache_hit_now)
                                    | ( we & fastram_ce & wr_pending) );
reg         snoop_stb;

// Native single-word read channel (ch3): launch one clk_sys cycle after the
// phi2 edge, once the new cycle's address has settled; data byte registered
// continuously from dout3 (no ack wait), exactly like the old sdram.v path.
reg         nat_req = 0;
wire        nat_ack;
reg  [24:1] nat_addr;
reg         nat_bsel;
wire [15:0] nat_dout;
reg  [7:0]  nat_data;

// Datapath-switch guard: for the first 2 committed cycles after accel_r
// changes, keep serving reads through the CACHE path (comb hit +
// stall-on-miss is correct at any cycle length) while the ch3 pipeline warms
// up. Without this, the first native-path reads right after a fast->native
// switch (IWM hold-off, HDD DMA) sample a cold/late nat_data: ch3 wasn't
// launching while accelerated, and its first ack can also queue behind an
// in-flight line fill -- stale operand bytes with no stall (caught by the
// SDRAM_SIM checker at the boot drive scan: BIT $C0ED fetched as BIT $2C8F,
// wedging the Sony handshake loop; the 14.3 "stuck at splash" freeze).
// Native-only operation (accelerator off) never transitions, so this is a
// structural no-op there and native cycle-exactness is untouched.
reg  [1:0]  accel_switch_guard = 0;
wire        use_cache_path = accel_r | (accel_switch_guard != 2'd0);

// CPU read byte: comb cache byte when accelerated (or just after a datapath
// switch), registered ch3 byte native
wire [7:0]  sdram_dout  = use_cache_path ? (cpu_sdram_addr[0] ? cache_data_now[15:8] : cache_data_now[7:0])
                                         : nat_data;

reg phi2_d;
always @(posedge clk_sys) begin
	phi2_d <= phi2;
	if (phi2) begin
		accel_r <= accel_active;
		if (accel_r != accel_active)          accel_switch_guard <= 2'd2;
		else if (accel_switch_guard != 2'd0)  accel_switch_guard <= accel_switch_guard - 2'd1;
	end
	wr_ack_s1 <= wr_ack;
	wr_ack_s2 <= wr_ack_s1;

	if (phi2_d & ~we & (fastram_ce | rom_ce) & ~accel_r) begin
		nat_addr <= {1'b0, cpu_sdram_addr[23:1]};
		nat_bsel <= cpu_sdram_addr[0];
		nat_req  <= ~nat_req;
	end
	nat_data <= nat_bsel ? nat_dout[15:8] : nat_dout[7:0];

	// Post gate mirrors the write-stall: while accelerated and a prior write
	// is pending, RDY is held low so this cycle has NOT committed -- do not
	// post (or snoop) it yet. When wr_pending clears, the next phi2 commits
	// the held cycle and posts it exactly once. At native (accel_r=0) the
	// condition is identical to the original unconditional post.
	if (phi2 & we & fastram_ce & ~(accel_r & wr_pending)) begin
		wr_addr <= {2'b00, addr_bus[22:1]};
		wr_din  <= {iigs_dout, iigs_dout};
		wr_wrl  <= ~addr_bus[0];
		wr_wrh  <=  addr_bus[0];
		wr_req  <= ~wr_req;
	end

	// snoop ch0 writes one cycle late, when wr_addr/wr_din hold the committed write
	snoop_stb <= phi2 & we & fastram_ce & ~(accel_r & wr_pending);
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
// ---- accelerator: burst-8 controller + line buffer (see doc/sdram_accel/) ----
sdram_burst sdram
(
	.SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A), .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH),
	.SDRAM_BA(SDRAM_BA), .SDRAM_nCS(SDRAM_nCS), .SDRAM_nWE(SDRAM_nWE),
	.SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCAS(SDRAM_nCAS), .SDRAM_CLK(SDRAM_CLK), .SDRAM_CKE(SDRAM_CKE),
	.init(~locked), .clk(clk_mem),
	.addr0(wr_addr), .wrl0(wr_wrl), .wrh0(wr_wrh), .din0(wr_din), .dout0(), .req0(wr_req), .ack0(wr_ack),
	.addr1(rd_addr), .wrl1(1'b0), .wrh1(1'b0), .din1(16'd0), .dout1(rd_line), .req1(rd_req), .ack1(rd_ack),
	.addr2(up_addr), .wrl2(up_wrl), .wrh2(up_wrh), .din2(up_din), .dout2(), .req2(up_req), .ack2(up_ack),
	.addr3(nat_addr), .dout3(nat_dout), .req3(nat_req), .ack3(nat_ack)
);

// Line buffer on the CPU read path. Runs in clk_sys; talks to ch1 via toggle req/ack (the
// controller is in clk_mem). At native 2.8 MHz a miss (one ~19-cycle clk_mem burst) completes
// well within a CPU cycle, so no CPU stall is needed; cache_stall is exposed for the future
// higher clock steps (drive it into the CPU RDY at that point -- see doc/sdram_accel/03).
sdram_cache #(.LINES(8), .LINE_WORDS(8), .ADDR_W(24)) icache
(
	.clk(clk_sys), .reset(reset), .cache_off(cache_disable),
	.cpu_addr(cache_addr), .cpu_rd(cache_rd), .cpu_data(cache_data),
	.cpu_ready(cache_ready), .cpu_stall(cache_stall),
	.hit_now(cache_hit_now), .cpu_data_now(cache_data_now),
	.wr_addr(wr_addr), .wr_data(wr_din), .wr_be({wr_wrh, wr_wrl}), .wr_stb(snoop_stb),
	.mem_addr(rd_addr), .mem_req(rd_req), .mem_ack(rd_ack), .mem_line(rd_line)
);

`ifdef DEBUG_DDR_TRACE
// ---- TEMPORARY: 14.3 MHz wedge hunt -- deep bus trace to HPS DDR3 ----
// Trigger arms at the FIRST IWM access ($C0E0-EF, bank 0) after reset, i.e.
// the start of the ROM's drive scan where the hardware wedges. From then on
// every change of the packed bus snapshot is recorded (2M records = 16MB at
// 0x30000000, ~50-150ms of full-resolution history). Read from the MiSTer:
//   dd if=/dev/mem of=/tmp/trace.bin bs=1M skip=768 count=16 iflag=skip_bytes
// then decode offline (trace2vcd.py or scripts/decode).
wire dtrace_active;
reg trace_trig = 0;
reg [24:0] trace_boot_ctr = 0;
always @(posedge clk_sys) begin
	if (reset) begin
		trace_trig <= 0;
		trace_boot_ctr <= 0;
	end else begin
		// IWM access in bank 00 or the E0/E1 fold (physical/translated bus)
		if (phi2 && addr_bus[15:4] == 12'hC0E &&
		    (addr_bus[23:16] == 8'h00 || addr_bus[23:16] == 8'hE0 || addr_bus[23:16] == 8'hE1))
			trace_trig <= 1;
		// fallback: arm ~1.17s after reset regardless (2^24 clk_sys), so the
		// wedge steady-state is captured even if the address arm never fires
		if (!trace_boot_ctr[24]) trace_boot_ctr <= trace_boot_ctr + 25'd1;
		if (trace_boot_ctr[24]) trace_trig <= 1;
	end
end
ddr_trace #(.CYCLE_BITS(8), .FIFO_BITS(12), .ADDR(32'h3000_0000), .RECORDS('h20_0000)) dtrace (
	.clk(clk_sys),
	.data({25'd0, use_cache_path, wr_pending, cache_hit_now, mem_stall, accel_r, we, phi2, addr_bus[23:0]}),
	.trigger(trace_trig),
	.DDRAM_CLK(DDRAM_CLK), .DDRAM_BUSY(DDRAM_BUSY), .DDRAM_BURSTCNT(DDRAM_BURSTCNT),
	.DDRAM_ADDR(DDRAM_ADDR), .DDRAM_RD(DDRAM_RD), .DDRAM_DIN(DDRAM_DIN),
	.DDRAM_BE(DDRAM_BE), .DDRAM_WE(DDRAM_WE),
	.dbg_active(dtrace_active)
);
`endif


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

`ifdef DEBUG_PIXEL_OVERLAY
// ---- TEMPORARY: floppy-boot chain probe (no floppy boots on HW 2026-07-09) ----
// One row of 16px bit-blocks at py 100-132, MSB first:
//   idx 0  img_mounted[3] pulse seen (sticky)      idx 1  woz_ctrl_525_mount (live)
//   idx 2  woz_ctrl_525_disk_mounted (live)        idx 3  woz_ctrl_525_ready (live)
//   idx 4  woz_ctrl_525_busy (live)                idx 5  sd_rd[3] seen (sticky)
//   idx 6  sd_ack[3] seen (sticky)                 idx 7  track_load_complete 525 (live)
//   idx 8  floppy_motor_on seen (sticky)           idx 9  floppy_motor_on (live)
//   idx 10 IWM $C0Ex phi2 access seen (sticky)     idx 11 img_mounted[2] seen (sticky)
//   idx 12 qtrack exceeded clamp (sticky)          idx 13 HPS same-LBA double-serve seen (sticky)
//   idx 14-21 WOZ_TRACK1_QTRACK[7:0] (live)        idx 22-29 woz_sd_525_lba[7:0] (live)
reg dbg_mnt3_seen, dbg_rd3_seen, dbg_ack3_seen, dbg_motor_seen;
reg dbg_iwm_seen, dbg_mnt2_seen;
// Tear-proof head-position forensics, latched in the SAME clock domain as
// WOZ_TRACK1_QTRACK (clk_sys) so pixel-sampling artifacts are impossible:
//   dbg_max_qtrack  - highest head position ever reached
//   dbg_impossible  - sticky: head exceeded the 5.25" stepper clamp (139+3)
reg [8:0] dbg_max_qtrack;
reg       dbg_impossible;
// HPS double-serve forensics: latch sd_lba at each slot-3 ack RISE. If Main
// re-serves the same LBA back-to-back, lba_hist0==lba_hist1 and dup_seen sets.
reg       dbg_ack3_d;
reg [7:0] dbg_lba_hist0, dbg_lba_hist1;
reg       dbg_dup_seen;
always @(posedge clk_sys) begin
	if (img_mounted[3])      dbg_mnt3_seen  <= 1'b1;
	if (sd_rd[3])            dbg_rd3_seen   <= 1'b1;
	if (sd_ack[3])           dbg_ack3_seen  <= 1'b1;
	if (floppy_motor_on)     dbg_motor_seen <= 1'b1;
	if (img_mounted[2])      dbg_mnt2_seen  <= 1'b1;
	if (WOZ_TRACK1_QTRACK > dbg_max_qtrack) dbg_max_qtrack <= WOZ_TRACK1_QTRACK;
	if (WOZ_TRACK1_QTRACK > 9'd142)         dbg_impossible <= 1'b1;
	dbg_ack3_d <= sd_ack[3];
	if (~dbg_ack3_d & sd_ack[3]) begin
		dbg_lba_hist1 <= dbg_lba_hist0;
		dbg_lba_hist0 <= woz_sd_525_lba[7:0];
		if (woz_sd_525_lba[7:0] == dbg_lba_hist0) dbg_dup_seen <= 1'b1;
	end
	if (phi2 && addr_bus[15:4] == 12'hC0E &&
	    (addr_bus[23:16] == 8'h00 || addr_bus[23:16] == 8'h01 ||
	     addr_bus[23:16] == 8'hE0 || addr_bus[23:16] == 8'hE1))
		dbg_iwm_seen <= 1'b1;
end
wire vga_de_dbg = ~(vblank | hblank);
reg [9:0]  dbg_px; reg [8:0] dbg_py;
reg        dbg_de_d, dbg_vs_d;
reg [29:0] dbg_sample;
always @(posedge clk_vid) if (ce_pix) begin
	dbg_de_d <= vga_de_dbg;  dbg_vs_d <= vsync;
	if (vsync & ~dbg_vs_d) begin
		dbg_sample <= {dbg_mnt3_seen, woz_ctrl_525_mount, woz_ctrl_525_disk_mounted,
		               woz_ctrl_525_ready, woz_ctrl_525_busy, dbg_rd3_seen,
		               dbg_ack3_seen, woz_ctrl_525_track_load_complete,
		               dbg_motor_seen, floppy_motor_on, dbg_iwm_seen, dbg_mnt2_seen,
		               dbg_impossible, dbg_dup_seen,
		               WOZ_TRACK1_QTRACK[7:0], woz_sd_525_lba[7:0]};
		dbg_py <= 9'd0;  dbg_px <= 10'd0;
	end else if (vga_de_dbg) begin
		dbg_px <= dbg_px + 10'd1;
	end else if (dbg_de_d & ~vga_de_dbg) begin
		dbg_px <= 10'd0;  dbg_py <= dbg_py + 9'd1;
	end
end
wire       dbg_area = (dbg_py >= 9'd100) && (dbg_py < 9'd132) &&
                      (dbg_px >= 10'd16) && (dbg_px < 10'd16 + 10'd480);
wire [4:0] dbg_idx  = (dbg_px - 10'd16) >> 4;
wire       dbg_bit  = dbg_sample[5'd29 - dbg_idx];
assign VGA_R = dbg_area ? (dbg_bit ? 8'hFF : 8'h18) : iigs_r;
assign VGA_G = dbg_area ? (dbg_bit ? 8'hFF : 8'h18) : iigs_g;
assign VGA_B = dbg_area ? 8'h00                     : iigs_b;
`else
assign VGA_R = iigs_r;
assign VGA_G = iigs_g;
assign VGA_B = iigs_b;
`endif

assign CLK_VIDEO=clk_vid;



// HARD DRIVE PARTS (supports 2 units - ProDOS limit)
wire [15:0] hdd_sector;

// Both HDD units share the same sector (routed to their block device indices)
assign sd_lba[0] = {16'b0, hdd_sector};  // Unit 0
assign sd_lba[1] = {16'b0, hdd_sector};  // Unit 1
assign sd_lba[2] = woz_sd_lba;
assign sd_lba[3] = woz_sd_525_lba;
// Per-ROM image: ROM1 and ROM3 use different PRAM layouts/checksums, so each
// would invalidate (and re-default) the other's saved image. The file is two
// 512-byte blocks — block 0 = ROM3, block 1 = ROM1 — selected by the live ROM
// switch, so each ROM only ever sees its own image.
assign sd_lba[4] = {31'd0, rom_select};  // rom_select: 0=ROM3, 1=ROM1

// ---- PRAM / TWGS NVRAM save-restore (slot 4) ----------------------------
// X68000-style: mountable SD file (SC4: remounted automatically at core
// start) + explicit Save/Load OSD commands. Auto-load fires on mount and on a
// ROM-version switch (to fetch that ROM's block); a completed load pulses a
// warm reset so the ROM re-reads PRAM into its live settings (they are only
// consulted at boot). A zeroed/blank block fails the ROM's PRAM checksum and
// the firmware re-defaults itself, so a fresh file can't brick anything.
// Block layout: [0-255]=PRAM, [256-287]=TWGS X2444, rest pads $FF.
// See doc/pram-nvram-save-handoff.md.
wire       bk_save_cmd = status[21];
wire       bk_load_cmd = status[22];
wire [8:0] nv_addr = sd_buff_addr;
wire [7:0] nv_din  = sd_buff_dout;
wire [7:0] nv_dout;
reg        bk_sd_rd, bk_sd_wr;
reg        bk_state, bk_loading;
reg        bk_mounted;      // slot-4 file currently mounted (nonzero size)
reg [15:0] nv_reset_cnt;    // stretched (~1ms) warm reset after a load
wire       nv_load_reset = (nv_reset_cnt != 16'd0);
wire       nv_wr = bk_state & bk_loading & sd_buff_wr & sd_ack[4];
assign     sd_buff_din[4] = nv_dout;

reg bk_old_load, bk_old_save, bk_old_ack, bk_old_mounted, bk_old_rom;
always @(posedge clk_sys) begin
	bk_old_load    <= bk_load_cmd;
	bk_old_save    <= bk_save_cmd;
	bk_old_ack     <= sd_ack[4];
	bk_old_mounted <= img_mounted[4];
	bk_old_rom     <= rom_select;
	if (nv_reset_cnt != 16'd0) nv_reset_cnt <= nv_reset_cnt - 16'd1;

	// img_mounted pulses on mount AND unmount; img_size==0 = unmount
	if (~bk_old_mounted & img_mounted[4]) bk_mounted <= (img_size != 64'd0);

	if (~bk_old_ack & sd_ack[4]) {bk_sd_rd, bk_sd_wr} <= 2'b00;

	if (!bk_state) begin
		if ((~bk_old_load & bk_load_cmd) ||
		    (~bk_old_mounted & img_mounted[4] && img_size != 64'd0) ||
		    (bk_mounted && (rom_select != bk_old_rom))) begin
			bk_state   <= 1'b1;
			bk_loading <= 1'b1;
			bk_sd_rd   <= 1'b1;
		end else if (~bk_old_save & bk_save_cmd) begin
			bk_state   <= 1'b1;
			bk_loading <= 1'b0;
			bk_sd_wr   <= 1'b1;
		end
	end else if (bk_old_ack & ~sd_ack[4]) begin
		bk_state   <= 1'b0;   // single 512-byte block per transfer
		if (bk_loading) nv_reset_cnt <= 16'hFFFF;  // warm reset: ROM re-reads PRAM
		bk_loading <= 1'b0;
	end
end

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
wire [8:0]  WOZ_TRACK1_QTRACK;    // Full quarter-track head position (half-track seeks)
wire        WOZ_TRACK1_DATA_VALID; // BRAM data matches the requested 5.25" track
// 5.25" TMAP index from the head position, at quarter-track resolution.
// This drive model's head coordinate sits +2 quarter-tracks above the WOZ TMAP
// convention (4am/Applesauce): e.g. the loader energizes PH3 for half-track 27
// (track 13.5, TMAP index 54) but the head model rests at quarter-track 56.
// Subtracting 2 aligns the head with the TMAP index so half-track copy
// protection (Lode Runner stores track 14 at index 54/58) reads the real track
// instead of the empty whole-track slot. For whole-track rests (head_phase
// congruent to 2 mod 4) this yields exactly the old (head>>2)*4 index, so normal
// disks are unaffected.
wire [7:0]  woz_track1_id = (WOZ_TRACK1_QTRACK >= 9'd2)
                            ? (WOZ_TRACK1_QTRACK[7:0] - 8'd2)
                            : 8'd0;
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
	if (drive35_eject_req) begin
		woz_ctrl_mount <= 1'b0;
		woz_ctrl_remount_pending <= 1'b0;
	end else if (~img_mounted2_d & img_mounted[2]) begin
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
	.disk_type_mismatch(),

	// Write-protect flag from WOZ INFO chunk
	.disk_write_protected(WOZ_TRACK3_WP),
	.dbg_load_sum(),
	.dbg_load_bytes(),
	.dbg_load_blocks()
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
	.track_id(woz_track1_id),          // Quarter-track TMAP index (half-track aware; see woz_track1_id)
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
	.track_data_valid(WOZ_TRACK1_DATA_VALID),

	// Disk type mismatch
	.disk_type_mismatch(),

	// Write-protect flag from WOZ INFO chunk
	.disk_write_protected(WOZ_TRACK1_WP),
	.dbg_load_sum(),
	.dbg_load_bytes(),
	.dbg_load_blocks()
);

endmodule
