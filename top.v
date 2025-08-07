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
  wire romc_ce;
  wire romd_ce;
wire inhibit_cxxx;


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
     .romc_ce(romc_ce),
     .romd_ce(romd_ce),
     .VBlank(VBlank),
     .STORE80(STORE80),
     .TEXTCOLOR(TEXTCOLOR),
     .BORDERCOLOR(BORDERCOLOR),
     .HIRES_MODE(HIRES_MODE),
     .ALTCHARSET(ALTCHARSET),
     .EIGHTYCOL(EIGHTYCOL),
     .PAGE2(PAGE2),
     .TEXTG(TEXTG),
     .MIXG(MIXG),
     .NEWVIDEO(NEWVIDEO),
     .MONOCHROME(MONOCHROME),
     .IO(IO),

     .VPB(VPB),
     .SLTROMSEL(SLTROMSEL),
     .CXROM(CXROM),
     .RDROM(RDROM),
     .LC_WE(LC_WE),
     .LCRAM2(LCRAM2),

     .H(H),
     .V(V),

     .ps2_key(ps2_key),

     .inhibit_cxxx(inhibit_cxxx)
     );


wire VPB;

wire CXROM;
wire LC_WE;
wire RDROM;
wire LCRAM2;
wire STORE80;
wire [7:0] TEXTCOLOR;
wire [3:0] BORDERCOLOR;
wire  HIRES_MODE;
wire ALTCHARSET;
wire EIGHTYCOL;
wire  PAGE2;
wire  TEXTG;
wire  MIXG;
wire [7:0] NEWVIDEO;
wire [7:0] MONOCHROME;
wire IO;
wire [7:0] SLTROMSEL;

wire [7:0] rom1_dout, rom2_dout, romc_dout, romd_dout;
wire [7:0] fastram_dout;
wire [7:0] slowram_dout;



//wire slot_ce =  bank == 8'h0 && addr >= 'hc400 && addr < 'hc800 && ~is_internal;
wire slot_ce =  (bank == 8'h0 || bank == 8'h1 || bank == 8'he0 || bank == 8'he1) && addr >= 'hc100 && addr < 'hc800 && ~is_internal && ~inhibit_cxxx;
wire is_internal =   ~SLTROMSEL[addr[10:8]];
wire is_internal_io =   ~SLTROMSEL[addr[6:4]];
//wire slot_internalrom_ce =  bank == 8'h0 && addr >= 'hc400 && addr < 'hc800 && is_internal;
wire slot_internalrom_ce =  (bank == 8'h0 || bank == 8'h1 || bank == 8'he0 || bank == 8'he1) && addr >= 'hc100 && addr < 'hc800 && is_internal && ~inhibit_cxxx;

// try to setup flags for traditional iie style slots
reg [7:0] device_select;
reg [7:0] io_select;


//always @(posedge clk_sys)
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



/*
always @(posedge clk_sys)
begin
        if (fast_clk)
        begin
                $display("bank %x addr %x rom1_ce %x rom2_ce %x fastram_ce %x slot_internalrom_ce %x slowram_ce %x slot_ce %x rom2_dout %x din %x SLOTROMSEL %x is_internal %x CXROM %x shadow %x IO %x io_select[7] %x device_select[7] %x raddr %x",
                        bank,addr,rom1_ce,rom2_ce,fastram_ce,slot_internalrom_ce,slowram_ce,slot_ce,rom2_dout,din,SLTROMSEL,is_internal,CXROM,shadow,IO,io_select[7],device_select[7],raddr);
          $display("we %x Addr %x din %x | HDD_DO %x, rom1_dout %x, rom2_dout %x, fastram_dout %x, slowram_dout %x, slot_dout %x", we, { bank[6:0], raddr }, dout, HDD_DO, rom1_dout, rom2_dout, fastram_dout, slowram_dout, slot_dout);
        end
end
*/


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


`define ROM3 1
`ifdef ROM3

  
  
rom #(.memfile("rom3/romc.mem")) romc(
  .clock(clk_sys),
  .address(addr),
  .q(romc_dout),
  .ce(romc_ce)
);
rom #(.memfile("rom3/romd.mem")) romd(
  .clock(clk_sys),
  .address(addr),
  .q(romd_dout),
  .ce(romd_ce)  
);
rom #(.memfile("rom3/rom1.mem")) rom1(
  .clock(clk_sys),
  .address(addr),
  .q(rom1_dout),
  .ce(rom1_ce)  
);

rom #(.memfile("rom3/rom2.mem")) rom2(
  .clock(clk_sys),
  .address(addr),
  .q(rom2_dout),
  .ce(rom2_ce|slot_internalrom_ce)
);


`else

rom #(.memfile("rom1/rom1.mem")) rom1(
  .clock(clk_sys),
  .address(addr),
  .q(rom1_dout),
  .ce(rom1_ce)
);

rom #(.memfile("rom1/rom2.mem")) rom2(
  .clock(clk_sys),
  .address(addr),
  .q(rom2_dout),
  .ce(rom2_ce|slot_internalrom_ce)
);
`endif

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

