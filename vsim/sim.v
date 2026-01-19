// Define DEBUG_SIM to enable verbose simulation debug output
// `define DEBUG_SIM

// BRAM_LATENCY: 0 = combinational (simulation), 1 = registered (FPGA)
// Can be overridden via -DWOZ_BRAM_LATENCY=1 in Verilator command line
// NOTE: BRAM_LATENCY=1 is work-in-progress; has 311-bit position drift issue
`ifndef WOZ_BRAM_LATENCY
`define WOZ_BRAM_LATENCY 1  // 0=combinational (sim), 1=registered (FPGA)
`endif

`timescale 1ns / 1ps
/*============================================================================
===========================================================================*/

module emu (

        input CLK_14M,
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
        output keyboard_cold_reset,

        // WOZ bit data inputs (from C++ sim_main.cpp)
        // 3.5" drive 1
        input [7:0]             woz3_bit_data,
        input [31:0]            woz3_bit_count,
        // 5.25" drive 1
        input [7:0]             woz1_bit_data,
        input [31:0]            woz1_bit_count,

        // WOZ track/address outputs (to C++ for data lookup)
        // 3.5" drive 1
        output [7:0]            woz3_track_out,
        output [13:0]           woz3_bit_addr_out,
        // 5.25" drive 1
        output [5:0]            woz1_track_out,
        output [12:0]           woz1_bit_addr_out,

        // WOZ disk ready inputs (from C++)
        input                   woz3_ready,
        input                   woz1_ready

);
  initial begin
    //$dumpfile("test.fst");
    //$dumpvars;
  end

wire [15:0] joystick_a0 =  joystick_l_analog_0;

wire UART_CTS;
wire UART_RTS;
wire UART_RXD;
wire UART_TXD;
wire UART_DTR;
wire UART_DSR;
    wire [22:0] fastram_address;
    wire [7:0] fastram_datatoram;
    wire [7:0] fastram_datafromram;
    wire fastram_we;
    wire fastram_ce;

    wire TRACK1_RAM_BUSY;
wire [13:0] TRACK1_RAM_ADDR;  // 14-bit for consistency with 3.5" drives
wire [7:0] TRACK1_RAM_DI;
wire [7:0] TRACK1_RAM_DO;
wire TRACK1_RAM_WE;
wire [5:0] TRACK1;

wire TRACK2_RAM_BUSY;
wire [13:0] TRACK2_RAM_ADDR;  // 14-bit for consistency with 3.5" drives
wire [7:0] TRACK2_RAM_DI;
wire [7:0] TRACK2_RAM_DO;
wire TRACK2_RAM_WE;
wire [5:0] TRACK2;

// 3.5" floppy drive 1 (drive 3 in IWM terms)
wire TRACK3_RAM_BUSY;
wire [13:0] TRACK3_RAM_ADDR;  // 14-bit for 10240-byte tracks
wire [7:0] TRACK3_RAM_DI;
wire [7:0] TRACK3_RAM_DO;
wire TRACK3_RAM_WE;
wire [6:0] TRACK3;            // 7-bit for 80 tracks per side
wire TRACK3_SIDE;
wire FD_DISK_3;

// WOZ bit interfaces for flux-based IWM
// 3.5" drive 1 WOZ bit interface
wire [7:0]  WOZ_TRACK3;           // Track number being read
wire [13:0] WOZ_TRACK3_BIT_ADDR;  // Byte address in track bit buffer
wire        WOZ_TRACK3_STABLE_SIDE; // Stable side for data reads (captured when motor starts)
wire [7:0]  WOZ_TRACK3_BIT_DATA;  // Byte from track bit buffer
wire [31:0] WOZ_TRACK3_BIT_COUNT; // Total bits in track
wire        WOZ_TRACK3_IS_FLUX;   // Track data is flux timing (not bitstream)
wire [31:0] WOZ_TRACK3_FLUX_SIZE; // Size in bytes of flux data (when IS_FLUX)
wire [31:0] WOZ_TRACK3_FLUX_TOTAL_TICKS; // Sum of FLUX bytes for timing normalization

// 5.25" drive 1 WOZ bit interface
wire [5:0]  WOZ_TRACK1;           // Track number being read
wire [12:0] WOZ_TRACK1_BIT_ADDR;  // Byte address in track bit buffer
wire [7:0]  WOZ_TRACK1_BIT_DATA;  // Byte from track bit buffer
wire [31:0] WOZ_TRACK1_BIT_COUNT; // Total bits in track

// Connect WOZ bit data - select between C++ and Verilog sources for 3.5"
// Define USE_CPP_WOZ to use C++ data path, comment out to use Verilog controller
//
// NOTE: The C++ path (BeforeEval) does NOT have inherent latency like BRAM does.
// BeforeEval reads the current address and immediately returns data for it.
// The Verilog BRAM has 1-cycle read latency. To match, we add a delay register
// to the C++ data when comparing.
//
// Enable C++ path for comparison (comment out to use Verilog path)
// `define USE_CPP_WOZ  // DISABLED - Testing Verilog with combinational BRAM

// Delay register for C++ data to match BRAM's 1-cycle latency for comparison
reg [7:0] woz3_bit_data_delayed;
always @(posedge CLK_14M) begin
    woz3_bit_data_delayed <= woz3_bit_data;
end

