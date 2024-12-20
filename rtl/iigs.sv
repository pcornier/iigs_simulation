module iigs
  (
   input              reset,

   input              clk_sys,
   input              fast_clk, // 2.5
   input              fast_clk_delayed, // 2.5
   input              slow_clk, // 1
   input              cpu_wait,
   input [32:0]       timestamp,

   input              scanline_irq,
   input              vbl_irq,

   output [7:0]       bank,
   output [15:0]      addr,
   output [7:0]       dout,
   input [7:0]        din,
   output logic       slowram_ce,
   output logic       fastram_ce,
   output logic       rom1_ce,
   output logic       rom2_ce,
   output logic [7:0] shadow/*verilator public_flat*/,
   output logic [7:0] TEXTCOLOR,
   output logic [3:0] BORDERCOLOR,
   output logic [7:0] SLTROMSEL,
   output             CXROM,
   output logic       RDROM,
   output logic       LC_WE,
   output logic       LCRAM2,
  //output logic /*verilator public_flat*/,
   output logic       PAGE2/*verilator public_flat*/,
   output logic       TEXTG/*verilator public_flat*/,
   output logic       MIXG/*verilator public_flat*/,
   output logic       HIRES_MODE/*verilator public_flat*/,
   output logic       ALTCHARSET/*verilator public_flat*/,
   output logic       EIGHTYCOL/*verilator public_flat*/,
   output logic [7:0] NEWVIDEO/*verilator public_flat*/,
   output             IO/*verilator public_flat*/,
   output             we,
   output             VPB,
   input              VBlank,
   input [9:0]        H,
   input [8:0]        V,

   input [10:0]       ps2_key,

   output             inhibit_cxxx
);

`ifdef VERILATOR
  //parameter RAMSIZE = 127; // 16x64k = 1MB, max = 127x64k = 8MB
    parameter RAMSIZE = 20; // 16x64k = 1MB, max = 127x64k = 8MB
`else
  parameter RAMSIZE = 20; // 16x64k = 1MB, max = 127x64k = 8MB
  //parameter RAMSIZE = 127; // 16x64k = 1MB, max = 127x64k = 8MB
