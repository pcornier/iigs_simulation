// Define DEBUG_SIM to enable verbose simulation debug output
// `define DEBUG_SIM

`timescale 1ns / 1ps
/*============================================================================
===========================================================================*/

module emu (

        input CLK_14M,
        input clk_vid_ext,     // DUALRATE: 28MHz video clock driven by sim_main (2x CLK_14M); unused otherwise
        input clk_mem_ext,     // SDRAM_SIM: 114.5MHz memory clock driven by sim_main (8x CLK_14M); unused otherwise
        input reset,
        input cold_reset,      // 1 = cold/power-on reset (full init), 0 = warm reset
        input soft_reset,
        input menu,
        input adam,

        input [31:0] joystick_0,
        input [31:0] joystick_1,
        input [31:0] joystick_2,
        input [31:0] joystick_3,
        input [31:0] joystick_4,
        input [31:0] joystick_5,

        input [15:0] joystick_l_analog_0,
        input [15:0] joystick_l_analog_1,
        input [15:0] joystick_l_analog_2,
        input [15:0] joystick_l_analog_3,
        input [15:0] joystick_l_analog_4,
        input [15:0] joystick_l_analog_5,

        input [15:0] joystick_r_analog_0,
        input [15:0] joystick_r_analog_1,
        input [15:0] joystick_r_analog_2,
        input [15:0] joystick_r_analog_3,
        input [15:0] joystick_r_analog_4,
        input [15:0] joystick_r_analog_5,

        input [7:0] paddle_0,
        input [7:0] paddle_1,
        input [7:0] paddle_2,
        input [7:0] paddle_3,
        input [7:0] paddle_4,
        input [7:0] paddle_5,

        input [8:0] spinner_0,
        input [8:0] spinner_1,
        input [8:0] spinner_2,
        input [8:0] spinner_3,
        input [8:0] spinner_4,
        input [8:0] spinner_5,

        // ps2 alternative interface.
        // [8] - extended, [9] - pressed, [10] - toggles with every press/release
        input [10:0] ps2_key,

        // [24] - toggles with every event
        input [24:0] ps2_mouse,
        input [15:0] ps2_mouse_ext, // 15:8 - reserved(additional buttons), 7:0 - wheel movements

        // Self-test mode override
        input selftest_override,

        // Sim-only: cross-wire SCC channels as an external serial loopback cable
        input serial_loopback,

        // CPU speed control (--speed flag): 0=native 2.86MHz .. 4=14.32MHz.
        // Shares state with the ZipGS $C058-$C05F software interface.
        input [2:0] host_speed,

        // ROM selection: 0=ROM3, 1=ROM1
        input rom_select/*verilator public_flat*/,

        // [31:0] - seconds since 1970-01-01 00:00:00, [32] - toggle with every change
        input [32:0] TIMESTAMP,

        output [7:0] VGA_R,
        output [7:0] VGA_G,
        output [7:0] VGA_B,

        output VGA_HS,
        output VGA_VS,
        output VGA_HB,
        output VGA_VB,

        output CE_PIXEL,

        output	[15:0]	AUDIO_L,
        output	[15:0]	AUDIO_R,

        input			ioctl_download,
        input			ioctl_wr,
        input [24:0]		ioctl_addr,
        input [7:0]		ioctl_dout,
        input [7:0]		ioctl_index,
        output reg		ioctl_wait=1'b0,

        output [31:0]           sd_lba[6],
        output [9:0]            sd_rd,
        output [9:0]            sd_wr,
        input [9:0]             sd_ack,
        input [8:0]             sd_buff_addr,
        input [7:0]             sd_buff_dout,
        output [7:0]            sd_buff_din[6],
        input                   sd_buff_wr,
        input [9:0]             img_mounted,
        input                   img_readonly,

        input [63:0]			img_size,

        // Keyboard-triggered reset outputs (from Ctrl+F11 or Ctrl+OpenApple+F11)
        output keyboard_reset,
        output keyboard_cold_reset

);
  initial begin
    //$dumpfile("test.fst");
    //$dumpvars;
  end

wire [15:0] joystick_a0 =  joystick_l_analog_0;

wire UART_RTS;
wire UART_TXD;
// UART inputs: RXD idle (mark=1), CTS asserted (clear to send=0)
wire UART_RXD = 1'b1;
wire UART_CTS = 1'b0;
wire [23:0] addr_bus;
wire [1:0] rom_bankaddr;
wire [7:0] fastram_dout;
wire [7:0] iigs_dout;
wire [7:0] iigs_din;
wire   we/*verilator public_flat*/;
wire fastram_ce;
wire rom_ce;

// Unified memory address mux (mirrors IIgs.sv SDRAM address formation)
// ROM3 (256KB) loaded at FC0000 via ioctl_index==0 (boot.rom)
// ROM1 (128KB) loaded at F80000 via ioctl_index==0x40 (boot1.rom, [15:6]==1)
wire rom3_loading = ioctl_download && (ioctl_index[7:6] == 2'd0);
wire rom1_loading = ioctl_download && (ioctl_index[7:6] != 2'd0);

wire [23:0] mem_addr = rom3_loading                  ? {6'b111111, ioctl_addr[17:0]} :
                       rom1_loading                  ? {7'b1111100, ioctl_addr[16:0]} :
                       (rom_ce & ~we & ~rom_select)  ? {6'b111111, rom_bankaddr, addr_bus[15:0]} :
                       (rom_ce & ~we &  rom_select)  ? {7'b1111100, rom_bankaddr[0], addr_bus[15:0]} :
                       {1'b0, addr_bus[22:0]};

// Speed-selected CPU read byte, mirroring the FPGA datapath selection in
// Apple-IIgs.sv (accel_r mux): native uses the REGISTERED BRAM output --
// bit-identical to the historical sim path (the HDD DMA readback alignment
// depends on it, so regression stays byte-exact) -- while any accelerated
// step uses the COMB read mirror, like the sdram_cache comb hit port. The
// registered output is one CLK_14M tick late, which is invisible at >=2-tick
// CPU cycles but returns the PREVIOUS address's byte at the 1-tick 14.32 MHz
// step (instant BRK-loop derail at reset).
wire accel_active_w;
wire [7:0] fastram_dout_comb;
wire phi2_w;
wire dbg_hdd_dma_w;
`ifdef SDRAM_SIM
// FPGA-accurate memory path: iigs_din comes from the sdram_burst+sdram_cache
// bridge below (exactly the Apple-IIgs.sv datapath); instant dpram unused.
wire mem_stall_sim;
`else
// Datapath-switch guard -- the plain-sim analogue of the SDRAM_SIM/Apple-IIgs.sv
// guard (see `use_cache_path` below). The registered BRAM read (fastram_dout) is
// one CLK_14M tick late and returns the PREVIOUS address's byte on the first
// native cycle right after an accelerated (1-tick) cycle. When the IWM $C0Ex
// hold-off flips accel_active_w 1->0 mid-run, that stale byte corrupts the very
// next instruction fetch: at 14.32 MHz the operand of `BIT $C0ED` (FF:4715)
// read back as $2C, so the ROM's SETIWMMODE ran `BIT $C02C`, never set IWM Q6,
// and the mode-register verify loop at FF:4720 spun forever (Lode Runner and any
// 5.25" boot hung on the splash). Serve the comb read for 2 committed cycles
// after accel_active_w changes so the registered path can warm up. Dormant in
// steady native (guard stays 0 -> registered read -> byte-identical regression;
// speed-0 never toggles accel_active_w) and in steady accelerated running.
reg        accel_r_plain    = 1'b0;
reg [1:0]  accel_guard_plain = 2'd0;
always @(posedge clk_sys) begin
    if (phi2_w) begin
        accel_r_plain <= accel_active_w;
        if (accel_r_plain != accel_active_w)  accel_guard_plain <= 2'd2;
        else if (accel_guard_plain != 2'd0)   accel_guard_plain <= accel_guard_plain - 2'd1;
    end
end
wire mem_stall_sim = 1'b0;
assign iigs_din = (accel_active_w | (accel_guard_plain != 2'd0))
                  ? fastram_dout_comb : fastram_dout;
`endif