// Debug: log data flow when address changes and data is loaded
// Use delayed C++ data to match BRAM's 1-cycle latency
reg [31:0] flux_data_log_count = 0;
reg [31:0] flux_data_mismatch_count = 0;
reg [13:0] flux_data_last_addr = 0;
always @(posedge CLK_14M) begin
    if (woz3_bit_count > 0 && WOZ_TRACK3_BIT_ADDR != flux_data_last_addr) begin
        flux_data_last_addr <= WOZ_TRACK3_BIT_ADDR;
        // Log first 100 samples for initial debug
        if (flux_data_log_count < 100) begin
            $display("FLUX_DATA: addr=%04X cpp_d=%02X verilog=%02X MATCH=%0d count_cpp=%0d count_v=%0d (cpp_imm=%02X)",
                     WOZ_TRACK3_BIT_ADDR, woz3_bit_data_delayed, woz_ctrl_bit_data,
                     (woz3_bit_data_delayed == woz_ctrl_bit_data) ? 1 : 0,
                     woz3_bit_count, woz_ctrl_bit_count, woz3_bit_data);
            flux_data_log_count <= flux_data_log_count + 1;
        end
        // Always log mismatches
        if (woz3_bit_data_delayed != woz_ctrl_bit_data) begin
            flux_data_mismatch_count <= flux_data_mismatch_count + 1;
            if (flux_data_mismatch_count < 50) begin
                $display("FLUX_MISMATCH #%0d: addr=%04X cpp_d=%02X verilog=%02X ready=%0d s0=%0d s1=%0d req=%0d state=%0d stable_side=%0d",
                         flux_data_mismatch_count + 1, WOZ_TRACK3_BIT_ADDR, woz3_bit_data_delayed, woz_ctrl_bit_data,
                         woz_ctrl_ready, sim_woz_track_s0, sim_woz_track_s1, WOZ_TRACK3, sim_woz_state, WOZ_TRACK3_STABLE_SIDE);
            end
        end
        // Also log bit_count mismatches
        if (woz3_bit_count != woz_ctrl_bit_count && woz_ctrl_bit_count > 0) begin
            $display("BITCOUNT_MISMATCH: cpp=%0d verilog=%0d addr=%04X",
                     woz3_bit_count, woz_ctrl_bit_count, WOZ_TRACK3_BIT_ADDR);
        end
    end
end

`ifdef USE_CPP_WOZ
// C++ BeforeEval returns data immediately for the given address.
// The flux_drive expects immediate data response (no latency).
assign WOZ_TRACK3_BIT_DATA = woz3_bit_data;       // C++ immediate data
assign WOZ_TRACK3_BIT_COUNT = woz3_bit_count;        // bit_count is immediate
assign WOZ_TRACK3_FLUX_TOTAL_TICKS = 32'd0;
`else
// Verilog controller BRAM has 1-cycle read latency.
// The woz_floppy_controller needs to account for this internally.
assign WOZ_TRACK3_BIT_DATA = woz_ctrl_bit_data;   // Verilog woz_floppy_controller (BRAM has 1-cycle latency)
assign WOZ_TRACK3_BIT_COUNT = woz_ctrl_bit_count; // Verilog woz_floppy_controller
assign WOZ_TRACK3_FLUX_TOTAL_TICKS = woz_ctrl_flux_total_ticks;
`endif
assign WOZ_TRACK1_BIT_DATA = woz1_bit_data;
assign WOZ_TRACK1_BIT_COUNT = woz1_bit_count;

reg [7:0] old_woz_3;
always @(posedge clk_sys) begin
old_woz_3 <= WOZ_TRACK3;
if (old_woz_3!=WOZ_TRACK3)
      $display("WOZ_TRACK3 changed %d",WOZ_TRACK3);
end

// Export WOZ track/address to C++ for data lookup
// Register track to align with C++ BeforeEval timing.
// Also register stable_side for Verilog controller to match C++ timing.
// Without this registration, Verilog controller sees immediate side changes
// while C++ sees 1-cycle-delayed track values, causing byte stream divergence.
reg [7:0] woz3_track_out_reg;
reg       woz3_stable_side_reg;
always @(posedge clk_sys) begin
    woz3_track_out_reg <= WOZ_TRACK3;
    woz3_stable_side_reg <= WOZ_TRACK3_STABLE_SIDE;
end
assign woz3_track_out = woz3_track_out_reg;
assign woz3_bit_addr_out = WOZ_TRACK3_BIT_ADDR;
assign woz1_track_out = WOZ_TRACK1;
assign woz1_bit_addr_out = WOZ_TRACK1_BIT_ADDR;

wire clk_sys=CLK_14M;
iigs #(.WOZ_BRAM_LATENCY(`WOZ_BRAM_LATENCY)) iigs(
        .reset(reset),
        .cold_reset(cold_reset),
        .CLK_28M(clk_sys),
        .CLK_14M(clk_sys),
        .clk_vid(clk_sys),
        .ce_pix(ce_pix),
        .cpu_wait(cpu_wait_combined),  // Combined HDD and WOZ wait
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
    .FD_DISK_1(fd_disk_1),
    //-- track buffer interface for disk 2
    .TRACK2(TRACK2),
    .TRACK2_ADDR(TRACK2_RAM_ADDR),
    .TRACK2_DO(TRACK2_RAM_DO),
    .TRACK2_DI(TRACK2_RAM_DI),
    .TRACK2_WE(TRACK2_RAM_WE),
    .TRACK2_BUSY(TRACK2_RAM_BUSY),
    .FD_DISK_2(fd_disk_2),
    //-- track buffer interface for 3.5" disk 1 (drive 3)
    .TRACK3(TRACK3),
    .TRACK3_ADDR(TRACK3_RAM_ADDR),
    .TRACK3_SIDE(TRACK3_SIDE),
    .TRACK3_DO(TRACK3_RAM_DO),
    .TRACK3_DI(TRACK3_RAM_DI),
    .TRACK3_WE(TRACK3_RAM_WE),
    .TRACK3_BUSY(TRACK3_RAM_BUSY),
    .FD_DISK_3(FD_DISK_3),
    //-- WOZ bit interfaces for flux-based IWM
    // 3.5" drive 1
    .WOZ_TRACK3(WOZ_TRACK3),
    .WOZ_TRACK3_BIT_ADDR(WOZ_TRACK3_BIT_ADDR),
    .WOZ_TRACK3_STABLE_SIDE(WOZ_TRACK3_STABLE_SIDE),
    .WOZ_TRACK3_BIT_DATA(WOZ_TRACK3_BIT_DATA),
    .WOZ_TRACK3_BIT_COUNT(WOZ_TRACK3_BIT_COUNT),
    .WOZ_TRACK3_LOAD_COMPLETE(woz_ctrl_track_load_complete),
    .WOZ_TRACK3_IS_FLUX(WOZ_TRACK3_IS_FLUX),
    .WOZ_TRACK3_FLUX_SIZE(WOZ_TRACK3_FLUX_SIZE),
    .WOZ_TRACK3_FLUX_TOTAL_TICKS(WOZ_TRACK3_FLUX_TOTAL_TICKS),
    // 5.25" drive 1
    .WOZ_TRACK1(WOZ_TRACK1),
    .WOZ_TRACK1_BIT_ADDR(WOZ_TRACK1_BIT_ADDR),
    .WOZ_TRACK1_BIT_DATA(WOZ_TRACK1_BIT_DATA),
    .WOZ_TRACK1_BIT_COUNT(WOZ_TRACK1_BIT_COUNT),
    // Disk ready to IWM (all 4 drives)
    .DISK_READY(DISK_READY),


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

        // Audio outputs
        .AUDIO_L(AUDIO_L),
        .AUDIO_R(AUDIO_R)
);

  reg prev_fastram_we;
  reg [22:0] prev_fastram_addr;
  always @(posedge clk_sys) begin
    prev_fastram_we <= fastram_we;
    prev_fastram_addr <= fastram_address;
    // Show all transitions involving C010
    if (fastram_ce && (fastram_address == 23'h00c010 || prev_fastram_addr == 23'h00c010)) begin
      $display("FASTRAM C010: addr=%x->%x data_in=%x data_out=%x we=%b->%b ce=%b",
               prev_fastram_addr, fastram_address, fastram_datatoram, fastram_datafromram, prev_fastram_we, fastram_we, fastram_ce);
    end
  end
   //dpram #(.widthad_a(23),.prefix("fast")) fastram
