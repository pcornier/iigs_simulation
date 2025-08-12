module iigs
  (
   input              reset,

   input              CLK_14M,
   input              clk_vid, 
   input              ce_pix, 
   input              cpu_wait,
   input [32:0]       timestamp,

     output [7:0] R,
  output [7:0] G,
  output [7:0] B,
  output HBlank,
  output VBlank,
  output HS,
  output VS,



     // fastram sdram
  output [22:0] fastram_address,
  output [7:0] fastram_datatoram,
  input  [7:0] fastram_datafromram,
  output       fastram_we,
  output       fastram_ce,


   input [10:0]       ps2_key,
   // Floppy write-protect (sim global)
   input              floppy_wp,

 
   // HDD control
  output [15:0] HDD_SECTOR,
  output        HDD_READ,
  output        HDD_WRITE,
  input         HDD_MOUNTED,
  input         HDD_PROTECT,
  input [8:0]   HDD_RAM_ADDR,
  input [7:0]   HDD_RAM_DI,
  output [7:0]  HDD_RAM_DO,
  input         HDD_RAM_WE,


      // --- 5.25" floppy track interfaces (Drive 1/2) ---
   output [5:0]       TRACK1,
   output [12:0]      TRACK1_ADDR,
   output [7:0]       TRACK1_DI,
   input  [7:0]       TRACK1_DO,
   output             TRACK1_WE,
   input              TRACK1_BUSY,

   output [5:0]       TRACK2,
   output [12:0]      TRACK2_ADDR,
   output [7:0]       TRACK2_DI,
   input  [7:0]       TRACK2_DO,
   output             TRACK2_WE,
   input              TRACK2_BUSY,

   input [3:0]        DISK_READY,
   input              FLOPPY_WP


);
   logic [7:0]       bank;
   logic [15:0]      addr;
   logic [7:0]       dout;
   logic       slowram_ce;
   logic       rom1_ce;
   logic       rom2_ce;
   logic       romc_ce;
   logic       romd_ce;
   logic [7:0] shadow/*verilator public_flat*/;
   logic [7:0] TEXTCOLOR;
   logic [3:0] BORDERCOLOR;
   logic [7:0] SLTROMSEL;
   logic [7:0] CYAREG;
   logic CXROM;
   logic       RDROM;
   logic       LC_WE;
   logic       LCRAM2;
   logic       PAGE2/*verilator public_flat*/;
   logic       TEXTG/*verilator public_flat*/;
   logic       MIXG/*verilator public_flat*/;
   logic       HIRES_MODE/*verilator public_flat*/;
   logic       ALTCHARSET/*verilator public_flat*/;
   logic       EIGHTYCOL/*verilator public_flat*/;
   logic [7:0] NEWVIDEO/*verilator public_flat*/;
   logic IO/*verilator public_flat*/;
   logic we;
   logic VPB;

`ifdef VERILATOR
  //parameter RAMSIZE = 127; // 16x64k = 1MB, max = 127x64k = 8MB
    parameter RAMSIZE = 20; // 16x64k = 1MB, max = 127x64k = 8MB
`else
  parameter RAMSIZE = 20; // 16x64k = 1MB, max = 127x64k = 8MB
  //parameter RAMSIZE = 127; // 16x64k = 1MB, max = 127x64k = 8MB
