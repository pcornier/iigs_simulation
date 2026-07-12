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
    input  wire        vda,          // CPU valid-data-address (this cycle)
    input  wire        vpa,          // CPU valid-program-address
    input  wire [7:0]  wr_data,      // dout (CPU write data)
    input  wire        cyareg7,      // CYAREG $C036 bit 7 (Fast)
    input  wire [2:0]  turbo_code,   // OSD turbo ceiling (host_speed); step when accel
    input  wire        host_irq_en,  // OSD AppleTalk/IRQ delay -> $BC0000 bit3 (inverted)
    input  wire        host_gfx_en,  // OSD Startup Graphics -> NVRAM word2 bit2
    input  wire        host_snd_en,  // OSD Startup Sound    -> NVRAM word2 bit3
    output wire        gfx_en,       // live NVRAM config bits, for the OSD mirror
    output wire        snd_en,

    // Tier C reset overlay: while armed (from reset until execution reaches
    // bank $BC), bank-0 reads of $F800-$FFFF serve the card ROM's top 2 KB --
    // the CPU's reset vector fetch lands on the firmware's $BCFFFC vector
    // (LFB20: JMPL $BCFA9A), and the JMPL moves execution into bank $BC where
    // the normal ROM mapping takes over. See twgs.3.s LFA9A/LFB07.
    input  wire        boot_armed,

    // Phase 2 (CDA install): while nmi_armed, serve ONLY the native NMI
    // vector ($00FFEA/B -> LFB24) and its 4-byte JMPL ($00FB24-27) from the
    // card ROM -- a tight window so runtime bank-0 language-card traffic is
    // untouched (unlike the broad reset overlay, nothing else is remapped).
    input  wire        nmi_armed,

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
  // Reset-overlay window: bank-0 $F800-$FFFF reads -> ROM $BCF800-$BCFFFF
  // (same low 15 bits, addr[15]=1 either way).
  wire boot_ovl = (enable && boot_armed && (bank == 8'h00) &&
                   (addr[15:11] == 5'b11111)) ||
                  (enable && nmi_armed && (bank == 8'h00) &&
                   (addr == 16'hFFEA || addr == 16'hFFEB ||
                    (addr[15:2] == 14'b11111011001001)));  // $FB24-$FB27
  wire sel_rom  = (bc && addr[15]) || boot_ovl; // $BC8000-$BCFFFF (32 KB)
  wire sel_cfg  = bc && (addr == 16'h0000);    // $BC0000  control latch
  wire sel_sdat = bc && (addr == 16'h4000);    // $BC4000  serial data
  wire sel_sctl = bc && (addr == 16'h4001);    // $BC4001  serial control
  assign sel = sel_rom | sel_cfg | sel_sdat | sel_sctl | bf;

  // ---- cache SRAM windows ($BE0000-7FFF tags, $BF0000-7FFF data) ----------
  // The card's cache RAM is directly addressable in banks $BE/$BF; the
  // firmware's Check_Cache_Size probes $BF (non-aliasing => 32 KB),
  // Test_Cache_RAM pattern-tests $BF0200..size, Test_Cache_Flush $BE.
  // Semantics derived from the diagnostics themselves:
  //  - plain R/W retention through the windows;
  //  - DATA reads (VDA & ~VPA) allocate: they visibly dirty the line's
  //    tag+data bytes (instruction fetches do NOT -- that is what lets the
  //    tests execute from inside the tested line range). Test_Cache_Rom /
  //    the flush walk are MVN $BC,$BC self-copies of the card ROM, so card
  //    ROM data reads allocate too; only the $BE/$BF windows are excluded.
  //  - writing $BC0000 while CYAREG.7=0 (both flush helpers: set/clear bit1
  //    at 1 MHz) is a hardware FLUSH: every line invalidates. Modeled as a
  //    background sweeper that outruns the CPU's fastest verify loop.
  // The diagnostics only ever check ==pattern / !=pattern, so invalidation
  // stamps a constant that can never equal the $AA/$55 test patterns.
  wire bf = enable && (bank[7:1] == 7'b1011111) && !addr[15];  // $BE/$BF
  wire win_wr      = bf && we && phi2;
  wire cache_alloc = enable && phi2 && !we && vda && !vpa && !bf;
  // Flush = instant, O(1): bytes are stored XOR flush_epoch and read back
  // XOR flush_epoch. A flush bumps the epoch, so every line written before
  // it reads back changed (old ^ e1 ^ e2, never equal to old since e1 != e2)
  // while writes after it read back exactly (same epoch both ways). A
  // sweeper was tried first and lost the race with the CPU's next fill.
  reg [7:0] flush_epoch;
  always @(posedge clk) begin
    if (reset)
      flush_epoch <= 8'd0;
    else if (cfg_wr_stb && !cyareg7)   // both flush helpers: cfg write at 1 MHz
      flush_epoch <= flush_epoch + 8'd1;
  end

  // Canonical single-port BRAM templates (Quartus-inferable: one write, one
  // registered read per array, nothing else in the block).
  reg [7:0] tag_ram  [0:32767];   // bank $BE view
  reg [7:0] data_ram [0:32767];   // bank $BF view
  reg [7:0] tag_q, data_q;
  wire       tag_we  = (win_wr && !bank[0]) || cache_alloc;
  wire       data_we = (win_wr &&  bank[0]) || cache_alloc;
  wire [7:0] tag_wd  = (win_wr && !bank[0]) ? (wr_data ^ flush_epoch)
                                            : (8'hC3   ^ flush_epoch);
  wire [7:0] data_wd = (win_wr &&  bank[0]) ? (wr_data ^ flush_epoch)
                                            : (8'hC3   ^ flush_epoch);
  always @(posedge clk) begin
    if (tag_we) tag_ram[addr[14:0]] <= tag_wd;
    tag_q <= tag_ram[addr[14:0]];
  end
  always @(posedge clk) begin
    if (data_we) data_ram[addr[14:0]] <= data_wd;
    data_q <= data_ram[addr[14:0]];
  end
  reg bank0_q;
  always @(posedge clk) if (bf) bank0_q <= bank[0];
  wire [7:0] cache_dout = (bank0_q ? data_q : tag_q) ^ flush_epoch;

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
      .host_irq_en(host_irq_en),
      .accel_en(accel_en), .speed_code(speed_code),
      .cfg_speed_code(cfg_speed_code),
      .cache_enable(cache_enable), .irq_logic_en(irq_logic_en)
  );

  twgs_nvram nvram (
      .clk(clk), .reset(reset),
      .ctrl_wr_stb(ctrl_wr_stb), .ctrl_wr_data(wr_data),
      .data_stb(data_stb), .data_we(we), .data_wr_data(wr_data),
      .data_dout(nvram_dout),
      .bk_addr(bk_addr), .bk_wr(bk_wr), .bk_data(bk_data), .bk_q(bk_q),
      .host_gfx_en(host_gfx_en), .host_snd_en(host_snd_en),
      .gfx_en(gfx_en), .snd_en(snd_en)
  );

  twgs_rom rom_i (
      .clk(clk), .ce(bc | boot_ovl), .addr(addr[14:0]), .dout(rom_dout)
  );

  // read mux: ROM, then registers ($BC4001 read is don't-care -> $FF)
  assign dout = sel_rom  ? rom_dout   :
                bf       ? cache_dout :
                sel_cfg  ? cfg_reg    :
                sel_sdat ? nvram_dout : 8'hFF;

`ifdef VERILATOR
  reg [15:0] dbg_alloc_cnt;
  always @(posedge clk) begin
    if (reset) dbg_alloc_cnt <= 0;
    else if (cache_alloc) begin
      dbg_alloc_cnt <= dbg_alloc_cnt + 1;
      if (dbg_alloc_cnt < 16'd20 || (bank == 8'hBC && dbg_alloc_cnt[9:0] == 0))
        $display("TWGS-ALLOC #%0d bank=%02x addr=%04x", dbg_alloc_cnt, bank, addr);
    end
  end
`endif

endmodule
