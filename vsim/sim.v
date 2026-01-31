// Define DEBUG_SIM to enable verbose simulation debug output
// `define DEBUG_SIM

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
        output [15:0]           woz3_bit_addr_out,
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

wire UART_RTS;
wire UART_TXD;
// UART inputs: RXD idle (mark=1), CTS asserted (clear to send=0)
wire UART_RXD = 1'b1;
wire UART_CTS = 1'b0;
    wire [22:0] fastram_address;
    wire [7:0] fastram_datatoram;
    wire [7:0] fastram_datafromram;
    wire fastram_we;
    wire fastram_ce;

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

// WOZ bit interfaces for flux-based IWM
// 3.5" drive 1 WOZ bit interface
wire [7:0]  WOZ_TRACK3;           // Track number being read
wire [15:0] WOZ_TRACK3_BIT_ADDR;  // Byte address in track bit buffer (16-bit for FLUX)
wire        WOZ_TRACK3_STABLE_SIDE; // Stable side for data reads (captured when motor starts)
wire [7:0]  WOZ_TRACK3_BIT_DATA;  // Byte from track bit buffer
wire [31:0] WOZ_TRACK3_BIT_COUNT; // Total bits in track
wire        WOZ_TRACK3_READY;     // Track data valid for current WOZ_TRACK3
wire        WOZ_TRACK3_IS_FLUX;   // Track data is flux timing (not bitstream)
wire [31:0] WOZ_TRACK3_FLUX_SIZE; // Size in bytes of flux data (when IS_FLUX)
wire [31:0] WOZ_TRACK3_FLUX_TOTAL_TICKS; // Sum of FLUX bytes for timing normalization
wire        woz_ctrl_ready;

// 5.25" drive 1 WOZ bit interface
wire [5:0]  WOZ_TRACK1;           // Track number being read
wire [12:0] WOZ_TRACK1_BIT_ADDR;  // Byte address in track bit buffer
wire [7:0]  WOZ_TRACK1_BIT_DATA;  // Byte from track bit buffer
wire [31:0] WOZ_TRACK1_BIT_COUNT; // Total bits in track

// WOZ data assignments - connect to C++ interface
assign WOZ_TRACK1_BIT_DATA = woz1_bit_data;
assign WOZ_TRACK1_BIT_COUNT = woz1_bit_count;

// WOZ track/address outputs to C++ for data lookup
assign woz3_track_out = WOZ_TRACK3;
assign woz3_bit_addr_out = WOZ_TRACK3_BIT_ADDR;
assign woz1_track_out = WOZ_TRACK1;
assign woz1_bit_addr_out = WOZ_TRACK1_BIT_ADDR;

// Register stable_side to match BRAM timing - prevents 1-cycle glitches on side change
reg woz3_stable_side_reg;
always @(posedge CLK_14M) begin
    woz3_stable_side_reg <= WOZ_TRACK3_STABLE_SIDE;
end

