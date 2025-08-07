`timescale 1ns / 1ps

//-----------------------------------------------------------------------------
//
// Apple II/e Video Generation Logic
//
// György Szombathelyi
//
// Original Apple II+ Video Generation Logic by
// Stephen A. Edwards, sedwards@cs.columbia.edu
//
// This takes data from memory and various mode switches to produce the
// lookup address in the video ROM, and the result is fed to the video shift
// register.
//
// Based on the book Understanding the Apple IIe by Jim Sather
//
//-----------------------------------------------------------------------------
// no timescale needed

module video_generator(
input wire CLK_14M,
input wire CLK_7M,
input wire ALTCHAR,
input wire GR2,
input wire SEGA,
input wire SEGB,
input wire SEGC,
input wire WNDW_N,
input wire [7:0] DL,
input wire LDPS_N,
input wire FLASH_CLK,
output wire VIDEO
);

// 14.31818 MHz master clock
// Data from RAM
// Low-frequency flashing text clock



// IIe signals
wire [11:0] video_rom_addr;
wire [7:0] video_rom_out;
reg [7:0] video_shiftreg;

  //---------------------------------------------------------------------------
  //
  // Apple II/e Video generator circuit
  //
  // Chapter 8 of Understanding the Apple II by Jim Sather
  //
  //---------------------------------------------------------------------------
  assign video_rom_addr = {GR2,DL[7] | ( ~GR2 & DL[6] & FLASH_CLK &  ~ALTCHAR),DL[6] & (ALTCHAR | GR2 | DL[7]),DL[5:0],SEGC,SEGB,SEGA};
/*
  spram #(12,8,"rtl/roms/video.mif") videorom
  (
   .address(video_rom_addr),
   .clock(CLK_14M),
   .data(0),
   .wren(0),
   .q(video_rom_out)
  );
  */

 /*
 rom #(.memfile("chr.mem"),.AW(12)) charrom(
  .clock(CLK_14M),
  .address(video_rom_addr),
  .q(video_rom_out),
  .ce(1'b1)
);
*/

   rom #(.DW(8),.AW(12),.memfile("rtl/roms/video.hex")) videorom (
           .clock(CLK_14M),
           .ce(1'b1),
           .address(video_rom_addr),
           .q(video_rom_out)
   );


  always @(posedge CLK_14M) begin
    if(CLK_7M == 1'b0) begin
      if(LDPS_N == 1'b0) begin
        // load
        if(WNDW_N == 1'b1) begin
          video_shiftreg <= {8{1'b1}};
        end
        else begin
          video_shiftreg <= video_rom_out;
        end
      end
      else begin
        // shift
        video_shiftreg <= {video_shiftreg[0],video_shiftreg[7:1]};
      end
    end
  end

  assign VIDEO =  ~video_shiftreg[0];

endmodule
