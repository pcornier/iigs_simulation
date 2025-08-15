`timescale 1ns / 1ps
/*============================================================================
===========================================================================*/

module emu (

        input CLK_14M,
        input reset,
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
        input [32:0] timestamp,

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

        output [31:0]           sd_lba[3],
        output [9:0]            sd_rd,
        output [9:0]            sd_wr,
        input [9:0]             sd_ack,
        input [8:0]             sd_buff_addr,
        input [7:0]             sd_buff_dout,
        output [7:0]            sd_buff_din[3],
        input                   sd_buff_wr,
        input [9:0]             img_mounted,
        input                   img_readonly,

        input [63:0]            img_size



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



wire clk_sys=CLK_14M;
iigs  iigs(
        .reset(reset),
        .CLK_14M(clk_sys),
        .clk_vid(clk_sys),
        .ce_pix(ce_pix),
        .cpu_wait(cpu_wait_hdd),
        .timestamp({33{1'b0}}),  // Add missing timestamp connection
        .floppy_wp(1'b1),  // Add missing floppy_wp
        .R(VGA_R),
        .G(VGA_G),
        .B(VGA_B),
        .HBlank(hblank),
        .VBlank(vblank),
        .HS(hsync),
        .VS(vsync),
        /* hard drive */
        .HDD_SECTOR(hdd_sector),
        .HDD_READ(hdd_read),
        .HDD_WRITE(hdd_write),
        .HDD_MOUNTED(hdd_mounted),
        .HDD_PROTECT(hdd_protect),
        .HDD_RAM_ADDR(sd_buff_addr),
        .HDD_RAM_DI(sd_buff_dout),
        .HDD_RAM_DO(sd_buff_din[1]),
        .HDD_RAM_WE(sd_buff_wr & sd_ack[1]),

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
        .joystick_1(joystick_1),
        .joystick_l_analog_0(joystick_l_analog_0),
        .joystick_l_analog_1(joystick_l_analog_1),
        .paddle_0(paddle_0),
        .paddle_1(paddle_1),
        .paddle_2(paddle_2),
        .paddle_3(paddle_3)
);

/*
  always @(posedge clk_sys) begin
    if (fastram_ce) begin
      if (fastram_we) $display("Writing %x: %x\n", fastram_address, fastram_datatoram);
      $display("Reading %x: %x\n", fastram_address, fastram_datafromram);
    end
  end
*/
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
        if (reset) $display("TOPRESET");
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


// HARD DRIVE PARTS
wire [15:0] hdd_sector;

assign sd_lba[1] = {16'b0,hdd_sector};
// NOTE: Don't override the full sd_rd/sd_wr bus here; floppy tracks drive bits 0/2.
// The legacy HDD mux on bit 2 conflicts with floppy 2 and was forcing bit 0 low.
// For floppy bring-up, leave the bus driven solely by the emu/floppy_track instances.
//assign sd_rd = { 7'b0, 1'b0,sd_rd_hd,1'b0};
//assign sd_wr = { 7'b0, 1'b0,sd_wr_hd,1'b0};
assign sd_rd[1]=sd_rd_hd;
assign sd_wr[1]=sd_wr_hd;

reg  hdd_mounted = 0;
wire hdd_read;
wire hdd_write;
reg  hdd_protect;
reg  cpu_wait_hdd = 0;
`ifdef SIMULATION
// Debug counters to measure how long the CPU is stalled by HDD
reg [31:0] hdd_wait_14m_cycles;
reg [31:0] hdd_wait_events;
`endif

reg  sd_rd_hd;
reg  sd_wr_hd;

always @(posedge clk_sys) begin
        reg old_ack ;
        reg hdd_read_pending ;
        reg hdd_write_pending ;
        reg state;

        old_ack <= sd_ack[1];
        hdd_read_pending <= hdd_read_pending | hdd_read;
        hdd_write_pending <= hdd_write_pending | hdd_write;

        if (img_mounted[1]) begin
                hdd_mounted <= img_size != 0;
                hdd_protect <= img_readonly;
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
                if (~old_ack & sd_ack[1]) begin
                        hdd_read_pending <= 0;
                        hdd_write_pending <= 0;
                        sd_rd_hd <= 0;
                        sd_wr_hd <= 0;
`ifdef SIMULATION
                        $display("HDD: DMA ack rising (~old_ack -> ack) at t=%0t", $time);
`endif
                end
                else if(old_ack & ~sd_ack[1]) begin
`ifdef SIMULATION
                        $display("HDD: DMA ack falling (transfer complete) at t=%0t", $time);
`endif
                        state <= 0;
                        cpu_wait_hdd <= 0;
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
   .mount (img_mounted[0]),
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




endmodule