`endif

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

  logic [7:0]         adb_din;
  logic [7:0]         adb_dout;
  logic [7:0]         adb_addr;
  logic               adb_rw, adb_strobe;

  logic [7:0]         iwm_din;
  logic [7:0]         iwm_dout;
  logic [7:0]         iwm_addr;
  logic               iwm_rw, iwm_strobe;

  logic [7:0]         snd_din;
  logic [7:0]         snd_dout;
  logic [1:0]         snd_addr;
  logic               snd_rw, snd_strobe;

  logic               aux;

  // some fake registers for now
  //logic [7:0] NEWVIDEO;
  logic [7:0]         STATEREG;
  logic [7:0]         CYAREG;
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

  assign inhibit_cxxx = lcram2_sel | ((bank == 8'h0 | bank == 8'h1) & shadow[6]);

// from c000 to c0ff only, c100 to cfff are slots or ROM based on $C02D
//wire IO = ~shadow[6] && addr[15:8] == 8'hc0 && (bank == 8'h0 || bank == 8'h1 || bank == 8'he0 || bank == 8'he1);
//assign IO =  /*~RAMRD & ~RAMWRT &*/ ~EXTERNAL_IO &  ((~shadow[6] & addr[15:8] == 8'hC0) | (shadow[6] & addr[15:13] == 3'b110)) & (bank == 8'h0 | bank == 8'h1 | bank == 8'he0 | bank == 8'he1);
  assign IO =  /*~RAMRD & ~RAMWRT &*/ ~EXTERNAL_IO &  (~shadow[6] & cpu_addr[15:8] == 8'hC0)  & (bank == 8'h0 | bank == 8'h1 | bank == 8'he0 | bank == 8'he1);

  assign { bank_bef, addr_bef } = cpu_addr;

  always_comb begin
    lcram2_sel = 0;
    if ((bank_bef == 'he0  || bank_bef == 8'he1) && addr_bef >= 'hd000 && addr_bef <='hdfff && LCRAM2 && RDROM  )
      begin
        lcram2_sel = 1;
        if (aux && bank_bef==8'he0)
          addr_bus = addr_bef- 'h1000 + 'h10000;
        else
          addr_bus = {bank_bef,16'h0} + addr_bef- 'h1000;
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
    else  if ((bank == 8'h00 || bank == 8'h01) && ~IO && shadow[6] && addr >= 'hc000 && addr <= 'hffff )
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

  assign rom1_ce = bank == 8'hfe;
  assign rom2_ce = bank == 8'hff ||
                   (bank == 8'h0 & addr >= 16'hd000 & addr <= 16'hdfff && (RDROM|~VPB)) ||
                   (bank == 8'h0 & addr >= 16'hc000 & addr <= 16'hcfff && (RDROM|~VPB)) ||
                   (bank == 8'h0 & addr >= 16'he000 &                     (RDROM|~VPB)) ||
                   (bank == 8'h0 & addr >= 16'hc070 & addr <= 16'hc07f);

  // driver for io_dout and fake registers
  always_ff @(posedge clk_sys) begin
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
    adb_strobe <= 1'b0;
    if (adb_strobe & cpu_wen) begin
      io_dout <= adb_dout;
    end

    prtc_strobe <= 1'b0;
    if (prtc_strobe & cpu_wen) begin
      io_dout <= prtc_dout;
    end

    iwm_strobe <= 1'b0;
    if (iwm_strobe & cpu_wen /*& fast_clk*/) begin
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
            12'h031: DISK35<= cpu_dout & 8'hc0;
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
            //12'h038: ; // SCC B
            //12'h039: ; // SCC A
            12'h03c, 12'h03d, 12'h03e, 12'h03f: begin
              snd_rw <= 1'b1;
              snd_strobe <= 1'b1;
              snd_addr <= addr[1:0];
              snd_din <= cpu_dout;
            end
            12'h041: begin $display("INTEN: %x %x",INTEN,cpu_dout); INTEN <= {INTEN[7:5],cpu_dout[4:0]}; end
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

            12'h038: begin $display("SCCB READ");io_dout <=0; end// SERIAL B
            12'h039: begin $display("SCCA READ");io_dout <=0; end// SERIAL A

            12'h03c, 12'h03d, 12'h03e, 12'h03f: begin
              snd_addr <= addr[1:0];
              snd_rw <= 1'b0;
              snd_strobe <= 1'b1;
            end
            12'h041: begin $display("read INTEN %x",INTEN);io_dout <= INTEN;end
            12'h042: $display("**++UNIMPLEMENTEDMEGAIIINTERRUPT");
            //12'h046: io_dout <=  {C046VAL[7], C046VAL[7], C046VAL[6:0]};
            12'h046: io_dout <= INTFLAG;
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
                  if (fast_clk_delayed) begin
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
                  if (fast_clk_delayed) begin
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
                  if (fast_clk_delayed) begin
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
                  if (fast_clk_delayed) begin
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
                  $display("ex IO_RD %x ",addr[11:0]);
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
      if (VGCINT[1]) // if it is enabled, set the bit
        begin
          $display("firing scanline");
          VGCINT[7]<=1'b1;
        end
    end
    if (onesecond_irq & VGCINT[2]) begin
      VGCINT[6]<=1'b1;
      VGCINT[7]<=1'b1;
    end

    if (vbl_irq & INTEN[3]) begin
      INTFLAG[3]<=1'b1;
    end
    if (qtrsecond_irq& INTEN[4]) begin
      INTFLAG[4]<=1'b1;
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


  always @(*)
    begin: aux_ctrl
      aux = 1'b0;
      if ((bank_bef==0 || bank_bef==8'he0) && (addr_bef[15:9] == 7'b0000000 | addr_bef[15:14] == 2'b11))		// Page 00,01,C0-FF
        aux = ALTZP;
      else if ((bank_bef==0 || bank_bef==8'he0) &&  addr_bef[15:10] == 6'b000001)		// Page 04-07
        aux = ((bank_bef==0 || bank_bef==8'he0) &&   ( (STORE80 & PAGE2) | ((~STORE80) & ((RAMRD & (cpu_wen)) | (RAMWRT & ~cpu_wen)))));
      else if (addr_bef[15:13] == 3'b001)		// Page 20-3F
        aux =((bank_bef==0 || bank_bef==8'he0) &&    ((STORE80 & PAGE2 & HIRES_MODE) | (((~STORE80) | (~HIRES_MODE)) & ((RAMRD & (cpu_wen)) | (RAMWRT & ~cpu_wen)))));
      else
        aux = ((bank_bef==0||bank_bef==8'he0) && ((RAMRD & (cpu_wen)) | (RAMWRT & ~cpu_wen)));
    end


  wire [7:0] cpu_din = IO ? iwm_strobe ? iwm_dout : io_dout : din;

  P65C816 cpu(
              .CLK(clk_sys),
              .RST_N(~reset),
              .CE(fast_clk),
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



  always @(posedge clk_sys)
    begin
      if (fast_clk)
        begin
          $display("ready_out %x bank %x cpu_addr %x  addr_bus %x cpu_din %x cpu_dout %x cpu_wen %x aux %x LCRAM2 %x RDROM %x LC_WE %x cpu_irq %x akd %x cpu_vpb %x RAMRD %x RDROM %x, iwm_strobe %x iwm_dout %x io_dout %x",ready_out,bank,cpu_addr,addr_bus,cpu_din,cpu_dout,cpu_wen,aux,LCRAM2,RDROM,LC_WE,cpu_irq,key_anykeydown,cpu_vpb,RAMRD,RDROM,iwm_strobe,iwm_dout,io_dout);
          // to debug interrupts:
          //$display("cpu_irq %x vgc7 any %x vgc second %x vgc scanline %x second enable %x scanline enable %x INTEN[4] %x INTEN[3] %x INTFLAG 4 %x INTFLG 3 %x ",cpu_irq,VGCINT[7],VGCINT[6],VGCINT[5],VGCINT[3],VGCINT[2],INTEN[4],INTEN[3],INTFLAG[4],INTFLAG[3]);
        end
    end


`ifdef VERILATOR
  reg [19:0] dbg_pc_counter;
  always @(posedge cpu_vpa or posedge cpu_vda or posedge reset)
    if (reset)
      dbg_pc_counter <= 20'd0;
    else if (cpu_vpa & cpu_vda)
      dbg_pc_counter <= dbg_pc_counter + 20'd1;
`endif

  adb adb(
          .clk(clk_sys),
          .cen(fast_clk),
          .reset(reset),
          .addr(adb_addr),
          .rw(adb_rw),
          .din(adb_din),
          .dout(adb_dout),
          .strobe(adb_strobe)
          );

  prtc prtc(
            .clk(clk_sys),
            .cen(fast_clk),
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

  iwm iwm(
          .clk(clk_sys),
          .cen(fast_clk_delayed),
          .reset(reset),
          .addr(iwm_addr),
          .din(iwm_din),
          .dout(iwm_dout),
          .rw(iwm_rw),
          .strobe(iwm_strobe),
          .DISK35(DISK35)
          );

  sound snd(
            .clk(clk_sys),
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
                    .CLK_14M(clk_sys),
                    .PS2_Key(ps2_key),
                    .reads(key_reads),  // read strobe
                    .reset(reset),
                    .akd(key_anykeydown),
                    .K(key_keys_pressed)
                    );

endmodule