`endif
   logic [9:0]        H;
   logic [8:0]        V;


  logic [7:0]         bank_bef;
  logic [15:0]        addr_bef;

  logic [23:0]        cpu_addr;
  logic [7:0]         cpu_dout;
  logic [23:0]        addr_bus;
  logic               cpu_vpa, cpu_vpb;
  logic               cpu_vda, cpu_mlb;
  logic               cpu_wen;
  logic [7:0]         io_dout;
  logic [7:0]         slot_dout;

  logic               onesecond_irq;
  logic               qtrsecond_irq;
  logic               snd_irq;

  logic               valid;

  logic [7:0]         prtc_din;
  logic [7:0]         prtc_dout;
  logic               prtc_addr;
  logic               prtc_rw, prtc_strobe;

  // Edge-detect for IRQ sources
  logic               vbl_irq_d;
  logic               qtr_irq_d;

  logic [7:0]         adb_din;
  logic [7:0]         adb_dout;
  logic [7:0]         adb_addr;
  logic               adb_rw, adb_strobe;

  logic [7:0]         iwm_din;
  logic [7:0]         iwm_dout;
  logic [7:0]         iwm_addr;
  logic               iwm_rw, iwm_strobe;

  // Slot HDD handled externally in top.v; no internal state here

  logic [7:0]         snd_din;
  logic [7:0]         snd_dout;
  logic [1:0]         snd_addr;
  logic               snd_rw, snd_strobe;

  logic               aux;

  // some fake registers for now
  //logic [7:0] NEWVIDEO;
  logic [7:0]         STATEREG;
  //logic [7:0]         CYAREG;
  logic [7:0]         SOUNDCTL;
  logic [7:0]         SOUNDDATA;
  logic [7:0]         DISKREG;
  //logic [7:0] SLTROMSEL;
  logic [7:0]         SOUNDADRL;
  logic [7:0]         SOUNDADRH;
  //logic [7:0] TEXTCOLOR;
  //logic ;
  logic [7:0]         SPKR;
  logic [7:0]         DISK35;
  logic [7:0]         C02BVAL;

  logic [7:0]         VGCINT; //23
  logic [7:0]         INTEN; //41
  logic [7:0]         INTFLAG; // 46, 47  AJS TODO

  logic               STORE80;
  logic               RAMRD;
  logic               RAMWRT;
  logic               INTCXROM;
  logic               ALTZP;
  logic               SLOTC3ROM;
  //logic               EIGHTYCOL;
  //logic               ALTCHARSET;
  //logic PAGE2;
  logic [7:0]         MONOCHROME;
  //logic RDROM;
  //logic LCRAM2;
  //logic LC_WE;
  logic               ROMBANK;

  logic               LC_WE_PRE;

  logic inhibit_cxxx;

  //logic TEXTG;
  //logic MIXG;

  logic               slot_area;
  logic [3:0]         slotid;

  // remap c700 to c500 if slot access and $C02D[7]
  //assign addr_bus =
  // slot_area && cpu_addr[15:8] == 8'b11000111 ? { cpu_addr[23:10], ~SLTROMSEL[7], cpu_addr[8:0] } : cpu_addr;

  logic               is_internal_io;

  logic               EXTERNAL_IO;

  logic               rom_writethrough;

  logic               lcram2_sel;

  assign VPB=cpu_vpb;
  assign CXROM=INTCXROM;
  assign { bank, addr } = addr_bus;
  assign dout = cpu_dout;
  assign we = ~cpu_wen;
  assign valid = cpu_vpa | cpu_vda;
  assign slot_area = addr[15:0] >= 16'hc100 && addr[15:0] <= 16'hcfff;
  assign slotid = addr[11:8];
  assign is_internal_io =   ~SLTROMSEL[addr[6:4]];



  assign EXTERNAL_IO =    ((bank == 8'h0 || bank == 8'h1 || bank == 8'he0 || bank == 8'he1) && addr >= 'hc090 && addr < 'hc100 && ~is_internal_io);

  assign inhibit_cxxx = lcram2_sel | ((bank == 8'h0 | bank == 8'h1 | bank == 8'he0 | bank == 8'he1) & shadow[6]);

// from c000 to c0ff only, c100 to cfff are slots or ROM based on $C02D
//wire IO = ~shadow[6] && addr[15:8] == 8'hc0 && (bank == 8'h0 || bank == 8'h1 || bank == 8'he0 || bank == 8'he1);
//assign IO =  /*~RAMRD & ~RAMWRT &*/ ~EXTERNAL_IO &  ((~shadow[6] & addr[15:8] == 8'hC0) | (shadow[6] & addr[15:13] == 3'b110)) & (bank == 8'h0 | bank == 8'h1 | bank == 8'he0 | bank == 8'he1);
  assign IO =  /*~RAMRD & ~RAMWRT &*/ ~EXTERNAL_IO &  
               (((bank == 8'h0 | bank == 8'h1) & ~shadow[6] & cpu_addr[15:8] == 8'hC0) |
                ((bank == 8'he0 | bank == 8'he1) & cpu_addr[15:8] == 8'hC0));

  assign { bank_bef, addr_bef } = cpu_addr;

  always_comb begin
    lcram2_sel = 0;
    if ((bank_bef == 'he0  || bank_bef == 8'he1) && addr_bef >= 'hd000 && addr_bef <='hdfff && LCRAM2 && ~RDROM  )
      begin
        lcram2_sel = 1;
        if (aux && bank_bef==8'he0)
          addr_bus = addr_bef- 'h1000 + 'h10000;
        else
          addr_bus = {bank_bef,16'h0} + addr_bef- 'h1000;
      end
    else if ((bank_bef == 'he0  || bank_bef == 8'he1) && addr_bef >= 'he000 && ~RDROM )
      begin
        lcram2_sel = 1;
        if (aux && bank_bef==8'he0)
          addr_bus = addr_bef + 'h10000;
        else
          addr_bus = {bank_bef,16'h0} + addr_bef;
      end
    else if ((bank_bef == 'h00  || bank_bef == 8'h1) && addr_bef >= 'hd000 && addr_bef <='hdfff && LCRAM2 /*&& RDROM*/ && ~shadow[6]  )
      begin
         lcram2_sel = 1;
	 if (aux && bank_bef=='h00)
           begin
             //$display("HERE1: %x %x",addr_bef,addr_bef+'h10000);
             addr_bus = addr_bef- 'h1000 + 'h10000;
           end
         else
           addr_bus = {bank_bef,16'h0} +addr_bef- 'h1000;
      end
    else if ((bank_bef == 'h00  || bank_bef == 8'h1) && addr_bef >= 'he000 && ~RDROM && ~shadow[6] )
      begin
         lcram2_sel = 1;
	 if (aux && bank_bef=='h00)
           begin
             addr_bus = addr_bef + 'h10000;
           end
         else
           addr_bus = {bank_bef,16'h0} + addr_bef;
      end
    else
      if (aux && (bank_bef=='h00 || bank_bef=='he0) )
        //if (aux)
        begin
          //$display("HERE2: %x %x",addr_bef,addr_bef+'h10000);
          addr_bus = addr_bef + 'h10000;
        end
      else
        addr_bus = cpu_addr;
    /*RDROM <= 1'b1;
     LCRAM2 <= 1'b1;
     LC_WE <= 1'b1;
     */
  end

  // RAM Chip Enables
  //assign slowram_ce = bank == 8'he0 || bank == 8'he1;
  always_comb begin
    // shadow
    //Bit 6: I/O Memory, Bit 5: Alternate Display Mode
    //Bit 4: Auxilary HGR, Bit 3: Super HiRes, Bit 2: HiRes Page 2
    //Bit 1: HiRes Page 1, Bit 0: Text/LoRes
    //
    //if (~shadow[6]) $display("UNIMPLEMENTED SHADOW 6");
    // read or write to e0 or e1 -- turn on the slowram
    if ((bank == 8'he0 || bank == 8'he1 ) && ~IO )
      slowram_ce = 1;
    //Bit 6: I/O Memory
    //else  if ((bank == 8'h00 || bank == 8'h01) && ~IO && ~shadow[6] && addr >= 'hc000 && addr <= 'hcfff )
    else  if ((bank == 8'h00 || bank == 8'h01) && ~IO && ~shadow[6] && addr >= 'hc000 && addr <= 'hffff )
      slowram_ce = 1;
    //Bit 5: Alternate Display Mode
    else  if (bank == 8'h00 && ~shadow[5] && addr >= 'h0800 && addr <= 'h0bff && ~IO)
      slowram_ce = 1;
    //Bit 5 AUX: Alt Display Mode
    else  if (bank == 8'h01 && ~shadow[5] && ~shadow[4] && addr >= 'h0800 && addr <= 'h0bff && ~IO)
      slowram_ce = 1;
    //Bit 4: (used in combo)
    //Bit 3,2: Super HiRes or parts or HiRes Page 2
    else  if (bank == 8'h00 && (~shadow[2]  || ~shadow[3] ) && addr >= 'h4000 && addr <= 'h5fff && ~IO)
      slowram_ce = 1;
    //Bit 3,2: Super HiRes or parts or HiRes Page 2 and Aux
    else  if (bank == 8'h01 && ((~shadow[2] && ~shadow[4]) || ~shadow[3] ) && addr >= 'h4000 && addr <= 'h5fff && ~IO)
      slowram_ce = 1;
    //Bit 3,1: Super HiRes or parts or HiRes Page 1
    else  if (bank == 8'h00 && (~shadow[1]  || ~shadow[3] ) && addr >= 'h2000 && addr <= 'h3fff && ~IO)
      slowram_ce = 1;
    //Bit 3,1: Super HiRes or parts or HiRes Page 1 and Aux
    else  if (bank == 8'h01 && ((~shadow[1] && ~shadow[4]) || ~shadow[3] ) && addr >= 'h2000 && addr <= 'h3fff && ~IO)
      slowram_ce = 1;
    //Bit 0: Alternate Display Mode
    else  if (bank == 8'h00 && ~shadow[0] && addr >= 'h0400 && addr <= 'h07ff && ~IO)
      slowram_ce = 1;
    //Bit 0 AUX: Alt Display Mode
    else  if (bank == 8'h01 && ~shadow[0] && ~shadow[4] && addr >= 'h0400 && addr <= 'h07ff && ~IO)
      slowram_ce = 1;
    else
      slowram_ce =0;
    //   if (bank == 8'h00
  end

  //assign fastram_ce = (bank < RAMSIZE) & ~slot_ce & ~slot_internalrom_ce ; // bank[7] == 0;
  //
  //assign rom_writethrough = ( (bank == 8'h0) & (addr>=16'hd000) & (addr <= 16'hdfff) & LC_WE);
  assign rom_writethrough = ( (bank_bef == 8'h0) & (addr_bef >= 16'hd000) & (addr_bef <= 16'hffff) & LC_WE);
  assign fastram_ce = (bank_bef < RAMSIZE)  & ( ~rom2_ce | rom_writethrough)  & ~rom1_ce &~IO; // bank[7] == 0;

  assign romc_ce = bank == 8'hfc;
  assign romd_ce = bank == 8'hfd;
  assign rom1_ce = bank == 8'hfe;
  assign rom2_ce = bank == 8'hff ||
                   (bank == 8'h0 & addr >= 16'hd000 & addr <= 16'hdfff && (RDROM|~VPB)) ||
                   (bank == 8'h0 & addr >= 16'hc000 & addr <= 16'hcfff && (RDROM|~VPB)) ||
                   (bank == 8'h0 & addr >= 16'he000 &                     (RDROM|~VPB)) ||
                   (bank == 8'h0 & addr >= 16'hc070 & addr <= 16'hc07f);

  // driver for io_dout and fake registers
  always_ff @(posedge CLK_14M) begin
    if (reset) begin
      // dummy values dumped from emulator
      CYAREG <= 8'h80; // motor speed
      STATEREG <=  8'b0000_1001;
      shadow <= 8'b0000_1000;
      SOUNDCTL <= 8'd0;
      //SOUNDCTL <= 8'h05;
      NEWVIDEO <= 8'h41;
      C02BVAL <= 8'h08;

      // FROM GSPLUS
      INTCXROM<=1'b1;
      RDROM<=1'b1;
      LCRAM2<=1'b1;
      LC_WE_PRE<=1'b0;

      DISKREG<=0;
      SLTROMSEL<=0;
      TEXTCOLOR<='hf2;
      SPKR<=0;
      DISK35<=0;
      VGCINT<=0; //23
      INTEN<=0; //41
      INTFLAG<=0; // 46, 47  AJS TODO

      STORE80<=0;
      RAMRD<=0;
      RAMWRT<=0;
      INTCXROM<=0;
      ALTZP<=0;
      SLOTC3ROM<=0;
      EIGHTYCOL<=0;
      ALTCHARSET<=0;
      PAGE2<=0;
      MONOCHROME<=0;
      RDROM<=1;
      LCRAM2<=0;
      LC_WE<=0;
      ROMBANK<=0;;
    end

    key_reads<=0;
    // Default pass-through for unhandled IO: feed external bus data
    io_dout <= din;
    adb_strobe <= 1'b0;
    if (adb_strobe & cpu_wen) begin
      io_dout <= adb_dout;
    end

    prtc_strobe <= 1'b0;
    if (prtc_strobe & cpu_wen) begin
      io_dout <= prtc_dout;
    end

    iwm_strobe <= 1'b0;
    if (iwm_strobe & cpu_wen & phi2) begin
      $display("read_iwm %x ret: %x GC036: %x (addr %x) cpu_addr(%x)",addr[11:0],iwm_dout,CYAREG,addr,cpu_addr);
      io_dout <= iwm_dout;
    end

    snd_strobe <= 1'b0;
    if (snd_strobe & cpu_wen) begin
      io_dout <= snd_dout;
    end

    if (IO) begin
      if (~cpu_wen)
        // write
        begin
          //$display("** IO_WR %x %x",addr[11:0],cpu_dout);
          case (addr[11:0])
            12'h000: begin $display("**STORE80 %x",0); STORE80<= 1'b0 ; end
            12'h001: begin $display("**STORE80 %x",1); STORE80<= 1'b1 ; end
            12'h002: begin $display("**RAMRD %x",0); RAMRD<= 1'b0 ; end
            12'h003: begin $display("**RAMRD %x",1); RAMRD<= 1'b1 ; end
            12'h004: begin $display("**RAMWRT %x",0); RAMWRT<= 1'b0 ; end
            12'h005: begin $display("**RAMWRT %x",1); RAMWRT<= 1'b1 ; end
            12'h006: begin $display("**INTCXROM %x",0);INTCXROM<= 1'b0; end
            12'h007: begin $display("**INTCXROM %x",1);INTCXROM <= 1'b1; end
            12'h008: begin $display("**ALTZP %x",0); ALTZP<= 1'b0; end
            12'h009: begin $display("**ALTZP %x",1); ALTZP<= 1'b1; end
            12'h00A: begin $display("**SLOTC3ROM %x",0);SLOTC3ROM<= 1'b0; end
            12'h00B: begin $display("**SLOTC3ROM %x",1);SLOTC3ROM<= 1'b1; end
            12'h00C: begin $display("**EIGHTYCOL %x",0); EIGHTYCOL<= 1'b0; end
            12'h00D: begin $display("**EIGHTYCOL %x",1); EIGHTYCOL<= 1'b1; end
            12'h00E: begin $display("**ALTCHARSET %x",0); ALTCHARSET<= 1'b0; end
            12'h00F: begin $display("**ALTCHARSET %x",1); ALTCHARSET<= 1'b1; end
            12'h010, 12'h026, 12'h027, 12'h070: begin
              if (addr[11:0]==12'h010)
                key_reads<=1;
              adb_addr <= addr[7:0];
              adb_strobe <= 1'b1;
              adb_din <= cpu_dout;
              adb_rw <= 1'b0;
              $display("ADB WR %03h <= %02h", addr[11:0], cpu_dout);
            end
            12'h011,12'h12,12'h13,12'h14,12'h15,12'h16,12'h17,12'h18,12'h19,12'h1a,12'h1b,12'h1c,
              12'h01d,12'h1e,12'h1f:
                begin
                  //key_reads<=1;
                end
            12'h021: MONOCHROME <=cpu_dout;
            12'h022: TEXTCOLOR <= cpu_dout;
            12'h023: begin $display("VGCINT 23 2 %x 1 %x",cpu_dout[2],cpu_dout[1]);VGCINT <= { VGCINT[7:3],cpu_dout[2:1],VGCINT[0]} ; end // code can only modify the enable bits
            12'h028: begin ROMBANK <= ~ROMBANK; $display("**++UNIMPLEMENTEDROMBANK %x",cpu_dout);  end
            12'h029: begin $display("**NEWVIDEO %x",cpu_dout);NEWVIDEO <= cpu_dout; end
            12'h02b: C02BVAL <= cpu_dout; // from gsplus
            12'h02d: SLTROMSEL <= cpu_dout;
            12'h030: SPKR <= cpu_dout;
            12'h031: begin
              DISK35<= cpu_dout & 8'hc0;
`ifdef SIMULATION
              $display("IWM DBG: WR $C031 <= %02h (DISK35 bit6=%0d bit7=%0d)", cpu_dout, (cpu_dout>>6)&1'b1, (cpu_dout>>7)&1'b1);
