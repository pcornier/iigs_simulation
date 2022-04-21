
module iigs(
  input reset,

  input clk_sys,
  input fast_clk, // 2.5
  input slow_clk, // 1

  output [7:0] bank,
  output [15:0] addr,
  output [7:0] dout,
  input [7:0] din,
  output reg [7:0] shadow,
  output reg [7:0] TEXTCOLOR,
  output reg [3:0] BORDERCOLOR,
  output reg [7:0] SLTROMSEL,
  output we
);

wire [23:0] cpu_addr;
wire [7:0] cpu_dout;
wire [23:0] addr_bus;
wire cpu_vpa, cpu_vpb;
wire cpu_vda, cpu_mlb;
wire cpu_we;
reg [7:0] io_dout;
reg [7:0] slot_dout;

assign { bank, addr } = addr_bus;
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

// some fake registers for now
reg [7:0] WVIDEO;
reg [7:0] RDCxROM;
reg [7:0] STATEREG;
reg [7:0] SETINTCxROM;
reg [7:0] CYAREG;
reg [7:0] SOUNDCTL;
reg [7:0] SOUNDDATA;
reg [7:0] DISKREG;
//reg [7:0] SLTROMSEL;
reg [7:0] SOUNDADRL;
reg [7:0] SOUNDADRH;
//reg [7:0] TEXTCOLOR;
reg [7:0] LOWRES;
reg [7:0] SPKR;
reg [7:0] RD80VID;
reg [7:0] DISK35;

wire slot_area = addr[15:0] >= 16'hc100 && addr[15:0] <= 16'hcfff;
wire [3:0] slotid = addr[11:8];

// remap c700 to c500 if slot access and $C02D[7]
//assign addr_bus =
 // slot_area && cpu_addr[15:8] == 8'b11000111 ? { cpu_addr[23:10], ~SLTROMSEL[7], cpu_addr[8:0] } : cpu_addr;
assign addr_bus = cpu_addr;

// from c000 to c0ff only, c100 to cfff are slots or ROM based on $C02D
wire IO = ~shadow[6] && addr[15:8] == 8'b11000000 && (bank == 8'h0 || bank == 8'h1 || bank == 8'he0 || bank == 8'he1);

// driver for io_dout and fake registers
always @(posedge clk_sys) begin
  if (reset) begin
    // dummy values dumped from emulator
    CYAREG <= 8'h80; // motor speed
    STATEREG <=  8'b0000_1001;
    shadow <= 8'b0000_1000;
    SOUNDCTL <= 8'd0;
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
  if (iwm_strobe & cpu_we) begin
    io_dout <= iwm_dout;
  end

  if (IO) begin
    if (~cpu_we)
      // write
      case (addr[11:0])
        12'h010, 12'h026, 12'h027, 12'h070: begin
          adb_addr <= addr[7:0];
          adb_strobe <= 1'b1;
          adb_din <= cpu_dout;
          adb_rw <= 1'b0;
        end
        12'h007: SETINTCxROM <= cpu_dout;
        12'h022: TEXTCOLOR <= cpu_dout;
        12'h029: WVIDEO <= cpu_dout;
	12'h02d: SLTROMSEL <= cpu_dout;
        12'h030: SPKR <= cpu_dout;
        12'h031: DISK35<= cpu_dout & 'hc0;
        12'h033, 12'h034: begin
          prtc_rw <= 1'b0;
          prtc_strobe <= 1'b1;
          prtc_addr <= ~addr[0];
          prtc_din <= cpu_dout;
	  if (~addr[0])
		  BORDERCOLOR=cpu_dout[3:0];
        end
        12'h035: shadow <= cpu_dout;
        12'h03c: SOUNDCTL <= cpu_dout;
        12'h03d: SOUNDDATA <= cpu_dout;
        12'h03e: SOUNDADRL <= cpu_dout;
        12'h03f: SOUNDADRH <= cpu_dout;
        12'h054: $display("TEXTPAGE1 54");
        12'h055: $display("TEXTPAGE2 55");
        12'h056: LOWRES <= cpu_dout;
        // $C068: bit0 stays high during boot sequence, why?
        // if bit0=1 it means that internal ROM at SCx00 is selected
        // does it mean slot cards are not accessible?
        12'h068: STATEREG <= { cpu_dout[7:1], 1'b1 };
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
		$display("IO_WR %x %x",addr[11:0],cpu_dout);
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
        12'h015: io_dout <= RDCxROM;
        12'h01f: io_dout <= RD80VID;
        12'h029: io_dout <= WVIDEO;
        12'h02d: io_dout <= SLTROMSEL;
        12'h030: io_dout <= SPKR;
        12'h031: io_dout <= DISK35;
        12'h033, 12'h034: begin
          prtc_addr <= ~addr[0];
          prtc_rw <= 1'b1;
          prtc_strobe <= 1'b1;
        end
        12'h035: io_dout <= shadow;
        12'h036: io_dout <= CYAREG;
        12'h03c: io_dout <= SOUNDCTL;
        12'h03d: io_dout <= SOUNDDATA;
        12'h03e: io_dout <= SOUNDADRL;
        12'h03f: io_dout <= SOUNDADRH;
        12'h056: io_dout <= LOWRES;
        12'h068: io_dout <= STATEREG;
        12'h071, 12'h072, 12'h073, 12'h074,
        12'h075, 12'h076, 12'h077, 12'h078,
        12'h079, 12'h07a, 12'h07b, 12'h07c,
        12'h07d, 12'h07e, 12'h07f:
          io_dout <= din;
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
		$display("IO_RD %x ",addr[11:0]);
      endcase
  end
end

wire [7:0] cpu_din = IO ? io_dout : din;

P65C816 cpu(
  .CLK(clk_sys),
  .RST_N(~reset),
  .CE(fast_clk),
  .RDY_IN(1'b1),
  .NMI_N(1'b1),
  .IRQ_N(1'b1),
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
		$display("ready_out %x bank %x cpu_addr %x  addr_bus %x cpu_din %x cpu_dout %x cpu_we %x ",ready_out,bank,cpu_addr,addr_bus,cpu_din,cpu_dout,cpu_we);
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
  .rw(prtc_rw),
  .strobe(prtc_strobe)
);

iwm iwm(
  .clk(clk_sys),
  .cen(fast_clk),
  .reset(reset),
  .addr(iwm_addr),
  .din(iwm_din),
  .dout(iwm_dout),
  .rw(iwm_rw),
  .strobe(iwm_strobe),
  .DISK35(DISK35)
);


endmodule

