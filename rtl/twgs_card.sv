// ============================================================================
// twgs_card.sv — TransWarp GS accelerator card (bank $BC), integration wrapper
//
// Ties together the three pieces of a "TWGS-lite" (tier B) card and presents a
// single, ZipGS-style overlay interface to iigs.sv:
//
//   twgs_regs   $BC0000 control latch + speed tier
//   twgs_nvram  $BC4000/1 Xicor X2444 serial NVRAM (pre-seeded, boot short-cut)
//   twgs_rom    $BC8000-$BCFFFF firmware (detection signature + JSL API)
//
// Drop-in usage in iigs.sv (see INTEGRATION.md for the exact edits):
//   - overlay the CPU read: cpu_din = IO ? io_dout : (sel ? dout : din);
//   - combine into the ONE speed engine:
//       eff_accel_en   = zip_accel_en   | (accel_en);
//       eff_speed_code = accel_en ? speed_code : zip_speed_code;   // TWGS wins
//     then feed eff_* into the existing fast_thresh expr (iigs.sv:2627).
//   - add bank==$BC to the slow/sync cycle classification when accelerated
//     (native-pace bank $BC — matches the real card and gives the sync ROM its
//     read-latency slack).
//
// `enable` = OSD "TransWarp GS" present toggle. When 0 the card vanishes:
// sel=0 (bank $BC reads fall through to din / empty), accel off, no signature.
//
// Pass the *_bef access address (bank_bef/addr_bef) and `dout`(write data) and
// `phi2` exactly as the ZipGS block does. Clock = CLK_14M.
// ============================================================================

module twgs_card (
    input  wire        clk,          // CLK_14M
    input  wire        reset,
    input  wire        enable,       // OSD: TWGS present

    input  wire [7:0]  bank,         // bank_bef
    input  wire [15:0] addr,         // addr_bef
    input  wire        we,
    input  wire        phi2,         // one pulse per CPU cycle
    input  wire [7:0]  wr_data,      // dout (CPU write data)
    input  wire        cyareg7,      // CYAREG $C036 bit 7 (Fast)
    input  wire [2:0]  turbo_code,   // OSD turbo ceiling (host_speed); step when accel

    output wire        sel,          // 1 = TWGS card space -> overlay cpu_din
    output wire [7:0]  dout,         // read data for this access
    output wire        accel_en,     // TWGS acceleration engaged
    output wire [2:0]  speed_code,   // 0 native .. 3 = 7.16 MHz
    output wire [2:0]  cfg_speed_code,// configured speed (ignores CYAREG.7) for the OSD mirror
    output wire        cache_enable, // $BC0000.1 (advisory)
    output wire        irq_logic_en, // ~$BC0000.3 (advisory)

    // X2444 NVRAM backup port (byte view; MiSTer SD save/load)
    input  wire [4:0]  bk_addr,
    input  wire        bk_wr,
    input  wire [7:0]  bk_data,
    output wire [7:0]  bk_q
);

  // ---- bank-$BC absolute decode -----------------------------------------
  wire bc       = enable && (bank == 8'hBC);
  wire sel_rom  = bc && addr[15];              // $BC8000-$BCFFFF (32 KB)
  wire sel_cfg  = bc && (addr == 16'h0000);    // $BC0000  control latch
  wire sel_sdat = bc && (addr == 16'h4000);    // $BC4000  serial data
  wire sel_sctl = bc && (addr == 16'h4001);    // $BC4001  serial control
  assign sel = sel_rom | sel_cfg | sel_sdat | sel_sctl;

  // one-per-cycle strobes (phi2 already pulses once per CPU cycle)
  wire cfg_wr_stb  = sel_cfg  & we & phi2;
  wire ctrl_wr_stb = sel_sctl & we & phi2;
  wire data_stb    = sel_sdat & phi2;          // read or write both clock a bit

  wire [7:0] cfg_reg, nvram_dout, rom_dout;

  twgs_regs regs (
      .clk(clk), .reset(reset),
      .cfg_wr_stb(cfg_wr_stb), .cfg_wr_data(wr_data),
      .cfg_reg(cfg_reg),
      .cyareg7(cyareg7),
      // enable=0 forces the host input to 0 so the OSD edge-apply can't set
      // the accelerate bit while the card is absent (keeps the documented
      // "twgs_present=0 is a pass-through" invariant); a mid-session enable
      // then edge-applies the current OSD speed, engaging the card.
      .turbo_code(enable ? turbo_code : 3'd0),
      .accel_en(accel_en), .speed_code(speed_code),
      .cfg_speed_code(cfg_speed_code),
      .cache_enable(cache_enable), .irq_logic_en(irq_logic_en)
  );

  twgs_nvram nvram (
      .clk(clk), .reset(reset),
      .ctrl_wr_stb(ctrl_wr_stb), .ctrl_wr_data(wr_data),
      .data_stb(data_stb), .data_we(we), .data_wr_data(wr_data),
      .data_dout(nvram_dout),
      .bk_addr(bk_addr), .bk_wr(bk_wr), .bk_data(bk_data), .bk_q(bk_q)
  );

  twgs_rom rom_i (
      .clk(clk), .ce(bc), .addr(addr[14:0]), .dout(rom_dout)
  );

  // read mux: ROM, then registers ($BC4001 read is don't-care -> $FF)
  assign dout = sel_rom  ? rom_dout   :
                sel_cfg  ? cfg_reg    :
                sel_sdat ? nvram_dout : 8'hFF;

endmodule
