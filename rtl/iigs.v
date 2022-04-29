
module iigs(
  input reset,

  input clk_sys,
  input fast_clk, // 2.5
  input fast_clk_delayed, // 2.5
  input slow_clk, // 1
  input cpu_wait, 

  input scanline_irq,
  input vbl_irq,
	
  output [7:0] bank,
  output [15:0] addr,
  output [7:0] dout,
  input [7:0] din,
  output reg [7:0] shadow/*verilator public_flat*/,
  output reg [7:0] TEXTCOLOR,
  output reg [3:0] BORDERCOLOR,
  output reg [7:0] SLTROMSEL,
  output   CXROM,
  output reg RDROM,
  output reg LC_WE,
  output reg LCRAM2,
  //output reg /*verilator public_flat*/,
  output reg PAGE2/*verilator public_flat*/,
  output reg TEXTG/*verilator public_flat*/,
  output reg MIXG/*verilator public_flat*/,
  output reg HIRES_MODE/*verilator public_flat*/,
  output reg [7:0] NEWVIDEO/*verilator public_flat*/,
  output IO/*verilator public_flat*/,
  output we,

  input VBlank,
  input[9:0] H,
  input[8:0] V

);
  wire [7:0] bank_bef;
  wire [15:0] addr_bef;

assign CXROM=INTCXROM;
wire [23:0] cpu_addr;
wire [7:0] cpu_dout;
reg [23:0] addr_bus;
wire cpu_vpa, cpu_vpb;
wire cpu_vda, cpu_mlb;
wire cpu_we;
reg [7:0] io_dout;
reg [7:0] slot_dout;

wire onesecond_irq;
wire qtrsecond_irq;

assign { bank, addr } = addr_bus;
assign { bank_bef, addr_bef } = cpu_addr;
assign dout = cpu_dout;
assign we = cpu_we;
wire valid = cpu_vpa | cpu_vda;

reg [7:0] prtc_din;
wire [7:0] prtc_dout;
reg prtc_addr;
reg prtc_rw, prtc_strobe;

reg [7:0] adb_din;
wire [7:0] adb_dout;
reg [7:0] adb_addr;
reg adb_rw, adb_strobe;

reg [7:0] iwm_din;
wire [7:0] iwm_dout;
reg [7:0] iwm_addr;
reg iwm_rw, iwm_strobe;


reg aux;

// some fake registers for now
//reg [7:0] NEWVIDEO;
reg [7:0] STATEREG;
reg [7:0] CYAREG;
reg [7:0] SOUNDCTL;
reg [7:0] SOUNDDATA;
reg [7:0] DISKREG;
//reg [7:0] SLTROMSEL;
reg [7:0] SOUNDADRL;
reg [7:0] SOUNDADRH;
//reg [7:0] TEXTCOLOR;
//reg ;
reg [7:0] SPKR;
reg [7:0] DISK35;
reg [7:0] C02BVAL;

reg [7:0] VGCINT; //23
reg [7:0] INTEN; //41 
reg [7:0] INTFLAG; // 46, 47  AJS TODO

reg STORE80;
reg RAMRD;
reg RAMWRT;
reg INTCXROM;
reg ALTZP;
reg SLOTC3ROM;
reg EIGHTYCOL;
reg ALTCHARSET;
//reg PAGE2;
reg [7:0] MONOCHROME;
//reg RDROM;
//reg LCRAM2;
//reg LC_WE;
reg ROMBANK;


//reg TEXTG;
//reg MIXG;


wire slot_area = addr[15:0] >= 16'hc100 && addr[15:0] <= 16'hcfff;
wire [3:0] slotid = addr[11:8];

// remap c700 to c500 if slot access and $C02D[7]
//assign addr_bus =
 // slot_area && cpu_addr[15:8] == 8'b11000111 ? { cpu_addr[23:10], ~SLTROMSEL[7], cpu_addr[8:0] } : cpu_addr;

wire is_internal_io =   ~SLTROMSEL[addr[6:4]];

wire EXTERNAL_IO =    ((bank == 8'h0 || bank == 8'h1 || bank == 8'he0 || bank == 8'he1) && addr >= 'hc090 && addr < 'hc100 && ~is_internal_io);



