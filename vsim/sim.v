`timescale 1ns / 1ps
/*============================================================================
===========================================================================*/

module emu (

	input clk_sys,
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

	output [31:0] 		sd_lba[3],
	output [9:0] 		sd_rd,
	output [9:0] 		sd_wr,
	input [9:0] 		sd_ack,
	input [8:0] 		sd_buff_addr,
	input [7:0] 		sd_buff_dout,
	output [7:0] 		sd_buff_din[3],
	input 			sd_buff_wr,
	input [9:0] 		img_mounted,
	input 			img_readonly,

	input [63:0] 		img_size



);
wire [15:0] joystick_a0 =  joystick_l_analog_0;

wire UART_CTS;
wire UART_RTS;
wire UART_RXD;
wire UART_TXD;
wire UART_DTR;
wire UART_DSR;


top top (
	.reset(reset),
	.clk_sys(clk_sys),
	.clk_vid(clk_sys),
	.ce_pix(ce_pix),
	.cpu_wait(cpu_wait_hdd),
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

	.fastram_address(fastram_address),
	.fastram_datatoram(fastram_datatoram),
	.fastram_datafromram(fastram_datafromram),
	.fastram_we(fastram_we),
	.fastram_ce(fastram_ce)
);

    wire [22:0] fastram_address;
    wire [7:0] fastram_datatoram;
    wire [7:0] fastram_datafromram;
    wire fastram_we;
    wire fastram_ce;

dpram #(.widthad_a(23),.prefix("fast")) fastram
(
        .clock_a(clk_sys),
        .address_a( fastram_address ),
        .data_a(fastram_datatoram),
        .q_a(fastram_datafromram),
        .wren_a(fastram_we),
        .ce_a(fastram_ce),
);


wire ce_pix=1'b1;
/*
reg ce_pix;
always @(posedge clk_sys) begin
        reg div ;

        div <= ~div;
        ce_pix <=  &div ;
end
*/

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
assign sd_rd = { 7'b0, 1'b0,sd_rd_hd,1'b0};
assign sd_wr = { 7'b0, 1'b0,sd_wr_hd,1'b0};

reg  hdd_mounted = 0;
wire hdd_read;
wire hdd_write;
reg  hdd_protect;
reg  cpu_wait_hdd = 0;

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
		if (~old_ack & sd_ack[1]) begin
			hdd_read_pending <= 0;
			hdd_write_pending <= 0;
			sd_rd_hd <= 0;
			sd_wr_hd <= 0;
			$display("~old ack %x sd_ack[1] %x",~old_ack,sd_ack[1]);
		end
		else if(old_ack & ~sd_ack[1]) begin
			$display("old ack %x ~sd_ack[1] %x",old_ack,~sd_ack[1]);
			state <= 0;
			cpu_wait_hdd <= 0;
		end
	end
end






endmodule