// WOZ bit interfaces for flux-based IWM
// 3.5" drive 1 WOZ bit interface
wire [7:0]  WOZ_TRACK3;           // Track number being read
wire [15:0] WOZ_TRACK3_BIT_ADDR;  // Byte address in track bit buffer (16-bit for FLUX)
wire        WOZ_TRACK3_STABLE_SIDE; // Stable side for data reads (captured when motor starts)
wire [7:0]  WOZ_TRACK3_BIT_DATA;  // Byte from track bit buffer
wire [31:0] WOZ_TRACK3_BIT_COUNT; // Total bits in track
wire        WOZ_TRACK3_READY;     // Track data valid for current WOZ_TRACK3
wire        WOZ_TRACK3_DATA_VALID; // BRAM data valid for selected side (no state check)
wire        WOZ_TRACK3_IS_FLUX;   // Track data is flux timing (not bitstream)
wire [31:0] WOZ_TRACK3_FLUX_SIZE; // Size in bytes of flux data (when IS_FLUX)
wire [31:0] WOZ_TRACK3_FLUX_TOTAL_TICKS; // Sum of FLUX bytes for timing normalization
wire        WOZ_TRACK3_WP;        // Write-protected flag from WOZ INFO chunk
wire        woz_ctrl_ready;

// 5.25" drive 1 WOZ bit interface
wire [5:0]  WOZ_TRACK1;           // Track number being read
wire [8:0]  WOZ_TRACK1_QTRACK;    // Full quarter-track head position (half-track seeks)
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
wire [15:0] WOZ_TRACK1_BIT_ADDR;  // Byte address in track bit buffer (16-bit for FLUX)
wire [7:0]  WOZ_TRACK1_BIT_DATA;  // Byte from track bit buffer
wire [31:0] WOZ_TRACK1_BIT_COUNT; // Total bits in track
wire        WOZ_TRACK1_IS_FLUX;   // Track data is flux timing (not bitstream)
wire [31:0] WOZ_TRACK1_FLUX_SIZE; // Size in bytes of flux data (when IS_FLUX)
wire [31:0] WOZ_TRACK1_FLUX_TOTAL_TICKS; // Sum of FLUX bytes for timing normalization
wire        WOZ_TRACK1_WP;        // Write-protected flag from WOZ INFO chunk

// Write interfaces from IWM back to WOZ controllers
wire [7:0]  WOZ_TRACK3_BIT_DATA_IN;  // Write byte for 3.5" BRAM
wire        WOZ_TRACK3_BIT_WE;       // Write enable for 3.5"
wire [15:0] WOZ_TRACK3_BIT_WR_ADDR;  // Write address for 3.5" (latched)
wire [7:0]  WOZ_TRACK1_BIT_DATA_IN;  // Write byte for 5.25" BRAM
wire        WOZ_TRACK1_BIT_WE;       // Write enable for 5.25"
wire [15:0] WOZ_TRACK1_BIT_WR_ADDR;  // Write address for 5.25" (latched)

