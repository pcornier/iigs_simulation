module top(
  input reset,
  input clk_sys,
  input clk_vid,
  input cpu_wait,
  input ce_pix,
  input [32:0] timestamp,

  output fast_clk,
  output fast_clk_delayed,
  output fast_clk_delayed_mem,
  output [7:0] R,
  output [7:0] G,
  output [7:0] B,
  output HBlank,
  output VBlank,
  output HS,
  output VS,
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

  // fastram sdram
  output [22:0] fastram_address,
  output [7:0] fastram_datatoram,
  input  [7:0] fastram_datafromram,
  output       fastram_we,
  output       fastram_ce,

  input [10:0] ps2_key

);




wire [7:0] bank;
wire [7:0] shadow;
wire [15:0] addr;
wire [7:0] dout;
wire we;
reg [2:0] clk_div;
wire slowram_ce;
  wire rom1_ce;
  wire rom2_ce;

always @(posedge clk_sys)
  clk_div <= clk_div + 3'd1;

assign fast_clk = clk_div == 0;
assign fast_clk_delayed = clk_div ==1;
assign fast_clk_delayed_mem = clk_div ==2;

wire scanline_irq;

  iigs core
    (
     .reset(reset),
     .clk_sys(clk_sys),
     .timestamp(timestamp),
     .cpu_wait(cpu_wait),
     .fast_clk(fast_clk_delayed),
     .fast_clk_delayed(fast_clk),
     .scanline_irq(scanline_irq),
     .vbl_irq(vbl_irq),
     .slow_clk(),

     .bank(bank),
     .addr(addr),
     .shadow(shadow),
     .dout(dout),
     .din(din),
     .we(we),
     .slowram_ce(slowram_ce),
     .fastram_ce(fastram_ce),
     .rom1_ce(rom1_ce),
     .rom2_ce(rom2_ce),
     .VBlank(VBlank),
     .TEXTCOLOR(TEXTCOLOR),
     .BORDERCOLOR(BORDERCOLOR),
     .HIRES_MODE(HIRES_MODE),
     .ALTCHARSET(ALTCHARSET),
     .EIGHTYCOL(EIGHTYCOL),
     .PAGE2(PAGE2),
     .TEXTG(TEXTG),
     .MIXG(MIXG),
     .NEWVIDEO(NEWVIDEO),
     .IO(IO),

     .VPB(VPB),
     .SLTROMSEL(SLTROMSEL),
     .CXROM(CXROM),
     .RDROM(RDROM),
     .LC_WE(LC_WE),
     .LCRAM2(LCRAM2),

     .H(H),
     .V(V),

     .ps2_key(ps2_key)
     );


wire VPB;

wire CXROM;
wire LC_WE;
wire RDROM;
wire LCRAM2;
wire [7:0] TEXTCOLOR;
wire [3:0] BORDERCOLOR;
wire  HIRES_MODE;
wire ALTCHARSET;
wire EIGHTYCOL;
wire  PAGE2;
wire  TEXTG;
wire  MIXG;
wire [7:0] NEWVIDEO;
wire IO;
wire [7:0] SLTROMSEL;

wire [7:0] rom1_dout, rom2_dout;
wire [7:0] fastram_dout;
wire [7:0] slowram_dout;



//wire slot_ce =  bank == 8'h0 && addr >= 'hc400 && addr < 'hc800 && ~is_internal;
wire slot_ce =  (bank == 8'h0 || bank == 8'h1 || bank == 8'he0 || bank == 8'he1) && addr >= 'hc100 && addr < 'hc800 && ~is_internal;
wire is_internal =   ~SLTROMSEL[addr[10:8]];
wire is_internal_io =   ~SLTROMSEL[addr[6:4]];
//wire slot_internalrom_ce =  bank == 8'h0 && addr >= 'hc400 && addr < 'hc800 && is_internal;
wire slot_internalrom_ce =  (bank == 8'h0 || bank == 8'h1 || bank == 8'he0 || bank == 8'he1) && addr >= 'hc100 && addr < 'hc800 && is_internal;

// try to setup flags for traditional iie style slots
reg [7:0] device_select;
reg [7:0] io_select;


//always @(posedge clk_sys)
always @(*)
begin
   device_select=8'h0;
   io_select=8'h0;
   if ((bank == 8'h0 || bank == 8'h1 || bank == 8'he0 || bank == 8'he1) && addr >= 'hc090 && addr < 'hc100 && ~is_internal_io)
   begin