wire clk_sys=CLK_14M;
iigs  iigs(
        .reset(reset),
        .cold_reset(cold_reset),
        .CLK_28M(clk_sys),
        .CLK_14M(clk_sys),
        .clk_vid(clk_sys),
        .ce_pix(ce_pix),
        .cpu_wait(cpu_wait_hdd),
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
    // Disk ready to IWM (pad to 4 bits)
    .DISK_READY({1'b0, woz_ctrl_disk_mounted, DISK_READY}),

    .WOZ_TRACK3(WOZ_TRACK3),
    .WOZ_TRACK3_BIT_ADDR(WOZ_TRACK3_BIT_ADDR),
    .WOZ_TRACK3_STABLE_SIDE(WOZ_TRACK3_STABLE_SIDE),
    .WOZ_TRACK3_BIT_DATA(WOZ_TRACK3_BIT_DATA),
    .WOZ_TRACK3_BIT_COUNT(WOZ_TRACK3_BIT_COUNT),
    .WOZ_TRACK3_READY(WOZ_TRACK3_READY),
    .WOZ_TRACK3_LOAD_COMPLETE(woz_ctrl_track_load_complete),
    .WOZ_TRACK3_IS_FLUX(WOZ_TRACK3_IS_FLUX),
    .WOZ_TRACK3_FLUX_SIZE(WOZ_TRACK3_FLUX_SIZE),
    .WOZ_TRACK3_FLUX_TOTAL_TICKS(WOZ_TRACK3_FLUX_TOTAL_TICKS),

    // WOZ bit interface for 5.25" drive 1
    .WOZ_TRACK1(WOZ_TRACK1),
    .WOZ_TRACK1_BIT_ADDR(WOZ_TRACK1_BIT_ADDR),
    .WOZ_TRACK1_BIT_DATA(WOZ_TRACK1_BIT_DATA),
    .WOZ_TRACK1_BIT_COUNT(WOZ_TRACK1_BIT_COUNT),

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
        .AUDIO_R(AUDIO_R),

        // Serial (SCC Channel A = Modem port)
        .UART_TXD(UART_TXD),
        .UART_RXD(UART_RXD),
        .UART_RTS(UART_RTS),
        .UART_CTS(UART_CTS)
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

// HDD unit being served (latched when operation starts)
reg hdd_active_unit = 1'b0;

// Both HDD units share the same sector (routed to their block device indices)
assign sd_lba[1] = {16'b0, hdd_sector};  // Unit 0
assign sd_lba[3] = {16'b0, hdd_sector};  // Unit 1
assign sd_lba[4] = 32'b0;                // Unused
assign sd_lba[5] = 32'b0;                // Unused

// Route sd_rd/sd_wr to the correct bit based on active unit
reg  sd_rd_hd;
reg  sd_wr_hd;
assign sd_rd[1] = sd_rd_hd & (hdd_active_unit == 1'b0);
assign sd_rd[3] = sd_rd_hd & (hdd_active_unit == 1'b1);
assign sd_rd[4] = 1'b0;  // Unused
assign sd_rd[5] = 1'b0;  // Unused
assign sd_wr[1] = sd_wr_hd & (hdd_active_unit == 1'b0);
assign sd_wr[3] = sd_wr_hd & (hdd_active_unit == 1'b1);
assign sd_wr[4] = 1'b0;  // Unused
assign sd_wr[5] = 1'b0;  // Unused

// Select the ack for the active unit
wire hdd_ack = (hdd_active_unit == 1'b0) ? sd_ack[1] : sd_ack[3];

// HDD RAM output - shared buffer routed to both HDD unit indices
wire [7:0] hdd_ram_do;
assign sd_buff_din[1] = hdd_ram_do;  // Unit 0
assign sd_buff_din[3] = hdd_ram_do;  // Unit 1
assign sd_buff_din[4] = 8'h00;       // Unused
assign sd_buff_din[5] = 8'h00;       // Unused

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

wire [1:0] DISK_READY;
reg  [1:0] DISK_CHANGE;
reg  [1:0] disk_mount;
reg        img_mounted0_d, img_mounted2_d;




always @(posedge clk_sys) begin
        // Latch previous mount flags to detect rising edges
        img_mounted0_d <= img_mounted[0];
        img_mounted2_d <= img_mounted[2];

        // Only toggle change on rising edge to avoid continuous bouncing
        if (~img_mounted0_d & img_mounted[0]) begin
                disk_mount[0]   <= (img_size != 0);
                DISK_CHANGE[0]  <= ~DISK_CHANGE[0];
`ifdef SIMULATION
                $display("FLOPPY: mount event drive0 (size=%0d)", img_size);
`endif
        end
        if (~img_mounted2_d & img_mounted[2]) begin
                disk_mount[1]   <= (img_size != 0);
                DISK_CHANGE[1]  <= ~DISK_CHANGE[1];
`ifdef SIMULATION
                $display("FLOPPY: mount event drive1 (size=%0d)", img_size);
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
   .ready  (DISK_READY[0]),
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
   .ready  (DISK_READY[1]),
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


// Verilog WOZ controller outputs (for comparison with C++ implementation)
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

// Connect WOZ controller outputs to IIgs inputs
assign WOZ_TRACK3_BIT_DATA = woz_ctrl_bit_data;
assign WOZ_TRACK3_BIT_COUNT = woz_ctrl_bit_count;
assign WOZ_TRACK3_READY = woz_ctrl_ready;
assign WOZ_TRACK3_FLUX_TOTAL_TICKS = woz_ctrl_flux_total_ticks;


endmodule