`endif
            end
            12'h032:
              begin
                $display("VGCINT 32: bit6 %x bit5 %x",cpu_dout[6],cpu_dout[5]);
                if (cpu_dout[6]==1'b0)
                  VGCINT[6]<=1'b0;
                if (cpu_dout[5]==1'b0)
                  VGCINT[5]<=1'b0;
                // clear 7 if both are cleared
                if ((VGCINT[5]==0 || cpu_dout[5]==0) && (VGCINT[6]==0 || cpu_dout[6]==0))
                  VGCINT[7]<=1'b0;
              end
            12'h033, 12'h034: begin
              prtc_rw <= 1'b0;
              prtc_strobe <= 1'b1;
              prtc_addr <= ~addr[0];
              prtc_din <= cpu_dout;
              if (~addr[0])
                BORDERCOLOR=cpu_dout[3:0];
            end
            12'h035: shadow <= cpu_dout;
            12'h036: begin $display("__CYAREG %x",cpu_dout);CYAREG <= cpu_dout; end
            // SCC (Serial) writes: log for debugging (unimplemented)
            12'h038, 12'h039, 12'h03a, 12'h03b: begin
              $display("SCC WR %03h <= %02h (unimpl)", addr[11:0], cpu_dout);
            end
            12'h03c, 12'h03d, 12'h03e, 12'h03f: begin
              snd_rw <= 1'b1;
              snd_strobe <= 1'b1;
              snd_addr <= addr[1:0];
              snd_din <= cpu_dout;
              $display("SOUND WR %03h <= %02h (SNDCTL/DATA/APL/APH)", addr[11:0], cpu_dout);
            end
            12'h041: begin $display("INTEN: %02x -> %02x",INTEN,{INTEN[7:5],cpu_dout[4:0]}); INTEN <= {INTEN[7:5],cpu_dout[4:0]}; end
            12'h042: $display("**++UNIMPLEMENTEDMEGAIIINTERRUPT");
            12'h047: begin $display("CLEAR INT");INTFLAG[4:3]<=2'b00; end // clear the interrupts
            12'h050: begin $display("**TEXTG %x",0); TEXTG<=1'b0;end
            12'h051: begin $display("**TEXTG %x",1); TEXTG<=1'b1;end
            12'h052: begin $display("**MIXG %x",0); MIXG<=1'b0;end
            12'h053: begin $display("**MIXG %x",1); MIXG<=1'b1;end
            12'h054: begin $display("**PAGE2 %x",0);PAGE2<=1'b0; end
            12'h055: begin $display("**PAGE2 %x",1);PAGE2<=1'b1; end
            12'h056: begin $display("**%x",0);HIRES_MODE<=1'b0; end
            12'h057: begin $display("**%x",1);HIRES_MODE<=1'b1; end
            // $C068: bit0 stays high during boot sequence, why?
            // if bit0=1 it means that internal ROM at SCx00 is selected
            // does it mean slot cards are not accessible?
            12'h068: begin $display("** WR68: %x  ALTZP %x PAGE2 %x RAMRD %x RAMWRT %x RDROM %x LCRAM2 %x ROMBANK %x INTCXROM %x ",cpu_dout,cpu_dout[7],cpu_dout[6],cpu_dout[5],cpu_dout[4],cpu_dout[3],cpu_dout[2],cpu_dout[1],cpu_dout[0]); {ALTZP,PAGE2,RAMRD,RAMWRT,RDROM,LCRAM2,ROMBANK,INTCXROM} <= {cpu_dout[7:4],cpu_dout[3],cpu_dout[2:0]}; end
            //12'h068: begin $display("** WR68: %x  ALTZP %x PAGE2 %x RAMRD %x RAMWRT %x RDROM %x LCRAM2 %x ROMBANK %x INTCXROM %x ",cpu_dout,cpu_dout[7],cpu_dout[6],cpu_dout[5],cpu_dout[4],cpu_dout[3],cpu_dout[2],cpu_dout[1],cpu_dout[0]); {ALTZP,PAGE2,RAMRD,RAMWRT,RDROM,LCRAM2,ROMBANK,INTCXROM} <= {cpu_dout[7:4],cpu_dout[3],cpu_dout[2:0]}; end


            12'h080,	// Read RAM bank 2 no write
              12'h084:	// Read bank 2 no write
                begin
                  RDROM <= 1'b0;
                  LCRAM2 <= 1'b1;
                  LC_WE <= 1'b0;
                  LC_WE_PRE<=1'b0;
                end
            12'h081,	// Read ROM write RAM bank 2 (RR)
              12'h085:
                begin
                  $display("WRITE: ROM WRITE THROUGH LC_WE_PRE %x LC_WE %x",LC_WE_PRE,LC_WE);
                  RDROM <= 1'b1;
                  LCRAM2 <= 1'b1;
                  LC_WE <= 1'b0;
                  LC_WE_PRE<=1'b0;
                end
            12'h082,	// Read ROM no write
              12'h086:
                begin
                  RDROM <= 1'b1;
                  LCRAM2 <= 1'b0;
                  LC_WE <= 1'b0;
                  LC_WE_PRE<=1'b0;
                end
            12'h083,	// Read bank 2 write bank 2(RR)
              12'h087:
                begin
                  $display("WRITE: ROM WRITE THROUGH LC_WE_PRE %x LC_WE %x",LC_WE_PRE,LC_WE);
                  RDROM <= 1'b0;
                  LCRAM2 <= 1'b1;
                  LC_WE <= 1'b0;
                  LC_WE_PRE<=1'b0;
                end
            12'h088,
              12'h08C:
                begin
                  RDROM <= 1'b0;
                  LCRAM2 <= 1'b0;
                  LC_WE <= 1'b0;
                  LC_WE_PRE<=1'b0;
                end
            12'h089,
              12'h08D:
                begin
                  $display("WRITE: ROM WRITE THROUGH LC_WE_PRE %x LC_WE %x",LC_WE_PRE,LC_WE);
                  RDROM <= 1'b1;
                  LCRAM2 <= 1'b0;
                  LC_WE <= 1'b0;
                  LC_WE_PRE<=1'b0;
                end
            12'h08A,
              12'h08E:
                begin
                  RDROM <= 1'b1;
                  LCRAM2 <= 1'b0;
                  LC_WE <= 1'b0;
                  LC_WE_PRE<=1'b0;
                end
            12'h08B,
              12'h08F:
                begin
                  $display("WRITE: ROM WRITE THROUGH LC_WE_PRE %x LC_WE %x",LC_WE_PRE,LC_WE);
                  RDROM <= 1'b0;
                  LCRAM2 <= 1'b0;
                  LC_WE <= 1'b0;
                  LC_WE_PRE<=1'b0;
                end

            12'h0e0, 12'h0e1, 12'h0e2, 12'h0e3,
              12'h0e4, 12'h0e5, 12'h0e6, 12'h0e7,
              12'h0e8, 12'h0e9, 12'h0ea, 12'h0eb,
              12'h0ec, 12'h0ed, 12'h0ee, 12'h0ef:
                begin
                  iwm_addr <= addr[7:0];
                  iwm_strobe <= 1'b1;
                  iwm_din <= cpu_dout;
                  iwm_rw <= 1'b0;
                  $display("IWM WR %03h <= %02h", addr[11:0], cpu_dout);
                end
            // Slot IO $C0D0-$C0DF (SmartPort) and $C0F0-$C0FF handled externally at top-level. Do not override here.
            12'h0d0,12'h0d1,12'h0d2,12'h0d3,
            12'h0d4,12'h0d5,12'h0d6,12'h0d7,
            12'h0d8,12'h0d9,12'h0da,12'h0db,
            12'h0dc,12'h0dd,12'h0de,12'h0df: begin
              // no-op: external SmartPort handles this range
            end
            default:
              $display("** IO_WR %x %x",addr[11:0],cpu_dout);
          endcase
        end
      else
        begin
          // read
          //$display("** IO_RD %x, RDROM %x ",addr[11:0], RDROM);
          case (addr[11:0])
            12'h000, 12'h010, 12'h024, 12'h025,
            12'h026, 12'h027, 12'h044, 12'h045,
            12'h061, 12'h062, 12'h064, 12'h065,
            12'h066, 12'h067, 12'h070: begin
              adb_addr <= addr[7:0];
              adb_strobe <= 1'b1;
              adb_rw <= 1'b1;
              $display("ADB RD %03h", addr[11:0]);
              if (addr[11:0] == 12'h010) begin  key_reads<=1; io_dout <= key_keys; end
              if (addr[11:0] == 12'h000) begin  $display("anykeydown: %x key_pressed %x",key_anykeydown,key_pressed);  if (key_pressed) io_dout <= key_keys | 'h80 ; else io_dout<='h00; end
              //if (addr[11:0] == 12'h000) begin  $display("anykeydown: %x",key_anykeydown);  if (key_anykeydown) io_dout <= key_keys | 'h80 ; else io_dout<='h00; end
              if (addr[11:0] == 12'h025) begin  $display("keymodereg");end
            end

            12'h002: begin $display("**RAMRD %x",0); RAMRD<= 1'b0 ; end
            12'h003: begin $display("**RAMRD %x",1); RAMRD<= 1'b1 ; end
            12'h004: begin $display("**RAMWRT %x",0); RAMWRT<= 1'b0 ; end
            12'h005: begin $display("**RAMWRT %x",1); RAMWRT<= 1'b1 ; end

            //12'h010: begin io_dout<=key_keys; key_reads<=1; end
            //12'h010: begin $display("anykeydown: %x",key_anykeydown); if (key_anykeydown) io_dout<='h80 | key_keys ; else io_dout<='h00; end

            12'h011: if(LCRAM2) io_dout<='h80 | key_keys; else io_dout<='h00;
            12'h012: if(~RDROM) io_dout<='h80 | key_keys; else io_dout<='h00;
            12'h013: if(RAMRD) io_dout<='h80 | key_keys; else io_dout<='h00;
            12'h014: if(RAMWRT) io_dout<='h80 | key_keys; else io_dout<='h00;
            12'h015: begin $display("read INTCXROM %x ",INTCXROM); if(INTCXROM) io_dout<='h80 | key_keys; else io_dout<='h00;end
            12'h016: if(ALTZP) io_dout<='h80 | key_keys; else io_dout<='h00;
            12'h017: if(SLOTC3ROM) io_dout<='h80 | key_keys; else io_dout<='h00;
            12'h018: if(STORE80) io_dout<='h80 | key_keys; else io_dout<='h00;
            12'h019: if(VBlank) io_dout<='h00 | key_keys; else io_dout<='h80;
            12'h01a: if(TEXTG) io_dout<='h80 | key_keys; else io_dout<='h00;
            12'h01b: if(MIXG) io_dout<='h80 | key_keys; else io_dout<='h00;
            12'h01c: if(PAGE2) io_dout<='h80 | key_keys; else io_dout<='h00;
            12'h01d: if(~HIRES_MODE) io_dout<='h80 | key_keys; else io_dout<='h00;
            12'h01e: if(ALTCHARSET) io_dout<='h80 | key_keys; else io_dout<='h00;
            12'h01f: if(EIGHTYCOL) io_dout <= 'h80 | key_keys; else io_dout<='h00;

            12'h022: io_dout <= TEXTCOLOR;
            12'h023: begin $display("READ VGCINT %x",VGCINT);io_dout <= VGCINT; end /* vgc int */


            //12'h028: $display("**++UNIMPLEMENTEDROMBANK (28)");
            12'h028: begin ROMBANK <= ~ROMBANK; $display("**++UNIMPLEMENTEDROMBANK %x",~ROMBANK);  end
            12'h029: io_dout <= NEWVIDEO;
            12'h02a: io_dout <= 'h0; // from gsplus
            12'h02b: io_dout <= C02BVAL; // from gsplus
            12'h02c: io_dout <= 'h0; // from gsplus
            12'h02d: io_dout <= SLTROMSEL;
            12'h02e: io_dout <= V[8:1]; /* vertcount */
            12'h02f: io_dout <= {V[0], H[9:2]}; /* horizcount */
            12'h030: io_dout <= SPKR;
            12'h031: io_dout <= DISK35;
            //12'h032: io_dout <= VGCINT; can you read this??
            12'h032: io_dout <= 0;// can you read this??
            12'h033, 12'h034: begin
              prtc_addr <= ~addr[0];
              prtc_rw <= 1'b1;
              prtc_strobe <= 1'b1;
            end
            12'h035: io_dout <= shadow;
            12'h036: begin $display("__CYAREG %x",CYAREG);io_dout<=CYAREG; end
            12'h037: io_dout <= 'h0; // from gsplus

            12'h038: begin $display("SCCB CTRL READ");io_dout <= 8'h04; end // Tx buffer empty = 1
            12'h039: begin $display("SCCA CTRL READ");io_dout <= 8'h04; end // Tx buffer empty = 1
            12'h03a: begin $display("SCCB DATA READ");io_dout <= 8'h00; end
            12'h03b: begin $display("SCCA DATA READ");io_dout <= 8'h00; end

            12'h03c, 12'h03d, 12'h03e, 12'h03f: begin
              snd_addr <= addr[1:0];
              snd_rw <= 1'b0;
              snd_strobe <= 1'b1;
            end
            12'h041: begin $display("read INTEN %x",INTEN);io_dout <= INTEN;end
            12'h042: $display("**++UNIMPLEMENTEDMEGAIIINTERRUPT");
            //12'h046: io_dout <=  {C046VAL[7], C046VAL[7], C046VAL[6:0]};
            12'h046: begin
              io_dout <= INTFLAG;
`ifdef SIMULATION
              $display("READ INTFLAG -> %02h (auto-clear VBL/QTR)", INTFLAG);