//	   $display("device_select addr[10:8] %x %x ISINTERNAL? ",addr[6:4],din);
          device_select[addr[6:4]]=1'b1;
  end
   if ((bank == 8'h0 || bank == 8'h1 || bank == 8'he0 || bank == 8'he1) && addr >= 'hc100 && addr < 'hc800 && ~is_internal && ~CXROM)
   begin
//	   $display("io_select addr[10:8] %x din %x HDD_DO %x fastclk %x addr %x RD %x",addr[10:8],din,HDD_DO,fast_clk,addr,we);
          io_select[addr[10:8]]=1'b1;
  end
end




always @(posedge clk_sys)
begin
        if (fast_clk)
        begin
                $display("bank %x addr %x rom1_ce %x rom2_ce %x fastram_ce %x slot_internalrom_ce %x slowram_ce %x slot_ce %x rom2_dout %x din %x SLOTROMSEL %x is_internal %x CXROM %x shadow %x IO %x io_select[7] %x device_select[7] %x raddr %x",
                        bank,addr,rom1_ce,rom2_ce,fastram_ce,slot_internalrom_ce,slowram_ce,slot_ce,rom2_dout,din,SLTROMSEL,is_internal,CXROM,shadow,IO,io_select[7],device_select[7],raddr);
          $display("we %x Addr %x din %x | HDD_DO %x, rom1_dout %x, rom2_dout %x, fastram_dout %x, slowram_dout %x, slot_dout %x", we, { bank[6:0], raddr }, dout, HDD_DO, rom1_dout, rom2_dout, fastram_dout, slowram_dout, slot_dout);
        end
end



wire [7:0] din =
  (io_select[7] == 1'b1 | device_select[7] == 1'b1) ? HDD_DO :
  rom1_ce ? rom1_dout :
  rom2_ce ? rom2_dout :
  slot_internalrom_ce ?  rom2_dout :
  fastram_ce ? fastram_dout :
  slowram_ce ? slowram_dout :
  slot_ce ? slot_dout :
  8'h80;

wire [7:0] slot_dout = HDD_DO;
wire [7:0] HDD_DO;

rom #(.memfile("rom1.mem")) rom1(
  .clock(clk_sys),
  .address(addr),
  .q(rom1_dout),
  .ce(rom1_ce)
);

rom #(.memfile("rom2.mem")) rom2(
  .clock(clk_sys),
  .address(addr),
  .q(rom2_dout),
  .ce(rom2_ce|slot_internalrom_ce)
);

// 8M 2.5MHz fast ram
/*
fastram fastram(
  .clk(clk_sys),
  .addr({ bank[6:0], addr }),
  .din(dout),
  .dout(fastram_dout),
  .wr(we),
  .ce(fastram_ce)
);
*/

assign     fastram_address = {bank[6:0],raddr};
assign     fastram_datatoram = dout;
assign     fastram_dout = fastram_datafromram;
assign     fastram_we = we;


`ifdef NOTDEFINED
`ifdef VERILATOR
dpram #(.widthad_a(23),.prefix("fast")) fastram
`else
dpram #(.widthad_a(16)) fastram
`endif
(
        .clock_a(clk_sys),
        .address_a({ bank[6:0], raddr }),
        .data_a(dout),
        .q_a(fastram_dout),
        .wren_a(we),
        .ce_a(fastram_ce),
);

`endif

//wire [15:0] raddr = ((bank == 'h00  || bank == 8'h1 || bank == 8'he0 || bank == 8'he1) && addr >= 'hd000 && addr <='hdfff && LCRAM2 ) ?  addr - 'h1000  : addr;
//wire [15:0] raddr = ((bank == 'h00  || bank == 8'he0 ) && addr >= 'hd000 && addr <='hdfff && LCRAM2 ) ?  addr - 'h1000  : addr;
wire [15:0] raddr = addr;

// 128k 1MHz slow ram
// TODO: when 00-01 shadows on E0-E1, there's a copy mechanism 0x->Ex and it is
// supposed to slow down the CPU during memory accesses.
// Does CPU also slow down when it reads or writes on E0-E1?
/*
slowram slowram(
  .clk(clk_sys),
  .addr({ bank[0], addr }),
  .din(dout),
  .dout(slowram_dout),
  .wr(we),
  .ce(slowram_ce)
);
*/
dpram #(.widthad_a(17),.prefix("slow"),.p(" e")) slowram
(
        .clock_a(clk_sys),
        .address_a({ bank[0], raddr }),
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
vgc vgc(
        .clk(clk_sys),
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

    hdd hdd(
        .CLK_14M(clk_sys),
        .PHASE_ZERO(fast_clk),
        .IO_SELECT(io_select[7]),
        .DEVICE_SELECT(device_select[7]),
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

endmodule