// --- System / video clock derivation ------------------------------------
// FASTSIM (default): one collapsed clock -- the CLK_14M input drives clk_sys
//   AND clk_vid, ce_pix=1. Fast, but the CPU<->video phase is a Verilator
//   scheduling artifact (over-amplifies beam-racing timing error).
// FAITHFUL_CLOCK: the CLK_14M *input* is driven at 28.6MHz by sim_main; derive
//   the 14.3MHz system clock (clk_sys = clk_28/2) and run video on the full
//   28.6MHz clk_vid with ce_pix gating -- mirroring Apple-IIgs.sv (PLL clk_28 +
//   clk_sys=clk_28/2, ce_pix toggling on clk_vid). Reproduces the hardware
//   CPU<->video phase so beam-racing timing is faithful.
// clk_sys (14.3MHz) drives the CPU/memory/system -- kept == CLK_14M in BOTH modes
// so the C++ memory model (serviced on CLK_14M edges in sim_main) stays in sync
// and the system boots. Only the VIDEO clock phase differs:
//   FASTSIM        : clk_vid == clk_sys  -> video advances on the SAME edge as the
//                    CPU (0 phase offset). The CPU<->video race is then a Verilator
//                    scheduling artifact, which over-amplifies beam-racing error.
//   FAITHFUL_CLOCK : clk_vid == ~clk_sys -> video advances on clk_sys's *negedge*,
//                    a defined half-cycle CPU<->video phase offset. On hardware
//                    video advances on ce_pix-gated clk_28 posedges, which (clk_28
//                    being exactly 2x, phase-aligned clk_sys) land on clk_sys edges;
//                    the negedge-phased case is this. Reproduces a real hardware
//                    phase without a 2x eval rate.
wire clk_sys = CLK_14M;
`ifdef DUALRATE_CLOCK
// True dual-rate: CPU/memory stay on CLK_14M (14.3MHz, serviced by sim_main as
// usual -> no boot blocker); the VIDEO runs on clk_vid_ext, driven by sim_main at
// 28.6MHz (2x, one extra eval per CPU half-cycle). This separates the VGC's
// text-page BRAM read (clk_vid posedge) from the CPU write (clk_sys posedge) in
// time, as on real hardware (clk_28 / clk_sys=/2), fixing the collapsed-clock
// same-edge stale read that streaks textfunk's beam-raced tunnel center.
wire clk_28  = clk_vid_ext;
wire clk_vid = clk_vid_ext;
`elsif FAITHFUL_CLOCK
wire clk_28  = CLK_14M;
wire clk_vid = ~CLK_14M;
`else
wire clk_28  = CLK_14M;
wire clk_vid = CLK_14M;
`endif

// Register stable_side to match BRAM timing - prevents 1-cycle glitches on side change
reg woz3_stable_side_reg;
always @(posedge clk_sys) begin
    woz3_stable_side_reg <= WOZ_TRACK3_STABLE_SIDE;
end

