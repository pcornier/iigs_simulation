
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
assign valid = cpu_vpa | cpu_vda;

reg [7:0] prtc_din;
wire [7:0] prtc_dout;
reg prtc_addr;
reg prtc_rw, prtc_strobe;

reg [7:0] adb_din;
wire [7:0] adb_dout;
reg [7:0] adb_addr;
reg adb_rw, adb_strobe;

// some fake registers for now
reg [7:0] WVIDEO;
reg [7:0] RDCxROM;
reg [7:0] STATEREG;
reg [7:0] SETINTCxROM;
reg [7:0] CYAREG;
reg [7:0] SOUNDCTL;
reg [7:0] SOUNDDATA;
reg [7:0] SLTROMSEL;
reg [7:0] SOUNDADRL;
reg [7:0] SOUNDADRH;
reg [7:0] LOWRES;
reg [7:0] SPKR;
reg [7:0] RD80VID;

wire slot_area = addr[15:0] >= 16'hc100 && addr[15:0] <= 16'hcfff;
wire [3:0] slotid = addr[11:8];

// remap c700 to c500 if slot access and $C02D[7]
assign addr_bus =
  slot_area && cpu_addr[15:8] == 8'b11000111 ? { cpu_addr[23:10], ~SLTROMSEL[7], cpu_addr[8:0] } : cpu_addr;

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
        12'h029: WVIDEO <= cpu_dout;
        12'h02d: SLTROMSEL <= cpu_dout;
        12'h030: SPKR <= cpu_dout;
        12'h033, 12'h034: begin
          prtc_rw <= 1'b0;
          prtc_strobe <= 1'b1;
          prtc_addr <= ~addr[0];
          prtc_din <= cpu_dout;
        end
        12'h035: shadow <= cpu_dout;
        12'h03c: SOUNDCTL <= cpu_dout;
        12'h03d: SOUNDDATA <= cpu_dout;
        12'h03e: SOUNDADRL <= cpu_dout;
        12'h03f: SOUNDADRH <= cpu_dout;
        12'h056: LOWRES <= cpu_dout;
        // $C068: bit0 stays high during boot sequence, why?
        // if bit0=1 it means that internal ROM at SCx00 is selected
        // does it mean slot cards are not accessible?
        12'h068: STATEREG <= { cpu_dout[7:1], 1'b1 };
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
  .RDY_OUT(),
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
		$display("cpu_addr %x cpu_din %x cpu_dout %x cpu_we %x ",cpu_addr,cpu_din,cpu_dout,cpu_we);
	end
end
*/

reg [19:0] dbg_pc_counter;
always @(posedge cpu_vpa or posedge cpu_vda or posedge reset)
  if (reset)
    dbg_pc_counter <= 20'd0;
  else if (cpu_vpa & cpu_vda)
    dbg_pc_counter <= dbg_pc_counter + 20'd1;

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

endmodule