dpram #(.widthad_a(23),.prefix("fast")) fastram
(
        .clock_a(clk_sys),
        .address_a( fastram_address ),
        .data_a(fastram_datatoram),
        .q_a(fastram_datafromram),
        .wren_a(fastram_we & fastram_ce),
        .ce_a(fastram_ce),
        .clock_b(clk_sys),
        .wren_b(1'b0),
        .address_b({23{1'b0}}),
        .data_b(8'h00),
        .q_b()
);



always @(posedge clk_sys) begin
`ifdef DEBUG_SIM
        if (reset) $display("TOPRESET");
`endif
end

`define FASTSIM 1
`ifdef  FASTSIM
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
wire        hdd_unit;           // Which unit (0-1) is being accessed (from bit 7)

// Per-unit mounted and protect status for 2 HDD units
// Using img_mounted indices: [1]=unit0, [3]=unit1
reg  [1:0] hdd_mounted = 2'b0;
wire hdd_read;
wire hdd_write;
reg  [1:0] hdd_protect = 2'b0;
reg  cpu_wait_hdd = 0;

// WOZ floppy cpu_wait - declared later after woz_ctrl_busy/bit_count (see ~line 740)

// HDD unit being served (latched when operation starts)
reg hdd_active_unit = 1'b0;

// Both HDD units share the same sector (routed to their block device indices)
assign sd_lba[1] = {16'b0, hdd_sector};  // Unit 0
assign sd_lba[3] = {16'b0, hdd_sector};  // Unit 1
assign sd_lba[4] = 32'b0;                // Unused
// sd_lba[5] driven by woz_floppy_controller

// Route sd_rd/sd_wr to the correct bit based on active unit
reg  sd_rd_hd;
reg  sd_wr_hd;
assign sd_rd[1] = sd_rd_hd & (hdd_active_unit == 1'b0);
assign sd_rd[3] = sd_rd_hd & (hdd_active_unit == 1'b1);
// sd_rd[4] driven by floppy35_track_1
// sd_rd[5] driven by woz_floppy_controller
assign sd_wr[1] = sd_wr_hd & (hdd_active_unit == 1'b0);
assign sd_wr[3] = sd_wr_hd & (hdd_active_unit == 1'b1);
// sd_wr[4] driven by floppy35_track_1
// sd_wr[5] driven by woz_floppy_controller

// Select the ack for the active unit
wire hdd_ack = (hdd_active_unit == 1'b0) ? sd_ack[1] : sd_ack[3];

// HDD RAM output - shared buffer routed to both HDD unit indices
wire [7:0] hdd_ram_do;
assign sd_buff_din[1] = hdd_ram_do;  // Unit 0
assign sd_buff_din[3] = hdd_ram_do;  // Unit 1
// sd_buff_din[4] driven by floppy35_track_1
// sd_buff_din[5] driven by woz_floppy_controller

`ifdef SIMULATION
// Debug counters to measure how long the CPU is stalled by HDD
reg [31:0] hdd_wait_14m_cycles;
reg [31:0] hdd_wait_events;
`endif

always @(posedge clk_sys) begin
        reg old_ack ;
        reg hdd_read_pending ;
        reg hdd_write_pending ;
        reg state;

        old_ack <= hdd_ack;  // Use the muxed ack for active unit
        hdd_read_pending <= hdd_read_pending | hdd_read;
        hdd_write_pending <= hdd_write_pending | hdd_write;

        // Latch hdd_unit when a new request arrives (before state machine picks it up)
`ifdef SIMULATION
        // Debug: show every time hdd_read or hdd_write pulses
        if (hdd_read | hdd_write) begin
                $display("HDD_SIM: Request pulse! hdd_unit=%0d hdd_read=%b hdd_write=%b state=%b hdd_read_pending=%b hdd_write_pending=%b hdd_active_unit=%0d",
                         hdd_unit, hdd_read, hdd_write, state, hdd_read_pending, hdd_write_pending, hdd_active_unit);
        end
`endif
        if ((hdd_read | hdd_write) & !state & !(hdd_read_pending | hdd_write_pending)) begin
                hdd_active_unit <= hdd_unit;
`ifdef SIMULATION
                $display("HDD_SIM: LATCHING unit: hdd_unit=%0d -> hdd_active_unit", hdd_unit);
`endif
        end

        // Handle HDD unit mounts (2 units mapped to img_mounted indices 1, 3)
        if (img_mounted[1]) begin
                hdd_mounted[0] <= img_size != 0;
                hdd_protect[0] <= img_readonly;
        end
        if (img_mounted[3]) begin
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
`ifdef SIMULATION
                hdd_wait_14m_cycles <= 0;
                hdd_wait_events <= 0;
`endif
        end
        else if(!state) begin
                if (hdd_read_pending | hdd_write_pending) begin
                        state <= 1;
                        sd_rd_hd <= hdd_read_pending;
                        sd_wr_hd <= hdd_write_pending;
                        cpu_wait_hdd <= 1;
`ifdef SIMULATION
                        hdd_wait_events <= hdd_wait_events + 1;
                        $display("HDD: cpu_wait asserted (read=%0d write=%0d) events=%0d t=%0t", hdd_read_pending, hdd_write_pending, hdd_wait_events+1, $time);
`endif
                end
        end
        else begin
                if (~old_ack & hdd_ack) begin
                        sd_rd_hd <= 0;
                        sd_wr_hd <= 0;
`ifdef SIMULATION
                        $display("HDD: DMA ack rising (~old_ack -> ack) unit=%0d at t=%0t", hdd_active_unit, $time);
`endif
                end
                else if(old_ack & ~hdd_ack) begin
`ifdef SIMULATION
                        $display("HDD: DMA ack falling (transfer complete) unit=%0d at t=%0t", hdd_active_unit, $time);
`endif
                        state <= 0;
                        cpu_wait_hdd <= 0;
                        hdd_read_pending <= 0;
                        hdd_write_pending <= 0;
`ifdef SIMULATION
                        $display("HDD: cpu_wait deasserted; stalled cycles=%0d", hdd_wait_14m_cycles);
                        hdd_wait_14m_cycles <= 0;
`endif
                end
        end
`ifdef SIMULATION
        // Accumulate 14M cycles while CPU is waiting on HDD
        if (cpu_wait_hdd) hdd_wait_14m_cycles <= hdd_wait_14m_cycles + 1;
`endif
end


wire fd_disk_1;
wire fd_disk_2;
// FD_DISK_3 comes from iigs module for 3.5" drive 1

wire [3:0] DISK_READY_internal;  // From floppy_track modules
reg  [3:0] DISK_CHANGE;
reg  [3:0] disk_mount;
reg        img_mounted0_d, img_mounted2_d, img_mounted4_d;

// Combined DISK_READY: use WOZ ready if WOZ is mounted, else use track module ready
wire [3:0] DISK_READY;
assign DISK_READY[0] = woz1_ready | DISK_READY_internal[0];  // 5.25" drive 1
assign DISK_READY[1] = DISK_READY_internal[1];               // 5.25" drive 2
// DISK_READY[2] indicates disk presence for motor control and flux_drive.
// Track data availability is checked separately via WOZ_TRACK3_BIT_COUNT > 0.
// Using woz_ctrl_disk_mounted (not woz_ctrl_ready) prevents motor/spinup reset
// when the track loader briefly goes non-IDLE during track changes.
assign DISK_READY[2] = woz_ctrl_disk_mounted | DISK_READY_internal[2];
assign DISK_READY[3] = DISK_READY_internal[3];               // 3.5" drive 2




always @(posedge clk_sys) begin
        // Latch previous mount flags to detect rising edges
        img_mounted0_d <= img_mounted[0];
        img_mounted2_d <= img_mounted[2];
        img_mounted4_d <= img_mounted[4];

        // Index 0: 5.25" drive 1
        // Only toggle change on rising edge to avoid continuous bouncing
        if (~img_mounted0_d & img_mounted[0]) begin
                disk_mount[0]   <= (img_size != 0);
                DISK_CHANGE[0]  <= ~DISK_CHANGE[0];
`ifdef SIMULATION
                $display("FLOPPY: mount event drive0 (size=%0d)", img_size);
`endif
        end
        // Index 2: 5.25" drive 2
        if (~img_mounted2_d & img_mounted[2]) begin
                disk_mount[1]   <= (img_size != 0);
                DISK_CHANGE[1]  <= ~DISK_CHANGE[1];
`ifdef SIMULATION
                $display("FLOPPY: mount event drive1 (size=%0d)", img_size);
`endif
        end
        // Index 4: 3.5" drive 1 (drive 3 in IWM terms)
        if (~img_mounted4_d & img_mounted[4]) begin
                disk_mount[2]   <= (img_size != 0);
                DISK_CHANGE[2]  <= ~DISK_CHANGE[2];
`ifdef SIMULATION
                $display("FLOPPY35: mount event drive2/3.5\" drive1 (size=%0d)", img_size);
`endif
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
   .mount (disk_mount[0]),   // Use disk_mount (persists) not img_mounted (gets cleared)
   .ready  (DISK_READY_internal[0]),
   .active (fd_disk_1),

   .sd_buff_addr (sd_buff_addr),
   .sd_buff_dout (sd_buff_dout),
   .sd_buff_din  (sd_buff_din[0]),
   .sd_buff_wr   (sd_buff_wr),

   .sd_lba       (sd_lba[0] ),
   .sd_rd        (sd_rd[0]),
   .sd_wr       ( sd_wr[0]),
   .sd_ack       (sd_ack[0])
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
   .ready  (DISK_READY_internal[1]),
   .active (fd_disk_2),

   .sd_buff_addr (sd_buff_addr),
   .sd_buff_dout (sd_buff_dout),
   .sd_buff_din  (sd_buff_din[2]),
   .sd_buff_wr   (sd_buff_wr),

   .sd_lba       (sd_lba[2] ),
   .sd_rd        (sd_rd[2]),
   .sd_wr       ( sd_wr[2]),
   .sd_ack       (sd_ack[2])
);

// 3.5" floppy drive 1 (drive 3 in IWM terms)
floppy35_track floppy35_track_1
(
   .clk(clk_sys),
   .reset(reset),

   .ram_addr(TRACK3_RAM_ADDR),
   .ram_di(TRACK3_RAM_DI),
   .ram_do(TRACK3_RAM_DO),
   .ram_we(TRACK3_RAM_WE),

   .track (TRACK3),
   .side  (TRACK3_SIDE),
   .busy  (TRACK3_RAM_BUSY),
   .change(DISK_CHANGE[2]),
   .mount (disk_mount[2]),
   .ready (DISK_READY_internal[2]),
   .active(FD_DISK_3),

   .sd_buff_addr (sd_buff_addr),
   .sd_buff_dout (sd_buff_dout),
   .sd_buff_din  (sd_buff_din[4]),
   .sd_buff_wr   (sd_buff_wr),

   .sd_lba       (sd_lba[4]),
   .sd_rd        (sd_rd[4]),
   .sd_wr        (sd_wr[4]),
   .sd_ack       (sd_ack[4])
);

//=============================================================================
// WOZ Floppy Controller (Verilog implementation for validation)
// This controller parses raw WOZ files via SD block device and provides
// bitstream data. Used to validate against the C++ implementation.
//=============================================================================

// Verilog WOZ controller outputs (for comparison with C++ implementation)
wire        woz_ctrl_ready;
wire        woz_ctrl_disk_mounted;
wire        woz_ctrl_busy;
wire [31:0] woz_ctrl_bit_count;
wire [7:0]  woz_ctrl_bit_data;
wire        woz_ctrl_track_load_complete;  // Pulses when track load finishes
wire [31:0] woz_ctrl_flux_total_ticks;

// Mount detection for WOZ controller (index 5)
reg         img_mounted5_d = 0;
reg         woz_ctrl_mount = 0;
reg         woz_ctrl_change = 0;

always @(posedge clk_sys) begin
    img_mounted5_d <= img_mounted[5];
    // Detect rising edge of img_mounted[5]
    if (~img_mounted5_d & img_mounted[5]) begin
        woz_ctrl_mount  <= (img_size != 0);
        woz_ctrl_change <= ~woz_ctrl_change;
`ifdef SIMULATION
        $display("WOZ_CTRL: Mount detected for index 5 (size=%0d)", img_size);
`endif
    end
end

woz_floppy_controller #(
    .IS_35_INCH(1),
    .BRAM_LATENCY(`WOZ_BRAM_LATENCY)
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
    .active(FD_DISK_3),

    // Bitstream Interface - use same bit_addr as C++ path
    // Use REGISTERED stable_side to match C++ timing.
    // When side changes, the BRAM mux must switch in sync with the BRAM data update.
    // Using immediate stable_side causes a 1-cycle glitch where stale data is returned.
    .bit_count(woz_ctrl_bit_count),
    .bit_addr(WOZ_TRACK3_BIT_ADDR),
    .stable_side(woz3_stable_side_reg),
    .bit_data(woz_ctrl_bit_data),
    .bit_data_in(8'h00),
    .bit_we(1'b0),

    // Track load notification (for flux_drive to reset bit_position)
    .track_load_complete(woz_ctrl_track_load_complete),

    // FLUX track support (WOZ v3)
    .is_flux_track(WOZ_TRACK3_IS_FLUX),
    .flux_data_size(WOZ_TRACK3_FLUX_SIZE),
    .flux_total_ticks(woz_ctrl_flux_total_ticks)
);

// WOZ floppy cpu_wait: DISABLED - caused boot to be too slow
// The cpu_wait approach doesn't work because it pauses during every track seek,
// not just when data is actually needed. Better to let the ROM run and accept
// that some reads during track loading may return zeros (which the ROM handles).
wire cpu_wait_woz = 1'b0;  // Disabled
wire cpu_wait_combined = cpu_wait_hdd | cpu_wait_woz;

//=============================================================================
// WOZ Controller Validation - Compare C++ vs Verilog outputs
//=============================================================================
`ifdef SIMULATION
reg [13:0] woz_cmp_last_addr;
reg [13:0] woz_cmp_last_addr_d;  // Delayed by 1 cycle for BRAM latency
reg [13:0] woz_cmp_last_addr_d2; // Delayed by 2 cycles for display
reg [31:0] woz_cmp_mismatch_count;
reg [31:0] woz_cmp_match_count;
reg        woz_cmp_enabled;
reg        woz_cmp_addr_changed;   // Stage 1: address changed this cycle
reg        woz_cmp_addr_changed_d; // Stage 2: delayed by 1 cycle (C++ data now valid)
reg [7:0]  woz_cmp_cpp_data_d;     // C++ data captured when C++ has updated for new addr
reg [31:0] woz_cmp_frame;          // Frame counter (VGA_VS rising edges)
reg        woz_cmp_vsync_d;
reg [31:0] woz_cmp_addr_mismatch_count;
reg [31:0] woz_cmp_bitpos_mismatch_count;
reg [31:0] woz_cmp_track_mismatch_count;
reg [31:0] woz_cmp_trackloaded_mismatch_count;
reg [31:0] woz_cmp_motor_mismatch_count;
reg [31:0] woz_cmp_motorcmd_mismatch_count;
reg [31:0] iwm_data_read_log_count;
localparam [31:0] IWM_DATA_READ_LOG_START_FRAME = 150;
localparam [31:0] IWM_DATA_READ_LOG_END_FRAME = 400;
localparam [31:0] IWM_DATA_READ_LOG_MAX = 200000;

initial begin
    woz_cmp_last_addr = 14'h3FFF;
    woz_cmp_last_addr_d = 14'h3FFF;
    woz_cmp_last_addr_d2 = 14'h3FFF;
    woz_cmp_mismatch_count = 0;
    woz_cmp_match_count = 0;
    woz_cmp_enabled = 0;
    woz_cmp_addr_changed = 0;
    woz_cmp_addr_changed_d = 0;
    woz_cmp_cpp_data_d = 8'hFF;
    woz_cmp_frame = 0;
    woz_cmp_vsync_d = 0;
    woz_cmp_addr_mismatch_count = 0;
    woz_cmp_bitpos_mismatch_count = 0;
    woz_cmp_track_mismatch_count = 0;
    woz_cmp_trackloaded_mismatch_count = 0;
    woz_cmp_motor_mismatch_count = 0;
    woz_cmp_motorcmd_mismatch_count = 0;
    iwm_data_read_log_count = 0;
end

reg [7:0] woz_cmp_last_track = 8'hFF;
reg [3:0] woz_cmp_track_stable_count = 4'd0;
wire woz_cmp_track_stable = (woz_cmp_track_stable_count >= 4'd3);

// Hierarchical taps for flux-drive internals (simulation-only)
wire [13:0] sim_drive35_bram_addr = emu.iigs.iwmc.drive35.BRAM_ADDR;
wire [16:0] sim_drive35_bit_position = emu.iigs.iwmc.drive35.BIT_POSITION;
wire [6:0]  sim_drive35_track = emu.iigs.iwmc.drive35_track;
wire        sim_drive35_track_loaded = emu.iigs.iwmc.drive35_track_loaded;
wire        sim_drive35_motor_spinning = emu.iigs.iwmc.drive35_motor_spinning;
wire        sim_drive35_motor_on = emu.iigs.iwmc.drive35_motor_on;
wire        sim_drive35_sony_motor_on = emu.iigs.iwmc.drive35.sony_motor_on;
wire [3:0]  sim_iwm_bus_addr = emu.iigs.iwmc.bus_addr;
wire        sim_iwm_bus_rd = emu.iigs.iwmc.bus_rd;
wire [7:0]  sim_iwm_data_out = emu.iigs.iwmc.iwm_data_out;
wire        sim_iwm_q6 = emu.iigs.iwmc.q6;
wire        sim_iwm_q7 = emu.iigs.iwmc.q7;
wire        sim_iwm_q7_for_flux = emu.iigs.iwmc.q7_for_flux;
wire        sim_iwm_smartport_mode = emu.iigs.iwmc.smartport_mode;
wire        sim_iwm_force_q7_data_read = emu.iigs.iwmc.force_q7_data_read;
wire [16:0] sim_iwm_bit_position = emu.iigs.iwmc.current_bit_position;
wire [13:0] sim_iwm_bram_addr = emu.iigs.iwmc.drive35_bram_addr;
wire [6:0]  sim_iwm_track = emu.iigs.iwmc.drive35_track;
wire        sim_iwm_motor_spinning = emu.iigs.iwmc.drive35_motor_spinning;
wire        sim_iwm_sony_motor_on = emu.iigs.iwmc.drive35.sony_motor_on;
wire [3:0]  sim_woz_state = emu.woz_ctrl.state;
wire [7:0]  sim_woz_pending_track = emu.woz_ctrl.pending_track_id;
wire [7:0]  sim_woz_track_s0 = emu.woz_ctrl.current_track_id_side0;
wire [7:0]  sim_woz_track_s1 = emu.woz_ctrl.current_track_id_side1;
wire [31:0] sim_woz_bit_count_s0 = emu.woz_ctrl.bit_count_side0;
wire [31:0] sim_woz_bit_count_s1 = emu.woz_ctrl.bit_count_side1;
wire [31:0] sim_woz_trk_bit_count = emu.woz_ctrl.trk_bit_count;
wire        sim_woz_loading_second = emu.woz_ctrl.loading_second_side;
wire        sim_woz_valid = emu.woz_ctrl.woz_valid;
wire        sim_woz_busy = emu.woz_ctrl.busy;
wire        sim_woz_sd_rd = emu.woz_ctrl.sd_rd;
wire        sim_woz_sd_ack = emu.woz_ctrl.sd_ack;

always @(posedge clk_sys) begin
    woz_cmp_vsync_d <= VGA_VS;
    if (!woz_cmp_vsync_d && VGA_VS) begin
        woz_cmp_frame <= woz_cmp_frame + 1;
    end

    // Enable comparison once both controllers are ready
    if (woz3_ready && woz_ctrl_ready && woz_ctrl_disk_mounted) begin
        woz_cmp_enabled <= 1;
    end

    // Track stability counter: count cycles since track_id last changed
    if (WOZ_TRACK3 != woz_cmp_last_track) begin
        woz_cmp_last_track <= WOZ_TRACK3;
        woz_cmp_track_stable_count <= 4'd0;
    end else if (woz_cmp_track_stable_count < 4'd15) begin
        woz_cmp_track_stable_count <= woz_cmp_track_stable_count + 1'd1;
    end

    // Stage 1: Detect address change
    woz_cmp_addr_changed <= 0;
    if (woz_cmp_enabled && WOZ_TRACK3_BIT_ADDR != woz_cmp_last_addr) begin
        woz_cmp_last_addr <= WOZ_TRACK3_BIT_ADDR;
        woz_cmp_addr_changed <= 1;
    end

    // Stage 2: One cycle later, C++ BeforeEval has run with new address
    // Now capture C++ data (which is correct for the new address)
    woz_cmp_addr_changed_d <= woz_cmp_addr_changed;
    if (woz_cmp_addr_changed) begin
        woz_cmp_cpp_data_d <= woz3_bit_data;  // Capture C++ data (now valid for new addr)
    end

    // Delay the address for display purposes (2 cycles total)
    woz_cmp_last_addr_d <= woz_cmp_last_addr;
    woz_cmp_last_addr_d2 <= woz_cmp_last_addr_d;

    // Stage 3: Compare on cycle after C++ data capture (when BRAM data is also valid)
    // Skip comparison while Verilog controller is loading a track (busy)
    // Also skip if track_id recently changed (to avoid glitches during track switches)
    if (woz_cmp_addr_changed_d && !woz_ctrl_busy && woz_cmp_track_stable) begin
        // Compare bit_data (now both should be for the same address)
        if (woz_cmp_cpp_data_d != woz_ctrl_bit_data) begin
            woz_cmp_mismatch_count <= woz_cmp_mismatch_count + 1;
            if (woz_cmp_mismatch_count < 100) begin
                $display("WOZ_CMP MISMATCH #%0d: frame=%0d track=%0d addr=%0d C++=%02X Verilog=%02X (C++ bit_count=%0d V bit_count=%0d stable_side=%0d)",
                         woz_cmp_mismatch_count + 1, woz_cmp_frame, WOZ_TRACK3, woz_cmp_last_addr_d2,
                         woz_cmp_cpp_data_d, woz_ctrl_bit_data,
                         woz3_bit_count, woz_ctrl_bit_count, WOZ_TRACK3_STABLE_SIDE);
            end
        end else begin
            woz_cmp_match_count <= woz_cmp_match_count + 1;
            // Log every 16384 matches to show progress
            if (woz_cmp_match_count[13:0] == 14'h0000 && woz_cmp_match_count > 0) begin
                $display("WOZ_CMP: %0d matches so far, %0d mismatches",
                         woz_cmp_match_count, woz_cmp_mismatch_count);
            end
        end

        // Compare bit_count
        if (woz3_bit_count != woz_ctrl_bit_count && woz_cmp_mismatch_count < 10) begin
            $display("WOZ_CMP BIT_COUNT MISMATCH: track=%0d C++=%0d Verilog=%0d",
                     WOZ_TRACK3, woz3_bit_count, woz_ctrl_bit_count);
        end
    end

    // Additional signal comparisons (log first 100 mismatches per category)
    if (woz_cmp_enabled && woz_cmp_track_stable) begin
        // BRAM address should match WOZ bit addr or be one byte ahead (prefetch)
        if ((sim_drive35_bram_addr != WOZ_TRACK3_BIT_ADDR) &&
            (sim_drive35_bram_addr != (WOZ_TRACK3_BIT_ADDR + 14'd1))) begin
            if (woz_cmp_addr_mismatch_count < 100) begin
                $display("WOZ_CMP ADDR MISMATCH #%0d: frame=%0d bram_addr=%0d woz_addr=%0d",
                         woz_cmp_addr_mismatch_count + 1, woz_cmp_frame,
                         sim_drive35_bram_addr, WOZ_TRACK3_BIT_ADDR);
            end
            woz_cmp_addr_mismatch_count <= woz_cmp_addr_mismatch_count + 1;
        end

        // Bit position should align with BRAM addr (same byte or one behind)
        if ((sim_drive35_bram_addr != sim_drive35_bit_position[16:3]) &&
            (sim_drive35_bram_addr != (sim_drive35_bit_position[16:3] + 14'd1))) begin
            if (woz_cmp_bitpos_mismatch_count < 100) begin
                $display("WOZ_CMP BITPOS MISMATCH #%0d: frame=%0d bit_pos=%0d bram_addr=%0d",
                         woz_cmp_bitpos_mismatch_count + 1, woz_cmp_frame,
                         sim_drive35_bit_position, sim_drive35_bram_addr);
            end
            woz_cmp_bitpos_mismatch_count <= woz_cmp_bitpos_mismatch_count + 1;
        end

        // Track number should match WOZ_TRACK3 upper bits (side in bit 0)
        if (sim_drive35_track != WOZ_TRACK3[7:1]) begin
            if (woz_cmp_track_mismatch_count < 100) begin
                $display("WOZ_CMP TRACK MISMATCH #%0d: frame=%0d drive35_track=%0d woz_track3=%0d",
                         woz_cmp_track_mismatch_count + 1, woz_cmp_frame,
                         sim_drive35_track, WOZ_TRACK3);
            end
            woz_cmp_track_mismatch_count <= woz_cmp_track_mismatch_count + 1;
        end

        // Track loaded should match ready+bit_count gate
        if (sim_drive35_track_loaded != (DISK_READY[2] && (WOZ_TRACK3_BIT_COUNT > 0))) begin
            if (woz_cmp_trackloaded_mismatch_count < 100) begin
                $display("WOZ_CMP TRACK_LOADED MISMATCH #%0d: frame=%0d track_loaded=%0d ready=%0d bit_count=%0d",
                         woz_cmp_trackloaded_mismatch_count + 1, woz_cmp_frame,
                         sim_drive35_track_loaded, DISK_READY[2], WOZ_TRACK3_BIT_COUNT);
            end
            woz_cmp_trackloaded_mismatch_count <= woz_cmp_trackloaded_mismatch_count + 1;
        end

        // Motor spinning should track the Sony motor command for 3.5" drives
        if (sim_drive35_motor_spinning != sim_drive35_sony_motor_on) begin
            if (woz_cmp_motor_mismatch_count < 100) begin
                $display("WOZ_CMP MOTOR MISMATCH #%0d: frame=%0d motor_spinning=%0d sony_motor_on=%0d",
                         woz_cmp_motor_mismatch_count + 1, woz_cmp_frame,
                         sim_drive35_motor_spinning, sim_drive35_sony_motor_on);
            end
            woz_cmp_motor_mismatch_count <= woz_cmp_motor_mismatch_count + 1;
        end

        // Log when the IWM motor command disagrees with the Sony motor command
        if (sim_drive35_motor_on != sim_drive35_sony_motor_on) begin
            if (woz_cmp_motorcmd_mismatch_count < 100) begin
                $display("WOZ_CMP MOTOR_CMD MISMATCH #%0d: frame=%0d motor_on=%0d sony_motor_on=%0d",
                         woz_cmp_motorcmd_mismatch_count + 1, woz_cmp_frame,
                         sim_drive35_motor_on, sim_drive35_sony_motor_on);
            end
            woz_cmp_motorcmd_mismatch_count <= woz_cmp_motorcmd_mismatch_count + 1;
        end
    end

    // Log IWM data register reads (C0EC) with key timing/flux context
    if (sim_iwm_bus_rd && (sim_iwm_bus_addr == 4'hC) &&
        (woz_cmp_frame >= IWM_DATA_READ_LOG_START_FRAME) &&
        (woz_cmp_frame <= IWM_DATA_READ_LOG_END_FRAME)) begin
        if (iwm_data_read_log_count < IWM_DATA_READ_LOG_MAX) begin
            $display("IWM_DATA_READ #%0d: frame=%0d addr=%01h dout=%02h q6=%0d q7=%0d q7_for_flux=%0d force_q7=%0d smartport=%0d drive_on=%0d motor_spin=%0d sony_motor=%0d bit_pos=%0d bram_addr=%0d track=%0d bit_count=%0d woz_state=%0d woz_pending=%0d woz_s0=%0d woz_s1=%0d bc_s0=%0d bc_s1=%0d trk_bc=%0d woz_valid=%0d woz_busy=%0d sd_rd=%0d sd_ack=%0d load2=%0d",
                     iwm_data_read_log_count + 1, woz_cmp_frame, sim_iwm_bus_addr, sim_iwm_data_out,
                     sim_iwm_q6, sim_iwm_q7, sim_iwm_q7_for_flux, sim_iwm_force_q7_data_read,
                     sim_iwm_smartport_mode, sim_drive35_motor_on, sim_iwm_motor_spinning,
                     sim_iwm_sony_motor_on, sim_iwm_bit_position, sim_iwm_bram_addr,
                     sim_iwm_track, WOZ_TRACK3_BIT_COUNT, sim_woz_state, sim_woz_pending_track,
                     sim_woz_track_s0, sim_woz_track_s1, sim_woz_bit_count_s0, sim_woz_bit_count_s1,
                     sim_woz_trk_bit_count, sim_woz_valid, sim_woz_busy, sim_woz_sd_rd, sim_woz_sd_ack,
                     sim_woz_loading_second);
        end
        iwm_data_read_log_count <= iwm_data_read_log_count + 1;
    end

    // Log ready state changes
    if (woz_ctrl_ready && !woz_cmp_enabled) begin
        $display("WOZ_CMP: Verilog controller ready, waiting for C++ ready signal");
    end
end
`endif

endmodule