`endif
              // Auto-clear VBL/QTR on read to avoid stuck IRQs if OS doesn't write $C047
              INTFLAG[4:3] <= 2'b00;
            end
            //12'h047: begin io_dout <= 'h0; C046VAL &= 'he7; end// some kind of interrupt thing
            12'h047: begin $display("CLEAR INT");$display("INTFLAG CLEAR INTERRUPTS"); INTFLAG[4:3]<=2'b00; INTFLAG[0]<=1'b0; end // clear the interrupts
            12'h050: begin $display("**TEXTG %x",0); TEXTG<=1'b0;end
            12'h051: begin $display("**TEXTG %x",1); TEXTG<=1'b1;end
            12'h052: begin $display("**MIXG %x",0); MIXG<=1'b0;end
            12'h053: begin $display("**MIXG %x",1); MIXG<=1'b1;end
            12'h054: begin $display("**PAGE2 %x",0);PAGE2<=1'b0; end
            12'h055: begin $display("**PAGE2 %x",1);PAGE2<=1'b1; end
            12'h056: begin $display("**%x",0);HIRES_MODE<=1'b0; end
            12'h057: begin $display("**%x",1);HIRES_MODE<=1'b1; end
            12'h058: io_dout <= 'h0; // some kind of soft switch?
            12'h05a: io_dout <= 'h0; // some kind of soft switch?
            12'h05d: io_dout <= 'h0; // some kind of soft switch?
            12'h05f: io_dout <= 'h0; // some kind of soft switch?
            12'h068: io_dout <= {ALTZP,PAGE2,RAMRD,RAMWRT,RDROM,LCRAM2,ROMBANK,INTCXROM};
            12'h071, 12'h072, 12'h073, 12'h074,
              12'h075, 12'h076, 12'h077, 12'h078,
              12'h079, 12'h07a, 12'h07b, 12'h07c,
              12'h07d, 12'h07e, 12'h07f:
                io_dout <= din;

            /*****************************************************************************
             * Language Card Memory
             *
             *           $C080 ;LC RAM bank2, Read and WR-protect RAM
             *ROMIN =    $C081 ;LC RAM bank2, Read ROM instead of RAM,
             *                 ;two or more successive reads WR-enables RAM
             *           $C082 ;LC RAM bank2, Read ROM instead of RAM,
             *                 ;WR-protect RAM
             *LCBANK2 =  $C083 ;LC RAM bank2, Read RAM
             *                 ;two or more successive reads WR-enables RAM
             *           $C088 ;LC RAM bank1, Read and WR-protect RAM
             *           $C089 ;LC RAM bank1, Read ROM instead of RAM,
             *                 ;two or more successive reads WR-enables RAM
             *           $C08A ;LC RAM bank1, Read ROM instead of RAM,
             *                 ;WR-protect RAM
             *LCBANK1 =  $C08B ;LC RAM bank1, Read RAM
             *                 ;two or more successive reads WR-enables RAM
             *           $C084-$C087 are echoes of $C080-$C083
             *           $C08C-$C08F are echoes of $C088-$C08B
             *
             ******************************************************************************/
            12'h080,	// Read RAM bank 2 no write
              12'h084:	// Read bank 2 no write
                begin
                  $display("READ 80/84: NO ROM WRITE THROUGH LC_WE_PRE %x LC_WE %x",LC_WE_PRE,LC_WE);
                  RDROM <= 1'b0;
                  LCRAM2 <= 1'b1;
                  LC_WE <= 1'b0;
                  LC_WE_PRE<=1'b0;
                end
            12'h081,	// Read ROM write RAM bank 2 (RR)
              12'h085:
                begin
                  $display("READ 81/85: ROM WRITE THROUGH LC_WE_PRE %x LC_WE %x",LC_WE_PRE,LC_WE);
                  RDROM <= 1'b1;
                  LCRAM2 <= 1'b1;
                  if (phi0) begin
                    LC_WE <= LC_WE_PRE  ;
                    LC_WE_PRE<=1'b1  ;
                  end
                end
            12'h082,	// Read ROM no write
              12'h086:
                begin
                  $display("READ 82/86: NO ROM WRITE THROUGH LC_WE_PRE %x LC_WE %x",LC_WE_PRE,LC_WE);
                  RDROM <= 1'b1;
                  LCRAM2 <= 1'b0;
                  LC_WE <= 1'b0;
                  LC_WE_PRE<=1'b0;
                end
            12'h083,	// Read bank 2 write bank 2(RR)
              12'h087:
                begin
                  $display("READ 83/87: ROM WRITE THROUGH LC_WE_PRE %x LC_WE %x",LC_WE_PRE,LC_WE);
                  RDROM <= 1'b0;
                  LCRAM2 <= 1'b1;
                  if (phi0) begin
                    LC_WE <= LC_WE_PRE  ;
                    LC_WE_PRE<=1'b1  ;
                  end
                end
            12'h088,
              12'h08C:
                begin
                  $display("READ 88/8C: NO ROM WRITE THROUGH LC_WE_PRE %x LC_WE %x",LC_WE_PRE,LC_WE);
                  RDROM <= 1'b0;
                  LCRAM2 <= 1'b0;
                  LC_WE <= 1'b0;
                  LC_WE_PRE<=1'b0;
                end
            12'h089,
              12'h08D:
                begin
                  $display("READ 89/8D: ROM WRITE THROUGH LC_WE_PRE %x LC_WE %x",LC_WE_PRE,LC_WE);
                  RDROM <= 1'b1;
                  LCRAM2 <= 1'b0;
                  if (phi0) begin
                    LC_WE <= LC_WE_PRE  ;
                    LC_WE_PRE<=1'b1  ;
                  end
                end
            12'h08A,
              12'h08E:
                begin
                  $display("READ 8A/8E: NO ROM WRITE THROUGH LC_WE_PRE %x LC_WE %x",LC_WE_PRE,LC_WE);
                  RDROM <= 1'b1;
                  LCRAM2 <= 1'b0;
                  LC_WE <= 1'b0;
                  LC_WE_PRE<=1'b0;
                end
            12'h08B,
              12'h08F:
                begin
                  $display("READ 8B/8F: ROM WRITE THROUGH LC_WE_PRE %x LC_WE %x",LC_WE_PRE,LC_WE);
                  RDROM <= 1'b0;
                  LCRAM2 <= 1'b0;
                  if (phi0) begin
                    LC_WE <= LC_WE_PRE  ;
                    LC_WE_PRE<=1'b1  ;
                  end
                end

            12'h0e0, 12'h0e1, 12'h0e2, 12'h0e3,
              12'h0e4, 12'h0e5, 12'h0e6, 12'h0e7,
              12'h0e8, 12'h0e9, 12'h0ea, 12'h0eb,
              12'h0ec, 12'h0ed, 12'h0ee, 12'h0ef:
                begin
                  iwm_addr <= addr[7:0];
                  iwm_strobe <= 1'b1;
                  iwm_rw <= 1'b1;
                  $display("IWM RD %03h -> %02h", addr[11:0], iwm_dout);
                end
            // Slot IO $C0D0-$C0DF (SmartPort) and $C0F0-$C0FF handled externally at top-level. Do not override here.
            12'h0d0,12'h0d1,12'h0d2,12'h0d3,
            12'h0d4,12'h0d5,12'h0d6,12'h0d7,
            12'h0d8,12'h0d9,12'h0da,12'h0db,
            12'h0dc,12'h0dd,12'h0de,12'h0df: begin
              // no-op: external SmartPort handles this range
            end
            default:
              $display("** IO_RD %x ",addr[11:0]);
          endcase
        end
    end

    /* *
     *  IRQ Logic
     *
     *  IIe Interrupts (INTEN/ INTFLAG):
     *  VBL - check interrupts enabled, and  intflag
     *  Quarter second (clock_frame%15?) - interrupts enabled and intflag
     *  VGC IIgs Interrupts: VGCINT
     *  1 second - interrupte enabled , VGC Interrupt
     *  scanline interrupt sets bit even if it doesn't trigger..
     * */
    //
    //VGCINT[]
    //reg [7:0] VGCINT; //23
    //reg [7:0] INTEN; //41    [0][0][0][1/4 sec][VBL][switch][move][mouse]
    //reg [7:0] INTFLAG; // 46 (47 clear)  AJS [mouse now][mouse last][an3][1/4sec][vbl][switch][move][system irq]
    VGCINT[4]<=1'b0; // EXT INT ALWAYS 0 in IIGS
    if (scanline_irq) begin
      // always set the status bit
      VGCINT[5] <= 1'b1;
`ifdef SIMULATION
      $display("VGC scanline_irq: set VGCINT[5]=1 (enable=%0d)", VGCINT[1]);