// from c000 to c0ff only, c100 to cfff are slots or ROM based on $C02D
//wire IO = ~shadow[6] && addr[15:8] == 8'hc0 && (bank == 8'h0 || bank == 8'h1 || bank == 8'he0 || bank == 8'he1);
assign IO = ~EXTERNAL_IO &  ((~shadow[6] & addr[15:8] == 8'hC0) | (shadow[6] & addr[15:13] == 3'b110)) & (bank == 8'h0 | bank == 8'h1 | bank == 8'he0 | bank == 8'he1);

assign { bank_bef, addr_bef } = cpu_addr;

always @(*) begin

	if ((bank_bef == 'h00  || bank_bef == 8'h1 || bank_bef == 8'he0 || bank_bef == 8'he1) && addr_bef >= 'hd000 && addr_bef <='hdfff && LCRAM2 && ~RDROM) 
		addr_bus = addr_bef- 'h1000;
	else
		addr_bus = cpu_addr;
	/*RDROM <= 1'b1;
	LCRAM2 <= 1'b1;
	LC_WE <= 1'b1;
	*/
end

// driver for io_dout and fake registers
always @(posedge clk_sys) begin
  if (reset) begin
    // dummy values dumped from emulator
    CYAREG <= 8'h80; // motor speed
    STATEREG <=  8'b0000_1001;
    shadow <= 8'b0000_1000;
    SOUNDCTL <= 8'd0;
    NEWVIDEO <= 8'h41;
    C02BVAL <= 8'h08;

    // FROM GSPLUS
    INTCXROM<=1'b1;
    RDROM<=1'b1;
    LCRAM2<=1'b1;
  end

  adb_strobe <= 1'b0;
  if (adb_strobe & cpu_we) begin
    io_dout <= adb_dout;
  end

  prtc_strobe <= 1'b0;
  if (prtc_strobe & cpu_we) begin
    io_dout <= prtc_dout;
  end

  iwm_strobe <= 1'b0;
  if (iwm_strobe & cpu_we /*& fast_clk*/) begin
