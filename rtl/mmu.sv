// ============================================================================
// mmu.sv — Apple IIgs memory decode
//
// Logical (CPU/DMA-side) address + soft-switch state  ->  physical address
// and chip enables. This mirrors the split in the real machine: the FPI owns
// the fast side (banks 00-7F, ROM, shadowing into the Mega II) and the
// Mega II owns the slow side (banks E0/E1, IIe soft switches, language card,
// I/O, slots). Neither chip contains an adder in the address path — all
// remapping is done by gating individual address lines:
//
//   - Language-card $Dxxx bank-2 window: force A12 low, so the second $Dxxx
//     bank lives in the otherwise-unused $Cxxx physical RAM (IIe MMU scheme).
//   - Main/aux select: force bank bit 0 high (slow-RAM A16 / odd fast bank).
//
// Everything here is a pure function of {bank_log, addr_log, we, vpb_n} and
// register state. No clocks, no internal state. That makes the module
// directly unit-testable: see vsim/mmu_tb.cpp, which sweeps this decode
// against a C++ golden model.
// ============================================================================

module mmu #(
    parameter RAMSIZE = 128           // number of 64K fast-RAM banks
)(
    // Logical address (CPU view, post HDD-DMA mux, pre-translation)
    input  wire [7:0]  bank_log,
    input  wire [15:0] addr_log,
    input  wire        we,            // 1 = write cycle
    input  wire        vpb_n,         // 65C816 vector pull, active low
    input  wire        rom_select,    // 1 = ROM1 build (no TEXT2 shadow)

    // Soft-switch / register state
    input  wire        LCRAM2,        // LC $Dxxx bank 2 selected
    input  wire        RDROM,         // LC reads come from ROM
    input  wire        LC_WE,         // LC write enable
    input  wire [7:0]  shadow,        // $C035 shadow register (bits are inhibits)
    input  wire        ALTZP,
    input  wire        RAMRD,
    input  wire        RAMWRT,
    input  wire        STORE80,
    input  wire        PAGE2,
    input  wire        HIRES_MODE,
    input  wire        bank_latch,    // NEWVIDEO[0]: 1 = E1 distinct from E0
    input  wire        shadow_all,    // CYAREG[4]: shadow video pages in all banks
    input  wire [7:0]  SLTROMSEL,     // $C02D slot ROM select

    // Simulation debug only (referenced by `ifdef debug $display; unused in synthesis)
    input  wire [7:0]  dbg_wdata,
    input  wire [23:0] dbg_cpu_addr,

    // Physical address & decode
    output wire [23:0] addr_bus,      // translated physical address
    output reg         aux,           // main/aux select (ORed into bank bit 0)
    output wire        lcram2_sel,    // LC RAM window active (feeds inhibit_cxxx)
    output wire        inhibit_cxxx,  // suppress $Cxxx slot/ROM decode
    output wire        IO,            // internal I/O space $C000-$C0FF
    output wire        EXTERNAL_IO,   // slot I/O $C090-$C0FF routed off-chip
    output wire        is_internal_io,
    output wire        is_internal,   // $CNxx slot ROM mapped to internal firmware
    output reg         fastram_ce,
    output reg         slowram_ce,
    output wire        slowram_we,
    output wire        rom1_ce,       // bank FE
    output wire        rom2_ce,       // bank FF + IIe-style windows in bank 00
    output wire        romc_ce,       // bank FC
    output wire        romd_ce,       // bank FD
    output wire        slot_ce,
    output wire        slot_internalrom_ce,
    output wire        rom_writethrough
);

  // --------------------------------------------------------------------------
  // Main/aux select (IIe soft-switch model, extended to the IIgs banks)
  // --------------------------------------------------------------------------

  // All-bank shadow: When CYAREG[4]=1, even banks (02-7E) act like bank 00 for RAMRD/RAMWRT
  wire all_bank_shadow_even = shadow_all && (bank_log >= 8'h02 && bank_log <= 8'h7e) && ~bank_log[0];

  always @(*)
    begin: aux_ctrl
      aux = 1'b0;
      if ((bank_log==0 || bank_log==8'he0 || (bank_log==8'he1 && ~bank_latch)) && (addr_log[15:9] == 7'b0000000 | addr_log[15:14] == 2'b11))		// Page 00,01,C0-FF
        aux = ALTZP;
      else if ((bank_log==0 || bank_log==1 || bank_log==8'he0 || bank_log==8'he1) &&  addr_log[15:10] == 6'b000001)		// Page 04-07
        aux = ((bank_log==1 || (bank_log==8'he1 && bank_latch)) || ((bank_log==0 || bank_log==8'he0 || (bank_log==8'he1 && ~bank_latch)) &&   ( (STORE80 & PAGE2) | ((~STORE80) & ((RAMRD & (~we)) | (RAMWRT & we))))));
      else if (addr_log[15:13] == 3'b001)		// Page 20-3F
        aux = ((bank_log==1 || (bank_log==8'he1 && bank_latch)) || ((bank_log==0 || bank_log==8'he0 || (bank_log==8'he1 && ~bank_latch)) &&    ((STORE80 & PAGE2 & HIRES_MODE) | (((~STORE80) | (~HIRES_MODE)) & ((RAMRD & (~we)) | (RAMWRT & we))))));
      else if (all_bank_shadow_even)
        // All-bank shadow: RAMRD/RAMWRT redirects even banks to odd banks
        aux = ((RAMRD & ~we) | (RAMWRT & we));
      else
        aux = ((bank_log==1 || (bank_log==8'he1 && bank_latch)) || ((bank_log==0 || bank_log==8'he0 || (bank_log==8'he1 && ~bank_latch)) && ((RAMRD & (~we)) | (RAMWRT & we))));
    end

  // --------------------------------------------------------------------------
  // Logical -> physical address translation
  // --------------------------------------------------------------------------

  // The guards ensure addr_log is in $D000-$DFFF wherever the A12 fold applies,
  // so this concatenation is exactly "addr_log - 16'h1000".
  wire [15:0] addr_lc_fold = {addr_log[15:13], 1'b0, addr_log[11:0]};

  // Language-card $Dxxx bank-2 window active: fold A12.
  // Mega II side (E0/E1): IOLC is always present. FPI side (00/01): only when
  // shadow[6]=0. On both sides, under RDROM the fold still applies to
  // language-card WRITES (write RAM while reading ROM) via LC_WE && we.
  wire lc_dxxx_fold =
      (addr_log[15:12] == 4'hD) && LCRAM2 && (~RDROM || (LC_WE && we)) &&
      ( (bank_log == 8'he0 || bank_log == 8'he1) ||
        ((bank_log == 8'h00 || bank_log == 8'h01) && ~shadow[6]) );

  // Language-card $E000-$FFFF RAM selected (no fold needed; feeds lcram2_sel /
  // inhibit_cxxx only).
  wire lc_exxx_ram =
      (addr_log[15:13] == 3'b111) && ~RDROM &&
      ( bank_log == 8'he0 || bank_log == 8'he1 ||
        ((bank_log == 8'h00 || bank_log == 8'h01) && ~shadow[6]) );

  assign lcram2_sel = lc_dxxx_fold | lc_exxx_ram;

  // Bank latch disabled (NEWVIDEO[0]=0): E1 behaves as E0 (IIe memory model).
  wire [7:0] bank_eff  = (bank_log == 8'he1 && ~bank_latch) ? 8'he0 : bank_log;

  // Main/aux select is bank bit 0 (slow-RAM A16 / odd fast bank). aux is only
  // ever asserted for banks 00/01/E0/E1 and, under CYAREG[4] all-bank shadow,
  // for even banks 02-7E — so this OR is the whole aux redirect.
  wire [7:0] bank_phys = {bank_eff[7:1], bank_eff[0] | aux};

  assign addr_bus = {bank_phys, lc_dxxx_fold ? addr_lc_fold : addr_log};

  wire [15:0] addr_phys = addr_bus[15:0];

  // --------------------------------------------------------------------------
  // I/O and slot decode
  // --------------------------------------------------------------------------

  assign slowram_we = we && (
    // For E0/E1 Language Card areas ($D000-$FFFF), require LC_WE
    ((bank_log == 8'he0 || bank_log == 8'he1) && addr_log >= 16'hd000) ? LC_WE :
    // For all other slowram areas, allow normal writes
    1'b1
  );

  assign is_internal_io = ~SLTROMSEL[addr_phys[6:4]];

  assign EXTERNAL_IO = ((((bank_log == 8'h0 || bank_log == 8'h1) && !shadow[6]) || bank_log == 8'he0 || bank_log == 8'he1) && addr_log >= 'hc090 && addr_log < 'hc100 && ~is_internal_io);

  assign inhibit_cxxx = lcram2_sel | ((bank_log == 8'h0 | bank_log == 8'h1) & shadow[6]);

  // I/O space ($C000-$C0FF) mapping per Apple IIgs Hardware Reference:
  // - Banks E0/E1: I/O always accessible (no shadow register check)
  // - Banks 00/01: I/O accessible only when shadow[6]=0
  // - All-bank shadow: When CYAREG[4]=1, I/O space appears in banks 02-7F too
  wire all_bank_io = shadow_all && (bank_log >= 8'h02 && bank_log <= 8'h7f);
  assign IO = ~EXTERNAL_IO & addr_log[15:8] == 8'hC0 &
              (((bank_log == 8'h00 | bank_log == 8'h01) && !shadow[6]) | bank_log == 8'he0 | bank_log == 8'he1 | all_bank_io);

  assign is_internal = ~SLTROMSEL[addr_phys[10:8]];
  assign slot_ce             = (bank_phys == 8'h0 || bank_phys == 8'h1 || bank_phys == 8'he0 || bank_phys == 8'he1) && addr_phys >= 'hc100 && addr_phys < 'hc800 && ~is_internal && ~inhibit_cxxx;
  assign slot_internalrom_ce = (bank_phys == 8'h0 || bank_phys == 8'h1 || bank_phys == 8'he0 || bank_phys == 8'he1) && addr_phys >= 'hc100 && addr_phys < 'hc800 &&  is_internal && ~inhibit_cxxx;

  // --------------------------------------------------------------------------
  // ROM chip enables
  // --------------------------------------------------------------------------

  assign romc_ce = bank_log == 8'hfc;
  assign romd_ce = bank_log == 8'hfd;
  assign rom1_ce = bank_log == 8'hfe;

  // Force ROM2 on IRQ/BRK vector fetch cycles (VPB low) to return correct vectors from ROM bank FF
  wire vec_fetch_force_rom_ce = (~vpb_n) && (bank_log == 8'h00) &&
                                ((addr_log == 16'hFFEE) || (addr_log == 16'hFFEF) ||
                                 (addr_log == 16'hFFFE) || (addr_log == 16'hFFFF));

  // rom2_ce enables reading from ROM bank $FF
  // Note: Per IIgs documentation, RDROM should only control language card ($D000-$FFFF).
  // However, for compatibility, we keep the $C000-$CFFF behavior EXCEPT for slot ROM space
  // ($C100-$C7FF) which must be controlled by INTCXROM/SLTROMSEL instead of RDROM.
  // This allows slot card ROM (like SmartPort at $C7xx) to work correctly.
  // When shadow[6]=1 (IOLC inhibit), $C000-$CFFF in banks 00/01 becomes RAM, not I/O or ROM
  // The language-card ROM windows ($D000-$DFFF, $E000-$FFFF under RDROM) apply
  // to bank 01 exactly like bank 00 (shadow[6] IOLC control covers both banks).
  wire lc_rom_bank = (bank_log == 8'h00 || bank_log == 8'h01);
  assign rom2_ce = (bank_log == 8'hff) || vec_fetch_force_rom_ce ||
                   (lc_rom_bank & addr_log >= 16'hd000 & addr_log <= 16'hdfff && (RDROM | ~vpb_n) && !shadow[6]) ||
                   (bank_log == 8'h0 & addr_log >= 16'hc000 & addr_log < 16'hc100 && (RDROM | ~vpb_n) && !shadow[6]) ||  // I/O ($C000-$C0FF) - only when IOLC not inhibited
                   // $C800-$CFFF: slot expansion ROM. On real hardware this maps to
                   // the expansion ROM of whichever slot most recently had $CN00
                   // accessed (cleared by reading $CFFF). We don't model external slot
                   // cards — every slot in this sim points at internal IIgs firmware —
                   // so routing $C800-$CFFF to internal ROM unconditionally (when IOLC
                   // is not inhibited) matches every observable behavior. Previously we
                   // gated on (RDROM | ~VPB), which broke games that do JSR $C300 /
                   // JMP $C803 with both RDROM=0 and INTCXROM=0 (e.g. A Mind Forever
                   // Voyaging) — they'd read $C803 as RAM = 0x00 and BRK into the
                   // monitor at frame ~430.
                   (bank_log == 8'h0 & addr_log >= 16'hc800 & addr_log <= 16'hcfff && !shadow[6]) ||  // Expansion ($C800-$CFFF)
                   // Note: $C100-$C7FF (slot ROM) deliberately NOT included here - handled by slot_internalrom_ce/slot_ce
                   (lc_rom_bank & addr_log >= 16'he000 &                          (RDROM | ~vpb_n) && !shadow[6]) ||
                   (bank_log == 8'h0 & addr_log >= 16'hc070 & addr_log <= 16'hc07f && !shadow[6]) ||
                   // Mega II language card: banks E0/E1 $D000-$FFFF read from
                   // ROM when RDROM=1 (gssquared maps SYS_ROM there; the old
                   // behavior read stale LC RAM instead). Writes are unaffected:
                   // the write path is gated by slowram_we/fastram_ce, not this.
                   ((bank_log == 8'he0 || bank_log == 8'he1) && addr_log >= 16'hd000 && RDROM);

  // ROM write-through for language card
  assign rom_writethrough = ((bank_log == 8'h00 || bank_log == 8'h01) && addr_log >= 16'hd000 && LC_WE && we);

  // --------------------------------------------------------------------------
  // Memory controller: fast/slow RAM chip enables
  // --------------------------------------------------------------------------

  // Page and shadow detection helpers
  wire [3:0] page = addr_log[15:12];  // 16 pages per bank (256 bytes each)

  // Shadow region detection (when shadow bit = 0, shadowing is ACTIVE)
  wire txt1_shadow  = ~shadow[0] && (page == 4'h0 && addr_log[11:8] >= 4'h4 && addr_log[11:8] <= 4'h7);  // $0400-$07FF
  wire txt2_shadow  = rom_select ? 1'b0: ~shadow[5] && (page == 4'h0 && addr_log[11:8] >= 4'h8 && addr_log[11:8] <= 4'hB);  // $0800-$0BFF (ROM3+ only)

  wire hgr1_shadow  = ~shadow[1] && (page >= 4'h2 && page <= 4'h3);          // $2000-$3FFF
  wire hgr2_shadow  = ~shadow[2] && (page >= 4'h4 && page <= 4'h5);          // $4000-$5FFF
  // SHR shadow bit 3: When 0, entire $2000-$9FFF shadows (master enable for SHR mode)
  // When bit 3=1, HGR bits 1-2 control $2000-$5FFF, and $6000-$9FFF does not shadow
  wire shr_master_shadow = ~shadow[3] && (bank_phys == 8'h01) && (page >= 4'h2 && page <= 4'h9);     // $2000-$9FFF when bit3=0
  wire aux_disable  = shadow[4];   // When set, disable auxiliary shadowing for bank 01

  always_comb begin
    fastram_ce = 0;
    slowram_ce = 0;

    if (IO) begin
      // I/O space - no RAM access
      fastram_ce = 0;
      slowram_ce = 0;
    end else begin
      case (bank_log)
        // Bank 00: Main memory with shadow regions
        8'h00: begin
          // In ROM shadow mode, $E000-$FFFF are ROM reads, do not access RAM
          // When shadow[6]=1 (IOLC inhibited), $E000-$FFFF is contiguous RAM, not ROM
          if (RDROM && addr_log >= 16'hE000 && !rom_writethrough && !shadow[6]) begin
            fastram_ce = 0;
            slowram_ce = 0;
          end else if (txt1_shadow || txt2_shadow || shr_master_shadow || hgr1_shadow || hgr2_shadow) begin
            // Shadowed regions: Enable BOTH for compatibility (fastram takes priority in mux)
            // shr_master_shadow: When bit3=0, entire $2000-$9FFF shadows
            // hgr*_shadow: When bit3=1, only HGR pages shadow based on bits 1-2
            fastram_ce = 1; // Enable fastram (will be selected by priority mux)
            slowram_ce = 1; // Also enable slowram (for proper shadow writes)
`ifdef DEBUG_IO
            if (addr_log >= 16'h0400 && addr_log <= 16'h07FF)
              $display("SHADOW_WRITE: bank00 addr=%04x shadow=%02x txt1=%b txt2=%b shr=%b -> DUAL WRITE",
                       addr_log, shadow, txt1_shadow, txt2_shadow, shr_master_shadow);
`endif
          end else begin
            fastram_ce = 1;  // Normal Bank 00 RAM (non-shadowed)
`ifdef DEBUG_IO
            if (addr_log >= 16'h0400 && addr_log <= 16'h07FF)
              $display("NO_SHADOW: bank00 addr=%04x shadow=%02x txt1=%b txt2=%b shr=%b -> FASTRAM ONLY",
                       addr_log, shadow, txt1_shadow, txt2_shadow, shr_master_shadow);
`endif
          end
        end

        // Bank 01: Auxiliary memory with conditional shadow regions
        8'h01: begin
          // In ROM shadow mode, $E000-$FFFF are ROM reads, do not access RAM
          // When shadow[6]=1 (IOLC inhibited), $E000-$FFFF is contiguous RAM, not ROM
          if (RDROM && addr_log >= 16'hE000 && !rom_writethrough && !shadow[6]) begin
            fastram_ce = 0;
            slowram_ce = 0;
          end else if (shr_master_shadow) begin
            // SHR master shadow (bit3=0): entire $2000-$9FFF shadows to E1
            fastram_ce = 1;  // Write to both Bank 01 (FASTRAM) and Bank E1 (SLOWRAM)
            slowram_ce = 1;  // Dual write to E1 shadow bank
          end else if (txt1_shadow || txt2_shadow) begin
            // Text pages ALWAYS shadow in bank 01 (ignore aux_disable per documentation)
            // Bit 4 only affects "auxiliary Hi-Res graphics pages", not text pages
            fastram_ce = 1;
            if (we) begin
              slowram_ce = 1;
`ifdef DEBUG_IO
              $display("BANK01_SHADOW_WRITE: addr=%04x data=%02x slowram_addr=%05x txt1=%b txt2=%b shadow[0]=%b",
                       addr_log, dbg_wdata, {1'b1, addr_log[15:0]}, txt1_shadow, txt2_shadow, shadow[0]);
`endif
            end
          end else if (!aux_disable && (hgr1_shadow || hgr2_shadow)) begin
            // Hi-Res pages shadow only when aux_disable=0 (bit 4 controls this)
            fastram_ce = 1;
            if (we) begin
              slowram_ce = 1;
            end
          end else begin
            fastram_ce = 1;  // Normal Bank 01 RAM (including LC area)
          end
        end

        // Banks E0/E1: Shadow memory - always SLOWRAM
        8'hE0, 8'hE1: begin
          slowram_ce = 1;
`ifdef DEBUG_CURCYL
          if (we && addr_log == 16'h0F3A)
            $display("E0E1_CURCYL_WRITE: bank=%02x addr=%04x data=%02x addr_bus=%06x aux=%b cpu_addr=%06x",
                     bank_log, addr_log, dbg_wdata, addr_bus, aux, dbg_cpu_addr);
`endif
`ifdef DEBUG_IO
          if (addr_log >= 16'h0400 && addr_log <= 16'h07FF)
            $display("SLOWRAM_DIRECT: bank%02x addr=%04x data=%02x we=%b slowram_addr=%05x bank[0]=%b addr_bus=%06x -> SLOWRAM",
                     bank_log, addr_log, we ? dbg_wdata : 8'hXX, we, {bank_phys[0], addr_phys}, bank_phys[0], addr_bus);
`endif
        end

        // Banks FC-FF: ROM banks - writes should be discarded
        8'hFC, 8'hFD, 8'hFE, 8'hFF: begin
          // ROM is read-only: reads from ROM space, writes are discarded
          // Do NOT enable fastram_ce or slowram_ce for ROM writes
          // This prevents ROM selftest code from corrupting system memory
          if (~we) begin
            // ROM reads: access ROM space (handled by rom1_ce/rom2_ce signals)
            fastram_ce = 0;
            slowram_ce = 0;
          end else begin
            // ROM writes: discard (no memory access)
            fastram_ce = 0;
            slowram_ce = 0;
          end
        end

        // All other banks: Normal RAM (if within RAMSIZE)
        // CYAREG bit 4 (shadow all banks): When set, video page writes in ANY bank shadow to E0/E1
        default: begin
          if ((bank_log < RAMSIZE) && ~rom1_ce && ~rom2_ce) begin
            fastram_ce = 1;
            // CYAREG[4] = FPI shadow enable: shadow video pages from all banks to E0/E1
            // Even banks shadow to E0, odd banks shadow to E1 (via bank[0] bit in slowram address)
            // txt1_shadow, hgr*_shadow etc already include shadow register inhibit checks
            if (shadow_all && we) begin  // All banks when writing (bank[0] determines E0 vs E1)
              // Check if address is in a shadowable video region
              if (txt1_shadow || txt2_shadow || hgr1_shadow || hgr2_shadow || shr_master_shadow) begin
                slowram_ce = 1;  // Enable shadow write to E0 (even) or E1 (odd)
`ifdef DEBUG_IO
                $display("FPI_SHADOW: bank%02x addr=%04x data=%02x -> E%d shadow (CYAREG[4]=1)",
                         bank_log, addr_log, dbg_wdata, bank_log[0]);
`endif
              end
            end
          end
        end
      endcase
    end
  end

`ifdef VERILATOR
  // ----------------------------------------------------------------------------
  // Structural invariants the surrounding decode web depends on. These can only
  // fire if a future edit breaks them — several consumers (I/O decode on the
  // logical address, slot decode on the physical address, the slow-RAM
  // {bank[0], addr} addressing) silently assume them.
  // ----------------------------------------------------------------------------
  always @(*) begin
    // Translation never touches the low 12 address bits
    if (addr_bus[11:0] != addr_log[11:0])
      $fatal(1, "mmu: translation changed A[11:0]: %02x/%04x -> %06x",
             bank_log, addr_log, addr_bus);
    // The A12 fold only ever applies inside $Dxxx
    if (lc_dxxx_fold && addr_log[15:12] != 4'hD)
      $fatal(1, "mmu: LC fold outside $Dxxx: %02x/%04x", bank_log, addr_log);
    // Physical bank only ever differs from logical in bit 0 (aux) or via the
    // E1->E0 bank-latch redirect
    if (bank_phys[7:1] != bank_log[7:1] && !(bank_log == 8'he1 && ~bank_latch))
      $fatal(1, "mmu: unexpected bank translation: %02x -> %02x", bank_log, bank_phys);
    // Mega II banks never enable fast RAM
    if (fastram_ce && (bank_log == 8'he0 || bank_log == 8'he1))
      $fatal(1, "mmu: fastram_ce for Mega II bank: %02x/%04x", bank_log, addr_log);
  end
`endif

endmodule