`endif
      if (VGCINT[1]) // if it is enabled, set the bit
        begin
          $display("firing scanline");
          VGCINT[7]<=1'b1;
        end
    end
    if (onesecond_irq & VGCINT[2]) begin
      VGCINT[6]<=1'b1;
      VGCINT[7]<=1'b1;
`ifdef SIMULATION
      $display("VGC 1-second irq: set VGCINT[6]=1");
`endif
    end

    // Latch VBL and quarter-second on rising edges only
    // to avoid immediate reassert after a clear while source stays high
    vbl_irq_d <= vbl_irq;
    qtr_irq_d <= qtrsecond_irq;
    if ((vbl_irq & ~vbl_irq_d) & INTEN[3]) begin
      INTFLAG[3]<=1'b1;
`ifdef SIMULATION
      $display("INTFLAG: set VBL (3) due vbl_irq rising edge");
`endif
    end
    if ((qtrsecond_irq & ~qtr_irq_d) & INTEN[4]) begin
      INTFLAG[4]<=1'b1;
`ifdef SIMULATION
      $display("INTFLAG: set QTR (4) due qtrsecond_irq rising edge");
`endif
    end

    // 0 means IRQ in process
    //             VBL           QTRSEC       SECOND      SCAN      DOC (SOUND)   -- needs ADB, SCC, SLOT
    INTFLAG[0] <= INTFLAG[3] | INTFLAG[4] | VGCINT[6] | VGCINT[7] | snd_irq;
    /*
     enum irq_sources
     {
     IRQS_DOC        = 0, // sound
     IRQS_SCAN       = 1,
     IRQS_ADB        = 2,
     IRQS_VBL        = 3,
     IRQS_SECOND     = 4,
     IRQS_QTRSEC     = 5,
     IRQS_SLOT       = 6,
     IRQS_SCC        = 7
     };
     */

  end
  wire cpu_irq =  (VGCINT[6]&VGCINT[2])|(VGCINT[5]&VGCINT[1])|(INTEN[3]&INTFLAG[3])|(INTEN[4]&INTFLAG[4])|snd_irq;

`ifdef SIMULATION
  // Trace sound IRQ line transitions and cpu_irq composition to verify behavior
  reg snd_irq_d;
  reg cpu_irq_d;
  reg [15:0] cpu_irq_high_cnt;
  always @(posedge CLK_14M) begin
    snd_irq_d <= snd_irq;
    cpu_irq_d <= cpu_irq;
    if (cpu_irq) cpu_irq_high_cnt <= cpu_irq_high_cnt + 16'd1; else cpu_irq_high_cnt <= 16'd0;
    if (snd_irq != snd_irq_d) begin
      $display("%m: snd_irq %0d -> %0d (VGCINT6&2=%0d VGCINT5&1=%0d INTEN3&F3=%0d INTEN4&F4=%0d)",
               snd_irq_d, snd_irq,
               (VGCINT[6]&VGCINT[2]),
               (VGCINT[5]&VGCINT[1]),
               (INTEN[3]&INTFLAG[3]),
               (INTEN[4]&INTFLAG[4]));
    end
    if (cpu_irq != cpu_irq_d) begin
      $display("%m: cpu_irq %0d -> %0d (v1=%0d v2=%0d v3=%0d v4=%0d snd=%0d)",
               cpu_irq_d, cpu_irq,
               (VGCINT[6]&VGCINT[2]),
               (VGCINT[5]&VGCINT[1]),
               (INTEN[3]&INTFLAG[3]),
               (INTEN[4]&INTFLAG[4]),
               snd_irq);
    end
    // Periodic summary when IRQ stays high too long
    if (cpu_irq_high_cnt == 16'd2000) begin
      $display("%m: cpu_irq stuck high: INTEN=%02h INTFLAG=%02h VGCINT=%02h snd=%0d", INTEN, INTFLAG, VGCINT, snd_irq);
      // Simulation safety valve: clear IIe-style flags to allow progress
      INTFLAG[4:3] <= 2'b00;
    end
  end
`endif


  always @(*)
    begin: aux_ctrl
      aux = 1'b0;
      if ((bank_bef==0 || bank_bef==8'he0) && (addr_bef[15:9] == 7'b0000000 | addr_bef[15:14] == 2'b11))		// Page 00,01,C0-FF
        aux = ALTZP;
      else if ((bank_bef==0 || bank_bef==1 || bank_bef==8'he0 || bank_bef==8'he1) &&  addr_bef[15:10] == 6'b000001)		// Page 04-07
        aux = ((bank_bef==1 || bank_bef==8'he1) || ((bank_bef==0 || bank_bef==8'he0) &&   ( (STORE80 & PAGE2) | ((~STORE80) & ((RAMRD & (cpu_wen)) | (RAMWRT & ~cpu_wen))))));
      else if (addr_bef[15:13] == 3'b001)		// Page 20-3F
        aux = ((bank_bef==1 || bank_bef==8'he1) || ((bank_bef==0 || bank_bef==8'he0) &&    ((STORE80 & PAGE2 & HIRES_MODE) | (((~STORE80) | (~HIRES_MODE)) & ((RAMRD & (cpu_wen)) | (RAMWRT & ~cpu_wen))))));
      else
        aux = ((bank_bef==1 || bank_bef==8'he1) || ((bank_bef==0||bank_bef==8'he0) && ((RAMRD & (cpu_wen)) | (RAMWRT & ~cpu_wen))));
    end
assign     fastram_address = {bank[6:0],addr};
assign     fastram_datatoram = dout;
assign     fastram_dout = fastram_datafromram;
assign     fastram_we = we;

//`define ROM3 1
`ifdef ROM3



rom #(.memfile("rom3/romc.mem")) romc(
  .clock(CLK_14M),
  .address(addr),
  .q(romc_dout),
  .ce(romc_ce)
);
rom #(.memfile("rom3/romd.mem")) romd(
  .clock(CLK_14M),
  .address(addr),
  .q(romd_dout),
  .ce(romd_ce)
);
rom #(.memfile("rom3/rom1.mem")) rom1(
  .clock(CLK_14M),
  .address(addr),
  .q(rom1_dout),
  .ce(rom1_ce)
);

rom #(.memfile("rom3/rom2.mem")) rom2(
  .clock(CLK_14M),
  .address(addr),
  .q(rom2_dout),
  .ce(rom2_ce|slot_internalrom_ce)
);


`else

rom #(.memfile("rom1/rom1.mem")) rom1(
  .clock(CLK_14M),
  .address(addr),
  .q(rom1_dout),
  .ce(rom1_ce)
);