$display("read_iwm %x ret: %x GC036: %x (addr %x) cpu_addr(%x)",addr[11:0],iwm_dout,CYAREG,addr,cpu_addr);
    io_dout <= iwm_dout;
  end

  if (IO) begin
    if (~cpu_we)
      // write
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
          adb_addr <= addr[7:0];
          adb_strobe <= 1'b1;
          adb_din <= cpu_dout;
          adb_rw <= 1'b0;
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
        12'h03c: SOUNDCTL <= cpu_dout;
        12'h03d: SOUNDDATA <= cpu_dout;
        12'h03e: SOUNDADRL <= cpu_dout;
        12'h03f: SOUNDADRH <= cpu_dout;
	12'h041: begin $display("INTEN: %x %x",INTEN,cpu_dout); INTEN <= {INTEN[7:5],cpu_dout[4:0]}; end
        12'h042: $display("**++UNIMPLEMENTEDMEGAIIINTERRUPT"); 
	12'h047: begin INTFLAG[4:3]<=2'b00; end // clear the interrupts
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
	12'h068: begin $display("** R68: %x  ALTZP %x PAGE2 %x RAMRD %x RAMWRT %x RDROM %x LCRAM2 %x ROMBANK %x INTCXROM %x ",cpu_dout,cpu_dout[7],cpu_dout[6],cpu_dout[5],cpu_dout[4],cpu_dout[3],cpu_dout[2],cpu_dout[1],cpu_dout[0]); {ALTZP,PAGE2,RAMRD,RAMWRT,RDROM,LCRAM2,ROMBANK,INTCXROM} <= {cpu_dout[7:4],~cpu_dout[3],cpu_dout[2:0]}; end


	12'h080,	// Read RAM bank 2 no write
	12'h084:	// Read bank 2 no write
		begin
			RDROM <= 1'b0;
			LCRAM2 <= 1'b1;
			LC_WE <= 1'b0;
		end
	12'h081,	// Read ROM write RAM bank 2 (RR)
	12'h085:
		begin
			RDROM <= 1'b1;
			LCRAM2 <= 1'b1;
			LC_WE <= 1'b1;
		end
	12'h082,	// Read ROM no write
	12'h086:
		begin
			RDROM <= 1'b1;
			LCRAM2 <= 1'b0;
			LC_WE <= 1'b0;
		end
	12'h083,	// Read bank 2 write bank 2(RR)
	12'h087:
		begin
			RDROM <= 1'b0;
			LCRAM2 <= 1'b1;
			LC_WE <= 1'b1;
		end
	12'h088,
	12'h08C:
		begin
			RDROM <= 1'b0;
			LCRAM2 <= 1'b0;
			LC_WE <= 1'b0;
		end
	12'h089,
	12'h08D:
		begin
			RDROM <= 1'b1;
			LCRAM2 <= 1'b0;
			LC_WE <= 1'b1;
		end
	12'h08A,
	12'h08E:
		begin
			RDROM <= 1'b1;
			LCRAM2 <= 1'b0;
			LC_WE <= 1'b0;
		end
	12'h08B,
        12'h08F:
		begin
			RDROM <= 1'b0;
			LCRAM2 <= 1'b0;
			LC_WE <= 1'b1;
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
    else
      // read
      case (addr[11:0])
        12'h000, 12'h010, 12'h024, 12'h025,
        12'h026, 12'h027, 12'h044, 12'h045,
        12'h061, 12'h062, 12'h064, 12'h065,
        12'h066, 12'h067, 12'h070: begin
          adb_addr <= addr[7:0];
          adb_strobe <= 1'b1;
          adb_rw <= 1'b1;
        end
	
	12'h002: begin $display("**RAMRD %x",0); RAMRD<= 1'b0 ; end
	12'h003: begin $display("**RAMRD %x",1); RAMRD<= 1'b1 ; end
	12'h004: begin $display("**RAMWRT %x",0); RAMWRT<= 1'b0 ; end
	12'h005: begin $display("**RAMWRT %x",1); RAMWRT<= 1'b1 ; end

	12'h011: if(LCRAM2) io_dout<='h80; else io_dout<='h00;
	12'h012: if(RDROM) io_dout<='h80; else io_dout<='h00;
	12'h013: if(RAMRD) io_dout<='h80; else io_dout<='h00;
	12'h014: if(RAMWRT) io_dout<='h80; else io_dout<='h00;
	12'h015: begin $display("read INTCXROM %x ",INTCXROM); if(INTCXROM) io_dout<='h80; else io_dout<='h00;end
	12'h016: if(ALTZP) io_dout<='h80; else io_dout<='h00;
	12'h017: if(SLOTC3ROM) io_dout<='h80; else io_dout<='h00;
	12'h018: if(STORE80) io_dout<='h80; else io_dout<='h00;
	12'h019: if(VBlank) io_dout<='h00; else io_dout<='h80;
	12'h01a: if(TEXTG) io_dout<='h80; else io_dout<='h00;
	12'h01b: if(MIXG) io_dout<='h80; else io_dout<='h00;
	12'h01c: if(PAGE2) io_dout<='h80; else io_dout<='h00;
	12'h01d: if(~HIRES_MODE) io_dout<='h80; else io_dout<='h00;
	12'h01e: if(ALTCHARSET) io_dout<='h80; else io_dout<='h00;
        12'h01f: if(EIGHTYCOL) io_dout <= 'h80; else io_dout<='h00;

        12'h022: io_dout <= TEXTCOLOR;
	12'h023: begin $display("READ VGCINT %x",VGCINT);io_dout <= VGCINT; end /* vgc int */

        //12'h028: $display("**++UNIMPLEMENTEDROMBANK (28)"); 
	12'h028: begin ROMBANK <= ~ROMBANK; $display("**++UNIMPLEMENTEDROMBANK %x",~ROMBANK);  end
        12'h029: io_dout <= NEWVIDEO;
        12'h02a: io_dout <= 'h0; // from gsplus
        12'h02b: io_dout <= C02BVAL; // from gsplus
        12'h02c: io_dout <= 'h0; // from gsplus
        12'h02d: io_dout <= SLTROMSEL;
        //12'h02e:  /* vertcount */
        //12'h02f:  /* horizcount */
        12'h030: io_dout <= SPKR;
        12'h031: io_dout <= DISK35;
        //12'h032: io_dout <= VGCINT; can you read this??
        12'h033, 12'h034: begin
          prtc_addr <= ~addr[0];
          prtc_rw <= 1'b1;
          prtc_strobe <= 1'b1;
        end
        12'h035: io_dout <= shadow;
	12'h036: begin $display("__CYAREG %x",CYAREG);io_dout<=CYAREG; end
        12'h037: io_dout <= 'h0; // from gsplus 
        12'h03c: io_dout <= SOUNDCTL;
        12'h03d: io_dout <= SOUNDDATA;
        12'h03e: io_dout <= SOUNDADRL;
        12'h03f: io_dout <= SOUNDADRH;
	12'h041: begin $display("read INTEN %x",INTEN);io_dout <= INTEN;end
        12'h042: $display("**++UNIMPLEMENTEDMEGAIIINTERRUPT"); 
        //12'h046: io_dout <=  {C046VAL[7], C046VAL[7], C046VAL[6:0]};
	//12'h047: begin io_dout <= 'h0; C046VAL &= 'he7; end// some kind of interrupt thing
	12'h047: begin $display("INTFLAG CLEAR INTERRUPTS"); INTFLAG[4:3]<=2'b00; end // clear the interrupts
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
        12'h068: io_dout <= {ALTZP,PAGE2,RAMRD,RAMWRT,~RDROM,LCRAM2,ROMBANK,INTCXROM};
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
			RDROM <= 1'b0;
			LCRAM2 <= 1'b1;
			LC_WE <= 1'b0;
		end
	12'h081,	// Read ROM write RAM bank 2 (RR)
	12'h085:
		begin
			RDROM <= 1'b1;
			LCRAM2 <= 1'b1;
			LC_WE <= 1'b1;
		end
	12'h082,	// Read ROM no write
	12'h086:
		begin
			RDROM <= 1'b1;
			LCRAM2 <= 1'b0;
			LC_WE <= 1'b0;
		end
	12'h083,	// Read bank 2 write bank 2(RR)
	12'h087:
		begin
			RDROM <= 1'b0;
			LCRAM2 <= 1'b1;
			LC_WE <= 1'b1;
		end
	12'h088,
	12'h08C:
		begin
			RDROM <= 1'b0;
			LCRAM2 <= 1'b0;
			LC_WE <= 1'b0;
		end
	12'h089,
	12'h08D:
		begin
			RDROM <= 1'b1;
			LCRAM2 <= 1'b0;
			LC_WE <= 1'b1;
		end
	12'h08A,
	12'h08E:
		begin
			RDROM <= 1'b1;
			LCRAM2 <= 1'b0;
			LC_WE <= 1'b0;
		end
	12'h08B,
        12'h08F:
		begin
			RDROM <= 1'b0;
			LCRAM2 <= 1'b0;
			LC_WE <= 1'b1;
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
//reg [7:0] INTEN; //41 
//reg [7:0] INTFLAG; // 47  AJS TODO
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