reg [31:0] video_data_latch;


dpram_mixed_width slowram (
        .clock_a(clk_sys),
        .address_a({ bank[0], raddr }),
        .data_a(dout),
        .q_a(slowram_dout),
        .wren_a(we),
        .ce_a(slowram_ce),

        .clock_b(clk_vid),
        .address_b(video_addr[16:2]),
        .data_b(0),
        .q_b(video_data_wide),
        .wren_b(1'b0),
	.ce_b(1'b1)
);

reg save;

always @(posedge clk_vid)
begin
        //if (apple_video_rd || vgc_rd)
        if (apple_video_rd)
		save<=1;
	if (save) begin
		save<=0;
		video_data_latch<=video_data_wide;
	end
	   $display("video_addr %x  o(%x) video_data_wide %x (%x) vgc_Rd %x appl_rd %x ",video_addr,video_addr_orig,video_data_wide,video_data_orig ,vgc_rd,apple_video_rd);
end


dpram #(.widthad_a(17),.prefix("slow"),.p(" e")) slowramb
(
        .clock_a(clk_sys),
        .address_a({ bank[0], raddr }),
        .data_a(dout),
        .q_a(slowram_dout_orig),
        .wren_a(we),
        .ce_a(slowram_ce),

        .clock_b(clk_vid),
        .address_b(video_addr[16:2]),
        .data_b(0),
        .q_b(video_data_orig),
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
wire [22:0] video_addr_orig;
wire [7:0] video_data;
wire [31:0] video_data_wide;
wire vbl_irq;

vgc_orig vgc(
        .clk(clk_sys),
        .clk_vid(clk_vid),
        .ce_pix(ce_pix),
        .scanline_irq(scanline_irqa),
        .vbl_irq(vbl_irqa),
        .H(H),
        .V(V),
        .R(Ra),
        .G(Ga),
        .B(Ba),
        .video_addr(video_addr_orig),
        .video_data(video_data_orig),
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
wire vgc_rd,apple_video_rd;
video_top video_top(
        .clk(clk_sys),
        .clk_vid(clk_vid),
        .ce_pix(ce_pix),
        .H(H),
        .V(V),
        .scanline_irq(scanline_irq),
        .vbl_irq(vbl_irq),
        .R(R),
        .G(G),
        .B(B),
        .video_addr(video_addr),
        .video_data(video_data),
        .text_mode(text_mode),
        .mixed_mode(mixed_mode),
        .page2(page2),
        .hires_mode(hires_mode),
        .an3(an3),
        .store80(STORE80),
        .col80(EIGHTYCOL),
        .altchar(ALTCHARSET),
        .text_color(TEXTCOLOR[7:4]),
        .background_color(TEXTCOLOR[3:0]),
        .border_color(BORDERCOLOR),
        .monochrome_mode(MONOCHROME[7]),
        .monochrome_dhires_mode(NEWVIDEO[5]),
        .shrg_mode(NEWVIDEO[7]),
        .apple_video_addr(apple_video_addr),
        .apple_video_bank(apple_video_bank),
        .apple_video_rd(apple_video_rd),
        .apple_video_data(video_data_latch),
        .vgc_address(vgc_address),
        .vgc_rd(vgc_rd),
        .vgc_data(video_data_wide),
        .gs_mode(1'b1)
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
// dpram_mixed_width.v
// This module wraps four 8-bit dpram modules to provide:
// - Port A: 8-bit wide, byte-addressable access
// - Port B: 32-bit wide, word-addressable access
// Both ports see the same underlying memory.

module dpram_mixed_width #(
    parameter BYTE_ADDR_WIDTH = 17,    // Total address width for Port A (byte address)
                                       // e.g., 17 for 128K bytes of memory
    //////////////////parameter string PREFIX = "slowa", // Parameter passed to underlying dpram modules
    parameter string P_PARAM = " e"  // Parameter passed to underlying dpram modules
) (
    // Port A: 8-bit byte-addressable interface
    input  wire clock_a,
    input  wire [BYTE_ADDR_WIDTH-1:0] address_a, // Byte address
    input  wire [7:0] data_a,
    output logic [7:0] q_a,
    input  wire wren_a,
    input  wire ce_a,

    // Port B: 32-bit word-addressable interface
    input  wire clock_b,
    input  wire [BYTE_ADDR_WIDTH-1-2:0] address_b, // Word address (BYTE_ADDR_WIDTH - 2)
                                                 // e.g., 15 bits for 32K words of memory
    input  wire [31:0] data_b,
    output wire [31:0] q_b,
    input  wire wren_b,
    input  wire ce_b
);

    // Calculate the actual address width for the underlying 8-bit dpram modules.
    // This is the word address, as each dpram stores one byte of a 32-bit word.
    localparam WORD_ADDR_WIDTH = BYTE_ADDR_WIDTH - 2;

    // Internal wires for Port A of each dpram instance
    wire [7:0] q_a_ram0, q_a_ram1, q_a_ram2, q_a_ram3;
    wire wren_a_ram0, wren_a_ram1, wren_a_ram2, wren_a_ram3;

    // Internal wires for Port B of each dpram instance
    wire [7:0] q_b_ram0, q_b_ram1, q_b_ram2, q_b_ram3;

    // Decode the byte select from Port A's address.
    // address_a[1:0] determines which of the four 8-bit RAMs (bytes) is accessed.
    wire [1:0] byte_select_a = address_a[1:0];
    // The higher bits of address_a form the word address for the underlying RAMs.
    wire [WORD_ADDR_WIDTH-1:0] word_address_a = address_a[BYTE_ADDR_WIDTH-1:2];

    // Generate individual write enables for Port A of each 8-bit RAM.
    // Only the selected byte's RAM will be written to by Port A, when wren_a and ce_a are active.
    assign wren_a_ram0 = wren_a & ce_a & (byte_select_a == 2'b00);
    assign wren_a_ram1 = wren_a & ce_a & (byte_select_a == 2'b01);
    assign wren_a_ram2 = wren_a & ce_a & (byte_select_a == 2'b10);
    assign wren_a_ram3 = wren_a & ce_a & (byte_select_a == 2'b11);

    // Instantiate four 8-bit dpram modules.
    // Each instance handles one byte (8 bits) of the 32-bit data bus.
    // Port A of each RAM is used for byte-level access.
    // Port B of each RAM is used for 32-bit word-level access.

    // RAM 0: Handles byte 0 (Least Significant Byte: data_b[7:0] and q_b[7:0])
    dpram #(.widthad_a(WORD_ADDR_WIDTH), .prefix("slow0"), .p(" e")) ram0 (
        .clock_a(clock_a),
        .address_a(word_address_a), // Word address for Port A
        .data_a(data_a),            // data_a is always connected, but wren_a_ram0 controls write
        .q_a(q_a_ram0),
        .wren_a(wren_a_ram0),       // Specific write enable for this RAM's Port A
        .ce_a(ce_a),                // ce_a is common for all Port A accesses

        .clock_b(clock_b),
        .address_b(address_b),      // Word address for Port B
        .data_b(data_b[7:0]),       // Connect to the least significant 8 bits of 32-bit data_b
        .q_b(q_b_ram0),
        .wren_b(wren_b)            // Common write enable for Port B
        //.ce_b(ce_b)                 // Common chip enable for Port B
    );

    // RAM 1: Handles byte 1 (data_b[15:8] and q_b[15:8])
    dpram #(.widthad_a(WORD_ADDR_WIDTH), .prefix("slow1"), .p(" e")) ram1 (
        .clock_a(clock_a),
        .address_a(word_address_a),
        .data_a(data_a),
        .q_a(q_a_ram1),
        .wren_a(wren_a_ram1),
        .ce_a(ce_a),

        .clock_b(clock_b),
        .address_b(address_b),
        .data_b(data_b[15:8]),
        .q_b(q_b_ram1),
        .wren_b(wren_b)
        //.ce_b(ce_b)
    );

    // RAM 2: Handles byte 2 (data_b[23:16] and q_b[23:16])
    dpram #(.widthad_a(WORD_ADDR_WIDTH), .prefix("slow2"), .p(" e")) ram2 (
        .clock_a(clock_a),
        .address_a(word_address_a),
        .data_a(data_a),
        .q_a(q_a_ram2),
        .wren_a(wren_a_ram2),
        .ce_a(ce_a),

        .clock_b(clock_b),
        .address_b(address_b),
        .data_b(data_b[23:16]),
        .q_b(q_b_ram2),
        .wren_b(wren_b)
        //.ce_b(ce_b)
    );

    // RAM 3: Handles byte 3 (Most Significant Byte: data_b[31:24] and q_b[31:24])
    dpram #(.widthad_a(WORD_ADDR_WIDTH), .prefix("slow3"), .p(" e")) ram3 (
        .clock_a(clock_a),
        .address_a(word_address_a),
        .data_a(data_a),
        .q_a(q_a_ram3),
        .wren_a(wren_a_ram3),
        .ce_a(ce_a),

        .clock_b(clock_b),
        .address_b(address_b),
        .data_b(data_b[31:24]),
        .q_b(q_b_ram3),
        .wren_b(wren_b)
        //.ce_b(ce_b)
    );

    // Multiplex the 8-bit outputs from Port A of each RAM to form the q_a output.
    // This selects the correct byte based on address_a[1:0].
    always @(*) begin
        case (byte_select_a)
            2'b00: q_a = q_a_ram0;
            2'b01: q_a = q_a_ram1;
            2'b10: q_a = q_a_ram2;
            2'b11: q_a = q_a_ram3;
            default: q_a = 8'hXX; // Should not happen with 2-bit select, but good practice
        endcase
    end

    // Concatenate the 8-bit outputs from Port B of each RAM to form the 32-bit q_b output.
    //assign q_b = {q_b_ram3, q_b_ram2, q_b_ram1, q_b_ram0};
    assign q_b = {q_b_ram3, q_b_ram2, q_b_ram1, q_b_ram0};
    //assign q_b = {q_b_ram0, q_b_ram1, q_b_ram2, q_b_ram3};


endmodule