iigs  iigs(
        .reset(reset),
        .cold_reset(cold_reset),
        .CLK_28M(clk_28),
        .CLK_14M(clk_sys),
        .clk_vid(clk_vid),
        .ce_pix(ce_pix),
        .timestamp(TIMESTAMP),//{33{1'b0}}),  // Add missing timestamp connection
        .floppy_wp(1'b1),  // Add missing floppy_wp
        .R(VGA_R),
        .G(VGA_G),
        .B(VGA_B),
        .HBlank(hblank),
        .VBlank(vblank),
        .HS(hsync),
        .VS(vsync),
        /* hard drive (supports 2 units - ProDOS limit) */
        .HDD_SECTOR(hdd_sector),
        .HDD_READ({sd_rd[3], sd_rd[1]}),
        .HDD_WRITE({sd_wr[3], sd_wr[1]}),
        .HDD_MOUNTED({img_mounted[3], img_mounted[1]}),
        .img_readonly(img_readonly),
        .img_size(img_size),
        .HDD_RAM_ADDR(sd_buff_addr),
        .HDD_RAM_DI(sd_buff_dout),
        .HDD_RAM_DO(hdd_ram_do),
        .HDD_RAM_WE(sd_buff_wr & (sd_ack[3] | sd_ack[1])),
        .HDD_ACK({sd_ack[3], sd_ack[1]}),

    // Mounted-media bitmap to IWM (pad to 4 bits)
    // [0] = 5.25" WOZ media mounted, [1] = 0, [2] = 3.5" WOZ media mounted, [3] = 0
    // Drive-mechanism presence is modeled separately inside iwm_woz.
    .DISK_READY({1'b0, woz_ctrl_disk_mounted, 1'b0, woz_ctrl_525_disk_mounted}),

    .WOZ_TRACK3(WOZ_TRACK3),
    .WOZ_TRACK3_BIT_ADDR(WOZ_TRACK3_BIT_ADDR),
    .WOZ_TRACK3_STABLE_SIDE(WOZ_TRACK3_STABLE_SIDE),
    .WOZ_TRACK3_BIT_DATA(WOZ_TRACK3_BIT_DATA),
    .WOZ_TRACK3_BIT_COUNT(WOZ_TRACK3_BIT_COUNT),
    .WOZ_TRACK3_READY(WOZ_TRACK3_READY),
    .WOZ_TRACK3_DATA_VALID(WOZ_TRACK3_DATA_VALID),
    .WOZ_TRACK3_LOAD_COMPLETE(woz_ctrl_track_load_complete),
    .WOZ_TRACK3_IS_FLUX(WOZ_TRACK3_IS_FLUX),
    .WOZ_TRACK3_FLUX_SIZE(WOZ_TRACK3_FLUX_SIZE),
    .WOZ_TRACK3_FLUX_TOTAL_TICKS(WOZ_TRACK3_FLUX_TOTAL_TICKS),
    .WOZ_TRACK3_WP(WOZ_TRACK3_WP),
    .WOZ_TRACK3_BIT_DATA_IN(WOZ_TRACK3_BIT_DATA_IN),
    .WOZ_TRACK3_BIT_WE(WOZ_TRACK3_BIT_WE),
    .WOZ_TRACK3_BIT_WR_ADDR(WOZ_TRACK3_BIT_WR_ADDR),

    // WOZ bit interface for 5.25" drive 1
    .WOZ_TRACK1(WOZ_TRACK1),
    .WOZ_TRACK1_QTRACK(WOZ_TRACK1_QTRACK),
    .WOZ_TRACK1_DATA_VALID(WOZ_TRACK1_DATA_VALID),
    .WOZ_TRACK1_BIT_ADDR(WOZ_TRACK1_BIT_ADDR),
    .WOZ_TRACK1_BIT_DATA(WOZ_TRACK1_BIT_DATA),
    .WOZ_TRACK1_BIT_COUNT(WOZ_TRACK1_BIT_COUNT),
    .WOZ_TRACK1_LOAD_COMPLETE(woz_ctrl_525_track_load_complete),
    .WOZ_TRACK1_IS_FLUX(WOZ_TRACK1_IS_FLUX),
    .WOZ_TRACK1_FLUX_SIZE(WOZ_TRACK1_FLUX_SIZE),
    .WOZ_TRACK1_FLUX_TOTAL_TICKS(WOZ_TRACK1_FLUX_TOTAL_TICKS),
    .WOZ_TRACK1_WP(WOZ_TRACK1_WP),
    .WOZ_TRACK1_BIT_DATA_IN(WOZ_TRACK1_BIT_DATA_IN),
    .WOZ_TRACK1_BIT_WE(WOZ_TRACK1_BIT_WE),
    .WOZ_TRACK1_BIT_WR_ADDR(WOZ_TRACK1_BIT_WR_ADDR),

        .top_addr(addr_bus),
        .rom_bankaddr(rom_bankaddr),
        .top_dout(iigs_dout),
        .top_din(iigs_din),
        .we(we),
        .fastram_ce(fastram_ce),
        .rom_ce(rom_ce),
        .rom_select(rom_select),

        .ps2_key(ps2_key),
        .ps2_mouse(ps2_mouse),
        .selftest_override(selftest_override),
        .serial_loopback(serial_loopback),
        .host_speed(host_speed),
        .accel_capable(1'b1),  // sim fast RAM is single-cycle BRAM: all speed steps safe
        .zip_regs_en(1'b1),    // ZipGS software interface always present in sim
        // OSD delay-toggle views: match the zipgs_regs power-on values so no
        // edge-apply fires (delays enabled, CPS off = the old "Auto" behavior)
        .osd_spkr_delay(1'b1),
        .osd_pdl_delay(1'b1),
        .osd_ctr_delay(1'b1),
        .osd_cps_follow(1'b0), // flip to 1'b1 to test 1MHz sync
        .osd_irq_delay(1'b1),  // AppleTalk/IRQ delay enabled (matches reset regs)
        .accel_irq_delay(),
        .accel_cfg_speed(),
        .accel_spkr_delay(),
        .accel_pdl_delay(),
        .accel_ctr_delay(),
        .accel_cps_follow(),
        .nv_addr(9'd0),      // NVRAM backup port unused in sim (HW SD slot 4)
        .nv_wr(1'b0),
        .nv_din(8'd0),
        .nv_dout(),
        .twgs_present(1'b0),   // TWGS card off by default (flip to 1'b1 to test detection)
        // Detection verified 2026-07-11: with 1'b1, monitor `BC/FF00.FF0F` shows
        // 'TWGS''SMJS' + the JML table (54 57 47 53 53 4D 4A 53 / 5C 28 FB BC ...)
        .accel_active(accel_active_w),  // selects registered vs comb fastram read (as on FPGA)
        .phi2(phi2_w),
        .dbg_hdd_dma(dbg_hdd_dma_w),
        .mem_stall(mem_stall_sim), // SDRAM_SIM: real cache-miss/write-pending stall; else 0 (instant BRAM)

        .FLOPPY_WP(1'b1),
        
        // Joystick and paddle inputs
        .joystick_0(joystick_0),
        .joystick_1(joystick_1),
        .joystick_l_analog_0(joystick_l_analog_0),
        .joystick_l_analog_1(joystick_l_analog_1),
        .paddle_0(paddle_0),
        .paddle_1(paddle_1),
        .paddle_2(paddle_2),
        .paddle_3(paddle_3),

        // Keyboard-triggered reset outputs
        .keyboard_reset(keyboard_reset),
        .keyboard_cold_reset(keyboard_cold_reset),

        // Caps Lock LED (unused in vsim)
        .capslock(),

        // ZipGS cache-disable (no SDRAM cache in sim; observe only)
        .cache_disable(),

        // Floppy motor status (for dirty track flush on motor-off)
        .floppy_motor_on(floppy_motor_on),
        .floppy35_motor_on(floppy35_motor_on),
        .drive35_eject_req(drive35_eject_req),

        // Audio outputs
        .AUDIO_L(AUDIO_L),
        .AUDIO_R(AUDIO_R),

        // Serial (SCC Channel A = Modem port)
        .UART_TXD(UART_TXD),
        .UART_RXD(UART_RXD),
        .UART_RTS(UART_RTS),
        .UART_CTS(UART_CTS)
);

   //dpram #(.widthad_a(24),.prefix("fast")) fastram - unified ROM+RAM


dpram #(.widthad_a(24),.prefix("fast"),.sim_async_a(1)) fastram
(
        .clock_a(clk_sys),
        .address_a( mem_addr ),
        .data_a(ioctl_download ? ioctl_dout : iigs_dout),
        .q_a(fastram_dout),
        .q_a_comb(fastram_dout_comb),
        .wren_a((we & fastram_ce) | ioctl_wr),
        .ce_a(fastram_ce | rom_ce | ioctl_download),
        .clock_b(clk_sys),
        .wren_b(1'b0),
        .address_b({24{1'b0}}),
        .data_b(8'h00),
        .q_b()
);


`ifdef SDRAM_SIM
// ===========================================================================
// FPGA-ACCURATE MEMORY PATH (make SDRAM=sim)
//
// Instantiates the PRODUCTION sdram_burst controller + sdram_cache line
// buffer against the behavioral chip model, glued with a VERBATIM copy of
// the Apple-IIgs.sv bridge (accel_r datapath mux, ch0 write post with
// back-pressure, cache snoop, ch3 native reads, mem_stall into the CPU RDY).
// clk_mem_ext is driven by sim_main at 8x CLK_14M (114.5 MHz model).
// This is the path where "works in sim, fails on FPGA" memory bugs live --
// see doc/sdram_accel/02_sim_model_spec.md and doc/zipgs-14mhz-plan.md.
//
// A golden-model coherency checker compares every committed CPU read byte
// against a mirror of committed writes and prints SDRAMSIM_VIOLATION lines
// the moment the memory path serves stale data (e.g. the 14.3 MHz stale
// cache line seen on hardware, GS/OS boot corruption 2026-07-07).
// ===========================================================================
wire clk_mem = clk_mem_ext;

// SDRAM pins between the real controller and the behavioral chip
wire [15:0] SDRAM_DQ; wire [12:0] SDRAM_A;
wire SDRAM_DQML, SDRAM_DQMH; wire [1:0] SDRAM_BA;
wire SDRAM_nCS, SDRAM_nWE, SDRAM_nRAS, SDRAM_nCAS, SDRAM_CLK, SDRAM_CKE;

// CPU physical address exactly as Apple-IIgs.sv forms it (no ioctl term --
// uploads go through ch2 like the real core)
wire [23:0] cpu_sdram_addr =
                    (rom_ce & ~we & ~rom_select)  ? {6'b111111, rom_bankaddr, addr_bus[15:0]} :
                    (rom_ce & ~we &  rom_select)  ? {7'b1111100, rom_bankaddr[0], addr_bus[15:0]} :
                    {1'b0, addr_bus[22:0]};

// ---- ch0: CPU single-word write-through (posted; see back-pressure below) ----
reg         wr_req = 0;
wire        wr_ack;
reg  [24:1] wr_addr;
reg         wr_wrl, wr_wrh;
reg  [15:0] wr_din;

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

// Write back-pressure + stall rule -- verbatim from Apple-IIgs.sv
reg         wr_ack_s1, wr_ack_s2;
wire        wr_pending = (wr_req != wr_ack_s2);
assign mem_stall_sim = use_cache_path & ( (~we & (fastram_ce | rom_ce) & ~cache_hit_now)
                                        | ( we & fastram_ce & wr_pending) );
reg         snoop_stb;

// ch3: native single-word read
reg         nat_req = 0;
wire        nat_ack;
reg  [24:1] nat_addr;
reg         nat_bsel;
wire [15:0] nat_dout;
reg  [7:0]  nat_data;

// Datapath-switch guard -- verbatim from Apple-IIgs.sv (see comment there):
// serve reads through the cache for 2 committed cycles after accel_r changes
// while the ch3 pipeline warms up.
reg  [1:0]  accel_switch_guard = 0;
wire        use_cache_path = accel_r | (accel_switch_guard != 2'd0);

wire [7:0]  sdram_dout  = use_cache_path ? (cpu_sdram_addr[0] ? cache_data_now[15:8] : cache_data_now[7:0])
                                         : nat_data;
assign iigs_din = sdram_dout;

reg phi2_d;
always @(posedge clk_sys) begin
	phi2_d <= phi2_w;
	if (phi2_w) begin
		accel_r <= accel_active_w;
		if (accel_r != accel_active_w)        accel_switch_guard <= 2'd2;
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

	if (phi2_w & we & fastram_ce & ~(accel_r & wr_pending)) begin
		wr_addr <= {2'b00, addr_bus[22:1]};
		wr_din  <= {iigs_dout, iigs_dout};
		wr_wrl  <= ~addr_bus[0];
		wr_wrh  <=  addr_bus[0];
		wr_req  <= ~wr_req;
	end

	snoop_stb <= phi2_w & we & fastram_ce & ~(accel_r & wr_pending);
end

// ---- ch2: ioctl ROM upload (throttled via ioctl_wait, like the FPGA) ----
reg         up_req = 0;
wire        up_ack;
reg  [24:1] up_addr;
reg         up_wrl, up_wrh;
reg  [15:0] up_din;

wire [23:0] ioctl_sdram_addr = rom3_loading ? {6'b111111, ioctl_addr[17:0]}
                                            : {7'b1111100, ioctl_addr[16:0]};
// (verbatim from Apple-IIgs.sv; requires the HPS-accurate one-shot ioctl_wr
// strobe semantics -- see sim_bus.cpp, which deasserts wr while ioctl_wait
// throttles, exactly like data_io.v on hardware)
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

sdram_burst sdram
(
	.SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A), .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH),
	.SDRAM_BA(SDRAM_BA), .SDRAM_nCS(SDRAM_nCS), .SDRAM_nWE(SDRAM_nWE),
	.SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCAS(SDRAM_nCAS), .SDRAM_CLK(SDRAM_CLK), .SDRAM_CKE(SDRAM_CKE),
	// init falling-edge would RE-RUN the ~300-clk_mem power-on sequence; tying
	// it to reset made that overlap the CPU's first fetches (ch3 never stalls
	// -> garbage execution). The controller self-initializes from its declared
	// power-on state, matching the FPGA where init=~locked ends well before
	// the CPU leaves reset.
	.init(1'b0), .clk(clk_mem),
	.addr0(wr_addr), .wrl0(wr_wrl), .wrh0(wr_wrh), .din0(wr_din), .dout0(), .req0(wr_req), .ack0(wr_ack),
	.addr1(rd_addr), .wrl1(1'b0), .wrh1(1'b0), .din1(16'd0), .dout1(rd_line), .req1(rd_req), .ack1(rd_ack),
	.addr2(up_addr), .wrl2(up_wrl), .wrh2(up_wrh), .din2(up_din), .dout2(), .req2(up_req), .ack2(up_ack),
	.addr3(nat_addr), .dout3(nat_dout), .req3(nat_req), .ack3(nat_ack)
);

sdram_cache #(.LINES(8), .LINE_WORDS(8), .ADDR_W(24)) icache
(
	.clk(clk_sys), .reset(reset), .cache_off(1'b0),
	.cpu_addr(cache_addr), .cpu_rd(cache_rd), .cpu_data(cache_data),
	.cpu_ready(cache_ready), .cpu_stall(cache_stall),
	.hit_now(cache_hit_now), .cpu_data_now(cache_data_now),
	.wr_addr(wr_addr), .wr_data(wr_din), .wr_be({wr_wrh, wr_wrl}), .wr_stb(snoop_stb),
	.mem_addr(rd_addr), .mem_req(rd_req), .mem_ack(rd_ack), .mem_line(rd_line)
);

sdram_sim_chip #(.CAS(3), .ROWW(13), .COLW(9), .BANKS(4), .RD_LAT(2), .CHECK(1)) sdram_chip (
	.clk(clk_mem), .dq(SDRAM_DQ), .a(SDRAM_A), .ba(SDRAM_BA),
	.dqml(SDRAM_DQML), .dqmh(SDRAM_DQMH),
	.ncs(SDRAM_nCS), .nras(SDRAM_nRAS), .ncas(SDRAM_nCAS), .nwe(SDRAM_nWE)
);

// ---- golden-model coherency checker ----
// Mirrors every committed byte (ioctl upload, CPU/DMA write) and checks every
// committed CPU read against it. A mismatch = the memory path served stale
// data -- printed immediately with context. DMA reads are excluded (their
// data path has its own registered alignment checked elsewhere).
reg [7:0] golden_mem [0:(1<<24)-1] /*verilator public_flat*/;
reg       golden_v   [0:(1<<24)-1];
integer   golden_viol = 0;
always @(posedge clk_sys) begin
	if (ioctl_wr & ioctl_download) begin
		golden_mem[ioctl_sdram_addr] <= ioctl_dout;
		golden_v[ioctl_sdram_addr]   <= 1'b1;
	end
	if (phi2_w & we & fastram_ce & ~(accel_r & wr_pending)) begin
		golden_mem[{1'b0, addr_bus[22:0]}] <= iigs_dout;
		golden_v[{1'b0, addr_bus[22:0]}]   <= 1'b1;
	end
	if (phi2_w & ~we & (fastram_ce | rom_ce) & ~mem_stall_sim & ~dbg_hdd_dma_w
	    & golden_v[cpu_sdram_addr]) begin
		if (sdram_dout !== golden_mem[cpu_sdram_addr] && golden_viol < 50) begin
			golden_viol <= golden_viol + 1;
			$display("SDRAMSIM_VIOLATION #%0d t=%0t addr=%06x got=%02x exp=%02x accel_r=%b hit_now=%b wr_pending=%b",
			         golden_viol, $time, cpu_sdram_addr, sdram_dout,
			         golden_mem[cpu_sdram_addr], accel_r, cache_hit_now, wr_pending);
		end
	end
end
`endif

// ROM is now loaded via ioctl into the unified dpram at startup
// (ROM3: 256KB at addr FC0000-FFFFFF, ROM1: 128KB at addr FE0000-FFFFFF)

always @(posedge clk_sys) begin
`ifdef DEBUG_SIM
        if (reset) $display("TOPRESET");
`endif
end

`define FASTSIM 1
`ifdef DUALRATE_CLOCK
// clk_vid runs at 28.6MHz; gate the video pixel pipeline to a 14.3MHz enable
// (/2 of clk_vid) so the pixel/char rate and frame timing are unchanged -- only
// the BRAM-access phase relative to the CPU changes.
reg ce_pix_div = 1'b0;
always @(posedge clk_vid) ce_pix_div <= ~ce_pix_div;
wire ce_pix = ce_pix_div;
`elsif FAITHFUL_CLOCK
// clk_vid is already 14.3MHz (= ~clk_sys), so ce_pix=1: video advances every
// clk_vid posedge = every clk_sys negedge (the half-cycle phase offset).
wire ce_pix=1'b1;
`elsif FASTSIM
wire ce_pix=1'b1;
`else
reg ce_pix;
always @(posedge clk_sys) begin
        reg div ;

        div <= ~div;
        ce_pix <=  &div ;
end
`endif

wire hsync,vsync;
wire hblank,vblank;

assign CE_PIXEL=ce_pix;

assign VGA_HS=hsync;
assign VGA_VS=vsync;

assign VGA_HB=hblank;
assign VGA_VB=vblank;






// HARD DRIVE PARTS (supports 2 units - ProDOS limit)
wire [15:0] hdd_sector;

// HDD unit being served (latched when operation starts)
reg hdd_active_unit = 1'b0;

// Both HDD units share the same sector (routed to their block device indices)
assign sd_lba[1] = {16'b0, hdd_sector};  // Unit 0
assign sd_lba[3] = {16'b0, hdd_sector};  // Unit 1
// sd_lba[4] driven by woz_ctrl_525
// sd_lba[5] driven by woz_ctrl

// HDD RAM output - shared buffer routed to both HDD unit indices
wire [7:0] hdd_ram_do;
assign sd_buff_din[1] = hdd_ram_do;  // Unit 0
assign sd_buff_din[3] = hdd_ram_do;  // Unit 1
// sd_buff_din[4] driven by woz_ctrl_525
// sd_buff_din[5] driven by woz_ctrl

// Unused SD indices (formerly floppy_track_1 on index 0, floppy_track_2 on index 2)
assign sd_lba[0] = 32'b0;
assign sd_rd[0] = 1'b0;
assign sd_wr[0] = 1'b0;
assign sd_buff_din[0] = 8'h00;
assign sd_lba[2] = 32'b0;
assign sd_rd[2] = 1'b0;
assign sd_wr[2] = 1'b0;
assign sd_buff_din[2] = 8'h00;


// Floppy motor state from IWM (for dirty track flush on motor-off)
wire floppy_motor_on;
wire floppy35_motor_on;
wire drive35_eject_req;

// 3.5" WOZ controller outputs
wire        woz_ctrl_disk_mounted;
wire        woz_ctrl_busy;
wire [31:0] woz_ctrl_bit_count;
wire [7:0]  woz_ctrl_bit_data;
wire        woz_ctrl_track_load_complete;  // Pulses when track load finishes
wire [31:0] woz_ctrl_flux_total_ticks;

// Mount detection for WOZ controller (index 5)
// On disk swap (mount while already mounted), create a 1-cycle glitch:
//   woz_ctrl_mount goes 1→0 for 1 cycle, then back to 1 on the next cycle.
//   This gives the controller a falling+rising edge to trigger a rescan,
//   matching MiSTer behavior where a single mount pulse with new size arrives.
reg         img_mounted5_d = 0;
reg         woz_ctrl_mount = 0;
reg         woz_ctrl_remount_pending = 0;
reg         woz_ctrl_change = 0;

always @(posedge clk_sys) begin
    img_mounted5_d <= img_mounted[5];

    // Detect rising edge of img_mounted[5]
    if (drive35_eject_req) begin
        woz_ctrl_mount <= 1'b0;
        woz_ctrl_remount_pending <= 1'b0;
    end else if (~img_mounted5_d & img_mounted[5]) begin
        if (woz_ctrl_mount) begin
            // Already mounted: force unmount first, then remount next cycle
            woz_ctrl_mount <= 0;
            woz_ctrl_remount_pending <= (img_size != 0);
        end else begin
            woz_ctrl_mount  <= (img_size != 0);
        end
        woz_ctrl_change <= ~woz_ctrl_change;
`ifdef SIMULATION
        $display("WOZ_CTRL: Mount detected for index 5 (size=%0d, remount=%0d)", img_size, woz_ctrl_mount);
`endif
    end else if (woz_ctrl_remount_pending) begin
        // One cycle after unmount: complete the remount
        woz_ctrl_mount <= 1;
        woz_ctrl_remount_pending <= 0;
    end
end


woz_floppy_controller #(
    .IS_35_INCH(1)
) woz_ctrl (
    .clk(clk_sys),
    .reset(reset),

    // SD Block Device Interface (index 5)
    .sd_lba(sd_lba[5]),
    .sd_rd(sd_rd[5]),
    .sd_wr(sd_wr[5]),
    .sd_ack(sd_ack[5]),
    .sd_buff_addr(sd_buff_addr),
    .sd_buff_dout(sd_buff_dout),
    .sd_buff_din(sd_buff_din[5]),
    .sd_buff_wr(sd_buff_wr),

    // Disk Status
    .img_mounted(woz_ctrl_mount),
    .img_readonly(img_readonly),
    .img_size(img_size),

    // Drive Interface - use immediate track_id for correct bit_count timing
    // The woz_floppy_controller needs immediate track_id for position calculations.
    .track_id(WOZ_TRACK3),
    .ready(woz_ctrl_ready),
    .disk_mounted(woz_ctrl_disk_mounted),
    .busy(woz_ctrl_busy),
    .active(floppy35_motor_on),  // 3.5" motor state (from Sony drive logic, not 5.25" inertia)

    // Bitstream Interface - use same bit_addr as C++ path
    // Use REGISTERED stable_side to match C++ timing.
    // When side changes, the BRAM mux must switch in sync with the BRAM data update.
    // Using immediate stable_side causes a 1-cycle glitch where stale data is returned.
    .bit_count(woz_ctrl_bit_count),
    .bit_addr(WOZ_TRACK3_BIT_ADDR),
    .stable_side(woz3_stable_side_reg),
    .bit_data(woz_ctrl_bit_data),
    .bit_data_in(WOZ_TRACK3_BIT_DATA_IN),
    .bit_we(WOZ_TRACK3_BIT_WE),
    .bit_wr_addr(WOZ_TRACK3_BIT_WR_ADDR),
    // Track load notification (for flux_drive to reset bit_position)
    .track_load_complete(woz_ctrl_track_load_complete),

    // FLUX track support (WOZ v3)
    .is_flux_track(WOZ_TRACK3_IS_FLUX),
    .flux_data_size(WOZ_TRACK3_FLUX_SIZE),
    .flux_total_ticks(woz_ctrl_flux_total_ticks),

    // Track data validity (independent of controller state)
    .track_data_valid(WOZ_TRACK3_DATA_VALID),

    // Disk type mismatch
    .disk_type_mismatch(woz_35_type_mismatch),

    // Write-protect flag from WOZ INFO chunk
    .disk_write_protected(WOZ_TRACK3_WP),
    .dbg_load_sum(),
    .dbg_load_bytes(),
    .dbg_load_blocks()
);

// Connect 3.5" WOZ controller outputs to IIgs inputs
assign WOZ_TRACK3_BIT_DATA = woz_ctrl_bit_data;
assign WOZ_TRACK3_BIT_COUNT = woz_ctrl_bit_count;
assign WOZ_TRACK3_READY = woz_ctrl_ready;
assign WOZ_TRACK3_FLUX_TOTAL_TICKS = woz_ctrl_flux_total_ticks;

wire woz_35_type_mismatch;

// =========================================================================
// 5.25" WOZ Floppy Controller (index 4)
// =========================================================================
wire        woz_ctrl_525_disk_mounted;
wire        woz_ctrl_525_busy;
wire [31:0] woz_ctrl_525_bit_count;
wire [7:0]  woz_ctrl_525_bit_data;
wire        woz_ctrl_525_track_load_complete;
wire        woz_ctrl_525_is_flux;
wire [31:0] woz_ctrl_525_flux_size;
wire [31:0] woz_ctrl_525_flux_total_ticks;
wire        woz_525_type_mismatch;

// Mount detection for 5.25" WOZ controller (index 4)
// Same remount mechanism as 3.5" - see comments above
reg         img_mounted4_d = 0;
reg         woz_ctrl_525_mount = 0;
reg         woz_ctrl_525_remount_pending = 0;

always @(posedge clk_sys) begin
    img_mounted4_d <= img_mounted[4];
    if (~img_mounted4_d & img_mounted[4]) begin
        if (woz_ctrl_525_mount) begin
            woz_ctrl_525_mount <= 0;
            woz_ctrl_525_remount_pending <= (img_size != 0);
        end else begin
            woz_ctrl_525_mount <= (img_size != 0);
        end
`ifdef SIMULATION
        $display("WOZ_CTRL_525: Mount detected for index 4 (size=%0d, remount=%0d)", img_size, woz_ctrl_525_mount);
`endif
    end else if (woz_ctrl_525_remount_pending) begin
        woz_ctrl_525_mount <= 1;
        woz_ctrl_525_remount_pending <= 0;
    end
end

woz_floppy_controller #(
    .IS_35_INCH(0)
) woz_ctrl_525 (
    .clk(clk_sys),
    .reset(reset),

    // SD Block Device Interface (index 4)
    .sd_lba(sd_lba[4]),
    .sd_rd(sd_rd[4]),
    .sd_wr(sd_wr[4]),
    .sd_ack(sd_ack[4]),
    .sd_buff_addr(sd_buff_addr),
    .sd_buff_dout(sd_buff_dout),
    .sd_buff_din(sd_buff_din[4]),
    .sd_buff_wr(sd_buff_wr),

    // Disk Status
    .img_mounted(woz_ctrl_525_mount),
    .img_readonly(img_readonly),
    .img_size(img_size),

    // Drive Interface
    .track_id(woz_track1_id),          // Quarter-track TMAP index (half-track aware; see woz_track1_id)
    .ready(),                          // Not connected (5.25" uses DISK_READY[0])
    .disk_mounted(woz_ctrl_525_disk_mounted),
    .busy(woz_ctrl_525_busy),
    .active(floppy_motor_on),

    // Bitstream Interface
    .bit_count(woz_ctrl_525_bit_count),
    .bit_addr(WOZ_TRACK1_BIT_ADDR),  // 16-bit for bitstream and FLUX tracks
    .stable_side(1'b0),                // 5.25" is single-sided
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
    .disk_type_mismatch(woz_525_type_mismatch),

    // Write-protect flag from WOZ INFO chunk
    .disk_write_protected(WOZ_TRACK1_WP),
    .dbg_load_sum(),
    .dbg_load_bytes(),
    .dbg_load_blocks()
);

// Connect 5.25" WOZ controller outputs to IIgs inputs
assign WOZ_TRACK1_BIT_DATA = woz_ctrl_525_bit_data;
assign WOZ_TRACK1_BIT_COUNT = woz_ctrl_525_bit_count;
assign WOZ_TRACK1_IS_FLUX = woz_ctrl_525_is_flux;
assign WOZ_TRACK1_FLUX_SIZE = woz_ctrl_525_flux_size;
assign WOZ_TRACK1_FLUX_TOTAL_TICKS = woz_ctrl_525_flux_total_ticks;


endmodule