end
wire cpu_irq =  (VGCINT[6]&VGCINT[2])|(VGCINT[5]&VGCINT[1])|(INTEN[3]&INTFLAG[3])|(INTEN[4]&INTFLAG[4]);


    always @(*)
    begin: aux_ctrl
        aux = 1'b0;
        if ((bank==0 || bank==8'he0) && (addr[15:9] == 7'b0000000 | addr[15:14] == 2'b11))		// Page 00,01,C0-FF
            aux = ALTZP;
        else if ((bank==0 || bank==8'he0) &&  addr[15:10] == 6'b000001)		// Page 04-07
            aux = ((bank==0 || bank==8'he0) &&   ( (STORE80 & PAGE2) | ((~STORE80) & ((RAMRD & (cpu_we)) | (RAMWRT & ~cpu_we)))));
        else if (addr[15:13] == 3'b001)		// Page 20-3F
            aux =((bank==0 || bank==8'he0) &&    ((STORE80 & PAGE2 & HIRES_MODE) | (((~STORE80) | (~HIRES_MODE)) & ((RAMRD & (cpu_we)) | (RAMWRT & ~cpu_we)))));
        else
            aux = ((bank==0||bank==8'he0) && ((RAMRD & (cpu_we)) | (RAMWRT & ~cpu_we)));
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
  .WE(cpu_we),
  .RDY_OUT(ready_out),
  .VPA(cpu_vpa),
  .VDA(cpu_vda),
  .MLB(cpu_mlb),
  .VPB(cpu_vpb)
);


/*
always @(posedge clk_sys)
begin
	if (fast_clk)
	begin
		$display("ready_out %x bank %x cpu_addr %x  addr_bus %x cpu_din %x cpu_dout %x cpu_we %x aux %x LCRAM2 %x RDROM %x LC_WE %x cpu_irq %x",ready_out,bank,cpu_addr,addr_bus,cpu_din,cpu_dout,cpu_we,aux,LCRAM2,RDROM,LC_WE,cpu_irq);
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


endmodule