rom #(.memfile("rom1/rom2.mem")) rom2(
  .clock(CLK_14M),
  .address(addr),
  .q(rom2_dout),
  .ce(rom2_ce|slot_internalrom_ce)
);
`endif

//wire slot_ce =  bank == 8'h0 && addr >= 'hc400 && addr < 'hc800 && ~is_internal;
wire slot_ce =  (bank == 8'h0 || bank == 8'h1 || bank == 8'he0 || bank == 8'he1) && addr >= 'hc100 && addr < 'hc800 && ~is_internal && ~inhibit_cxxx;
wire is_internal =   ~SLTROMSEL[addr[10:8]];
wire is_internal_io =   ~SLTROMSEL[addr[6:4]];
//wire slot_internalrom_ce =  bank == 8'h0 && addr >= 'hc400 && addr < 'hc800 && is_internal;
wire slot_internalrom_ce =  (bank == 8'h0 || bank == 8'h1 || bank == 8'he0 || bank == 8'he1) && addr >= 'hc100 && addr < 'hc800 && is_internal && ~inhibit_cxxx;

// try to setup flags for traditional iie style slots
reg [7:0] device_select;
reg [7:0] io_select;
wire [7:0] rom1_dout, rom2_dout, romc_dout, romd_dout;
wire [7:0] fastram_dout;
wire [7:0] slowram_dout;

always @(*)
begin
   device_select=8'h0;
   io_select=8'h0;
   if ((bank == 8'h0 || bank == 8'h1 || bank == 8'he0 || bank == 8'he1) && addr >= 'hc090 && addr < 'hc100 && ~is_internal_io && ~inhibit_cxxx)
   begin
//	   $display("device_select addr[10:8] %x %x ISINTERNAL? ",addr[6:4],din);
          device_select[addr[6:4]]=1'b1;
  end
   if ((bank == 8'h0 || bank == 8'h1 || bank == 8'he0 || bank == 8'he1) && addr >= 'hc100 && addr < 'hc800 && ~is_internal && ~CXROM && ~inhibit_cxxx)
   begin
//	   $display("io_select addr[10:8] %x din %x HDD_DO %x fastclk %x addr %x RD %x",addr[10:8],din,HDD_DO,fast_clk,addr,we);
          io_select[addr[10:8]]=1'b1;
  end
end
`ifdef NOTDEFINED
`ifdef VERILATOR
dpram #(.widthad_a(23),.prefix("fast")) fastram
`else
dpram #(.widthad_a(16)) fastram
`endif
(
        .clock_a(clk_sys),
        .address_a({ bank[6:0], addr }),
        .data_a(dout),
        .q_a(fastram_dout),
        .wren_a(we),
        .ce_a(fastram_ce),
);
`endif

