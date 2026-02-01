//-----------------------------------------------------------------------------
//
// Apple II SCSI Card
//
// Steven A. Wilson
//
//-----------------------------------------------------------------------------
// Registers (per MAME)
//    C0n0-C0n7 = NCR5380 registers in normal order
//    C0n8 = pseudo-DMA read/write and DACK
//    C0n9 = DIP switches
//    C0na = RAM and ROM bank switching
//    C0nb = reset 5380
//    C0nc = set IIgs block mode
//    C0nd = set pseudo-DMA
//    C0ne = read DRQ status in bit 7
//-----------------------------------------------------------------------------
`timescale 1ns / 1ps

module scsicard
  #( parameter DEVS = 1 )
   (
     input	       CLK_14M,
     input	       phi0,
     input	       IO_SELECT,
     input	       DEVICE_SELECT,
     input	       C800_SELECT,
     input	       RESET,
     input [15:0]      A,
     input	       RD,
     input [7:0]       D_IN,
     output [7:0]      D_OUT,
     output [31:0]     sd_lba[DEVS],
     output [DEVS-1:0] sd_rd,
     output [DEVS-1:0] sd_wr,
     input  [DEVS-1:0] sd_ack,
     input  [DEVS-1:0] img_mounted,
     input [63:0]      img_size,
     input [8:0]       sd_buff_addr,
     input [7:0]       sd_buff_dout,
     output [7:0]      sd_buff_din[DEVS],
     input	       sd_buff_wr
    );

   // Edge detector for side effects
   logic dev_sel_d;
   always @(posedge CLK_14M) begin
      dev_sel_d <= DEVICE_SELECT;
   end

   logic ncr_dack;
   logic ncr_dreq;
   logic ncr_reset;

   logic [7:0] bank_reg;

   logic ncr_select;
   logic rom_select;
   logic ram_select;
   logic gs_dma_select;
   logic cardreg_select;

   logic [7:0] ncr_dout;
   logic [7:0] rom_dout;
   logic [7:0] ram_dout;
   logic [7:0] cardreg_dout;
   logic [7:0] gs_dma_dout;

   logic       gs_dma_mode;
   logic       dma_select;
   
   assign rom_select = (C800_SELECT && A[10]) || IO_SELECT;
   assign ram_select = (C800_SELECT && ~A[10] && ~gs_dma_mode);
   assign gs_dma_select = (C800_SELECT && ~A[10] && gs_dma_mode);
   assign ncr_select = (DEVICE_SELECT && ~A[3]) || dma_select;
   assign cardreg_select = DEVICE_SELECT && A[3];

   assign D_OUT = rom_select ? rom_dout :
                  ram_select ? ram_dout :
                  ncr_select ? ncr_dout :
                  cardreg_select ? cardreg_dout :
                  gs_dma_select ? gs_dma_dout :
                  8'hFF;
/* -----\/----- EXCLUDED -----\/-----
   always @(posedge CLK_14M) begin
      if (rom_select | ram_select | ncr_select | cardreg_select | gs_dma_select)
        $display("D_OUT %x rom_dout %x ram_dout %x ncr_dout %x cardreg_dout %x gs_dma_dout %x A %x rom_addr %x bank_reg %x IO_SELECT %x DEVICE_SELECT %x C800_SELECT %x",
                 D_OUT,  rom_dout,  ram_dout,  ncr_dout,  cardreg_dout,  gs_dma_dout,  A,  rom_addr, bank_reg, IO_SELECT,  DEVICE_SELECT,  C800_SELECT);
   end
 -----/\----- EXCLUDED -----/\----- */

   always @(posedge CLK_14M) begin
      ncr_reset <= 1'b0;
      ncr_dack <= 1'b0;
      dma_select <= 1'b0;

      if (ncr_select && phi0) begin: ncr_debug
	 if (RD) $display("[:sl7:scsi] Read ncr register %0x = %x", A[2:0], D_OUT);
	 else $display("[:sl7:scsi] Write ncr register 0%x = %x", A[2:0], D_IN);
      end: ncr_debug

      if (cardreg_select) begin: cardregs
         if (RD) begin: cardreg_read
            case (A[2:0])
              3'h0: begin: dma_read
                 $display("[:sl7:scsi] DMA read %x", ncr_dout);
                 cardreg_dout <= ncr_dout;
                 ncr_dack <= 1'b1;
                 dma_select <= 1'b1;
              end: dma_read
              3'h1: cardreg_dout <= 8'h80; // SCSI ID; 'h80 = 7
              3'h6: cardreg_dout <= {ncr_dreq, 7'h00};
              default: cardreg_dout <= 8'hFF;
            endcase;
         end: cardreg_read
         else if (~RD && phi0) begin: cardreg_write
            case (A[2:0])
              3'h0: begin: dma_write
                 $display("[:sl7:scsi] DMA write %x", D_IN);
                 ncr_dack <= 1'b1;
                 dma_select <= 1'b1;
              end: dma_write
              3'h2: begin
                 $display("[:sl7:scsi] bank %x", D_IN);
                 bank_reg <= D_IN;
              end
              3'h3: begin
                 $display("[", D_IN);
                 ncr_reset <= 1'b1;
                 gs_dma_mode <= 1'b0;
              end
              3'h4: gs_dma_mode <= 1'b1;
              3'h5: gs_dma_mode <= 1'b0;
              default: $display("[:sl7:scsi] write nonexistent cardreg %x", A[2:0]);
            endcase
         end: cardreg_write
      end: cardregs

      if (gs_dma_select) begin: gs_dma
         if (RD) begin: gs_dma_read
            $display("[:sl7:scsi] GS DMA read %x", ncr_dout);
            gs_dma_dout <= ncr_dout;
            ncr_dack <= 1'b1;
            dma_select <= 1'b1;
         end: gs_dma_read
         else begin: gs_dma_write
            $display("[:sl7:scsi] GS DMA write %x", D_IN);
            ncr_dack <= 1'b1;
            dma_select <= 1'b1;
         end: gs_dma_write
      end: gs_dma

      if (RESET) begin: sync_reset
         gs_dma_mode <= 1'b0;
         bank_reg <= 8'h00;
         ncr_reset <= 1'b1;
      end: sync_reset
   end
   
   ncr5380 #(.DEVS(DEVS)) ncr
     (
      .clk(CLK_14M),
      .reset(ncr_reset),
      .bus_cs(ncr_select),
      .bus_rs(A[2:0]),
      .ior(RD),
      .iow(~RD),
      .dack(ncr_dack),
      .dreq(ncr_dreq),
      .wdata(D_IN),
      .rdata(ncr_dout),

      .img_mounted(img_mounted),
      .img_size(img_size[40:9]), // SCSI takes size in sectors

      .io_lba(sd_lba),
      .io_rd(sd_rd),
      .io_wr(sd_wr),
      .io_ack(sd_ack),

      .sd_buff_addr(sd_buff_addr),
      .sd_buff_dout(sd_buff_dout),
      .sd_buff_din(sd_buff_din),
      .sd_buff_wr(sd_buff_wr)
      );

   logic [13:0] rom_addr;
   assign rom_addr = IO_SELECT ? {6'b0, A[7:0]} : {bank_reg[3:0], A[9:0]};

   rom #(14,8,"rtl/roms/scsicard.hex") scsirom
     (
      .clock(CLK_14M),
      .ce(1'b1),
      .address(rom_addr),
      .q(rom_dout)
      );

   ram #(13, 8) scsiram
     (
      .clk(CLK_14M),
      .d(D_IN),
      .addr({bank_reg[6:4], A[9:0]}),
      .we(~RD & ram_select),
      .q(ram_dout)
      );

/* -----\/----- EXCLUDED -----\/-----
   initial begin
      $dumpfile("scsicard.fst");
      $dumpvars(0);
   end
 -----/\----- EXCLUDED -----/\----- */
endmodule