dpram #(.widthad_a(17),.prefix("slow"),.p(" e")) slowram
(
        .clock_a(CLK_14M),
        .address_a({ bank[0], addr }),
        .data_a(dout),
        .q_a(slowram_dout),
        .wren_a(we),
        .ce_a(slowram_ce),

        .clock_b(clk_vid),
        .address_b(video_addr[16:0]),
        .data_b(0),
        .q_b(video_data),
        .wren_b(1'b0)


        //.ce_b(1'b1)
);

wire [9:0] H;
wire [8:0] V;

video_timing video_timing(
.clk_vid(clk_vid),
.ce_pix(ce_pix),
.hsync(HS),
.vsync(VS),
.hblank(HBlank),
.vblank(VBlank),
.hpos(H),
.vpos(V)
);




wire [22:0] video_addr;
wire [7:0] video_data;
wire vbl_irq;
wire scanline_irq;
vgc vgc(
        .CLK_14M(CLK_14M),
        .clk_vid(clk_vid),
        .ce_pix(ce_pix),
        .scanline_irq(scanline_irq),
        .vbl_irq(vbl_irq),
        .H(H),
        .V(V),
        .R(R),
        .G(G),
        .B(B),
        .video_addr(video_addr),
        .video_data(video_data),
        .TEXTCOLOR(TEXTCOLOR),
        .BORDERCOLOR(BORDERCOLOR),
        .HIRES_MODE(HIRES_MODE),
        .ALTCHARSET(ALTCHARSET),
        .EIGHTYCOL(EIGHTYCOL),
        .PAGE2(PAGE2),
        .TEXTG(TEXTG),
        .MIXG(MIXG),
        .NEWVIDEO(NEWVIDEO)
);



wire [7:0] din =
  (io_select[7] == 1'b1 | device_select[7] == 1'b1) ? HDD_DO :
  rom1_ce ? rom1_dout :
  rom2_ce ? rom2_dout :
  romc_ce ? romc_dout :
  romd_ce ? romd_dout :
  slot_internalrom_ce ?  rom2_dout :
  fastram_ce ? fastram_dout :
  slowram_ce ? slowram_dout :
  slot_ce ? slot_dout :
  8'h80;

wire [7:0] slot_dout = HDD_DO;
wire [7:0] HDD_DO;

  wire [7:0] cpu_din = IO ? iwm_strobe ? iwm_dout : io_dout : din;
wire ready_out;

  P65C816 cpu(
              .CLK(CLK_14M),
              .RST_N(~reset),
              .CE(phi2),
              .RDY_IN(~cpu_wait),
              .NMI_N(1'b1),
              .IRQ_N(~cpu_irq),
              .ABORT_N(1'b1),
              .D_IN(cpu_din),
              .D_OUT(cpu_dout),
              .A_OUT(cpu_addr),
              .WE(cpu_wen), // This signal is active low at this point
              .RDY_OUT(ready_out),
              .VPA(cpu_vpa),
              .VDA(cpu_vda),
              .MLB(cpu_mlb),
              .VPB(cpu_vpb)
              );


/*
  always @(posedge CLK_14M)
    begin
      if (phi2)
        begin
          $display("ready_out %x bank %x cpu_addr %x  addr_bus %x cpu_din %x cpu_dout %x cpu_wen %x aux %x LCRAM2 %x RDROM %x LC_WE %x cpu_irq %x akd %x cpu_vpb %x RAMRD %x RDROM %x, iwm_strobe %x iwm_dout %x io_dout %x",ready_out,bank,cpu_addr,addr_bus,cpu_din,cpu_dout,cpu_wen,aux,LCRAM2,RDROM,LC_WE,cpu_irq,key_anykeydown,cpu_vpb,RAMRD,RDROM,iwm_strobe,iwm_dout,io_dout);
          // to debug interrupts:
          //$display("cpu_irq %x vgc7 any %x vgc second %x vgc scanline %x second enable %x scanline enable %x INTEN[4] %x INTEN[3] %x INTFLAG 4 %x INTFLG 3 %x ",cpu_irq,VGCINT[7],VGCINT[6],VGCINT[5],VGCINT[3],VGCINT[2],INTEN[4],INTEN[3],INTFLAG[4],INTFLAG[3]);
        end
    end
*/


`ifdef VERILATOR
  reg [19:0] dbg_pc_counter;
  always @(posedge cpu_vpa or posedge cpu_vda or posedge reset)
    if (reset)
      dbg_pc_counter <= 20'd0;
    else if (cpu_vpa & cpu_vda)
      dbg_pc_counter <= dbg_pc_counter + 20'd1;
`endif

  adb adb(
          .CLK_14M(CLK_14M),
          .cen(phi2),
          .reset(reset),
          .addr(adb_addr),
          .rw(adb_rw),
          .din(adb_din),
          .dout(adb_dout),
          .strobe(adb_strobe)
          );

  prtc prtc(
            .CLK_14M(CLK_14M),
            .cen(phi2),
            .timestamp(timestamp),
            .reset(reset),
            .addr(prtc_addr),
            .din(prtc_din),
            .dout(prtc_dout),
            .onesecond_irq(onesecond_irq),
            .qtrsecond_irq(qtrsecond_irq),
            .rw(prtc_rw),
            .strobe(prtc_strobe)
            );

`ifdef IWMSTUB
  iwm iwm(
          .CLK_14M(CLK_14M),
          .cen(q3_en),
          .reset(reset),
          .addr(iwm_addr),
          .din(iwm_din),
          .dout(iwm_dout),
          .rw(iwm_rw),
          .strobe(iwm_strobe),
          .DISK35(DISK35)
          );
  `else
        iwm_controller iwmc (
      // Global clocks/resets
      .CLK_14M(CLK_14M),
      .CLK_7M_EN(clk_7M_en),
      .Q3(q3_en),
      .PH0(phi0),
      .RESET(reset),
      // Bus interface
      .IO_SELECT(iwm_strobe),
      .DEVICE_SELECT(iwm_strobe),
      .WR_CYCLE(iwm_rw),
      //.ACCESS_STROBE(iwm_strobe),
      .A(iwm_addr),
      .D_IN(iwm_din),
      .D_OUT(iwm_dout),
      // Drive status and control
      .DISK_READY(DISK_READY),
      .DISK35(DISK35),
      .WRITE_PROTECT(floppy_wp),
      // 5.25" Drive 1
      .TRACK1(TRACK1),
      .TRACK1_ADDR(TRACK1_ADDR),
      .TRACK1_DI(TRACK1_DI),
      .TRACK1_DO(TRACK1_DO),
      .TRACK1_WE(TRACK1_WE),
      .TRACK1_BUSY(TRACK1_BUSY),
      // 5.25" Drive 2
      .TRACK2(TRACK2),
      .TRACK2_ADDR(TRACK2_ADDR),
      .TRACK2_DI(TRACK2_DI),
      .TRACK2_DO(TRACK2_DO),
      .TRACK2_WE(TRACK2_WE),
      .TRACK2_BUSY(TRACK2_BUSY),
      // 3.5" not yet wired
      .TRACK3(), .TRACK3_ADDR(), .TRACK3_SIDE(), .TRACK3_DI(), .TRACK3_DO(8'h00), .TRACK3_WE(), .TRACK3_BUSY(1'b0),
      .TRACK4(), .TRACK4_ADDR(), .TRACK4_SIDE(), .TRACK4_DI(), .TRACK4_DO(8'h00), .TRACK4_WE(), .TRACK4_BUSY(1'b0)
  );
  `endif

    // Legacy slot-7 HDD 
    hdd hdd(
        .CLK_14M(CLK_14M),
        .phi0(phi0),
        .IO_SELECT(io_select[7]),
        .DEVICE_SELECT(device_select[7]),
        //.IO_SELECT(1'b0),
        //.DEVICE_SELECT(1'b0),
        .RESET(reset),
        .A(addr),
        .RD(~we),
        .D_IN(dout),
        .D_OUT(HDD_DO),
        .sector(HDD_SECTOR),
        .hdd_read(HDD_READ),
        .hdd_write(HDD_WRITE),
        .hdd_mounted(HDD_MOUNTED),
        .hdd_protect(HDD_PROTECT),
        .ram_addr(HDD_RAM_ADDR),
        .ram_di(HDD_RAM_DI),
        .ram_do(HDD_RAM_DO),
        .ram_we(HDD_RAM_WE)
    );
/*
    // Native SmartPort HDD on Slot 5 ($C0D0–$C0DF), no ROM
    sp_hdd sp_hdd(
        .CLK_14M(CLK_14M),
        .phi0(phi0),
        .IO_SELECT(io_select[5]),
        .DEVICE_SELECT(device_select[5]),
        .RESET(reset),
        .A(addr),
        .RD(~we),
        .D_IN(dout),
        .D_OUT(SP_DO),
        .sector(HDD_SECTOR),
        .hdd_read(HDD_READ),
        .hdd_write(HDD_WRITE),
        .hdd_mounted(HDD_MOUNTED),
        .hdd_protect(HDD_PROTECT),
        .ram_addr(HDD_RAM_ADDR),
        .ram_di(HDD_RAM_DI),
        .ram_do(HDD_RAM_DO),
        .ram_we(HDD_RAM_WE)
    );
*/
  sound snd(
            .CLK_14M(CLK_14M),
            .ph0_en(phi0),
            .reset(reset),
            .select(snd_strobe),
            .wr(snd_rw),
            .host_addr(snd_addr),
            .host_data_in(snd_din),
            .host_data_out(snd_dout),
            .irq(snd_irq)
            );

  wire [6:0] key_keys=key_keys_pressed[6:0];
  wire [7:0] key_keys_pressed;
  wire       key_pressed = key_keys_pressed[7];
  wire       key_anykeydown;
  reg        key_reads;
  keyboard keyboard(
                    .CLK_14M(CLK_14M),
                    .PS2_Key(ps2_key),
                    .reads(key_reads),  // read strobe
                    .reset(reset),
                    .akd(key_anykeydown),
                    .K(key_keys_pressed)
                    );
// Clock divider instance
clock_divider clk_div_inst (
    .clk_14M(CLK_14M),
    .cyareg(CYAREG),
    .bank(bank),
    .addr(addr),
    .shadow(shadow),
    .IO(IO),
    .reset(reset),
    .stretch(1'b0),  // TODO: Connect to VGC stretch signal
    .clk_14M_en(),
    .clk_7M_en(clk_7M_en),
    .ph0_en(ph0_en),
    .ph2_en(ph2_en),
    .q3_en(q3_en),
    .ph0_state()
);
// Map clock enables to Apple IIgs standard names
wire phi2 = ph2_en;
wire phi0 = ph0_en;
wire ph0_en;
wire ph2_en;
wire clk_7M_en;
wire clk_7M = clk_7M_en;
wire q3_en;

endmodule
