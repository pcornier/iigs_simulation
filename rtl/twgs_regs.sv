// ============================================================================
// twgs_regs.sv — TransWarp GS control latch + speed mapping ($BC0000)
//
// Parallels rtl/zipgs_regs.sv, but for the TransWarp GS card instead of ZipGS.
// The TWGS control register is a plain 8-bit read/write latch at $BC0000
// (bank-BC absolute, NOT a $C0xx soft switch). Its bit 2 (accelerate) — in
// combination with CYAREG.7 (Fast) — selects the CPU speed tier, exactly as
// GetCurISpeed in the TWGS ROM decodes it:
//
//   CYAREG.7=0            -> ~1 MHz   (this core: slow/sync cycle, untouched)
//   CYAREG.7=1, $BC0000.2=0 -> ~2.6 MHz (native fast) -> speed_code 0
//   CYAREG.7=1, $BC0000.2=1 -> full TransWarp (~7 MHz) -> speed_code 3 (7.16)
//
// Bit layout of $BC0000 (only these are touched by firmware; it is otherwise a
// transparent latch):
//   bit1 = data cache enable   (TWGS_Cache; advisory here — SDRAM cache is real)
//   bit2 = accelerate          (TWGS_ON/OFF; drives the speed tier)
//   bit3 = IRQ-logic DISABLE   (1 = auto-slowdown-on-interrupt off; advisory)
//
// Sources: TransWarpGS-ROM src/twgs_1.8s/twgs.s:50-51,123 (equates),
//   512-544 (TWGS_ON/OFF), 1161-1203 (cache/IRQ), twgs.3.s:2146 (GetCurISpeed).
//
// Clock-enable friendly, no gated clocks. cfg_wr_stb must be ONE pulse per CPU
// write to $BC0000 (gate with phi2 in the caller, same as zip_wr_stb).
// ============================================================================

module twgs_regs (
    input  wire       clk,          // CLK_14M
    input  wire       reset,

    // One pulse per CPU write to $BC0000 (caller: we & phi2 & sel_bc0000)
    input  wire       cfg_wr_stb,
    input  wire [7:0] cfg_wr_data,
    output reg  [7:0] cfg_reg,       // read back at $BC0000

    input  wire       cyareg7,       // CYAREG $C036 bit 7 (Fast)

    // Turbo ceiling from the OSD ("CPU Speed"): the clock step to use WHEN
    // accelerating. 0=native 2.86, 1=3.58, 2=4.77, 3=7.16, 4=14.32 MHz. Tie to
    // 3'd3 for a fixed authentic TransWarp (~8 MHz-class) card; drive from the
    // OSD host_speed to let the OSD raise the ceiling (code 4 needs stall-on-
    // miss + the clamps removed -- see INTEGRATION.md).
    input  wire [2:0] turbo_code,

    output wire       accel_en,      // 1 = TWGS acceleration engaged
    output wire [2:0] speed_code,    // 0 native .. = turbo step when accelerating
    output wire [2:0] cfg_speed_code,// CONFIGURED speed (ignores CYAREG.7) — for
                                     // the OSD mirror: what the card would run
                                     // at System Speed Fast
    output wire       cache_enable,  // $BC0000 bit1 (advisory; cache is always on)
    output wire       irq_logic_en   // ~$BC0000 bit3 (advisory)
);

  // Host (OSD) speed: edge-applied into the accelerate bit, mirroring the
  // zipgs_regs host path. Nonzero -> engage ($BC0000.2 = 1) at that step;
  // zero -> disengage. A change equal to the current configured speed is a
  // no-op so OSD-mirror write-backs of software changes are absorbed.
  reg [2:0] host_prev;

  always @(posedge clk) begin
    if (reset) begin
      cfg_reg   <= 8'h00;            // power-on: not accelerating, cache off
      host_prev <= 3'd0;
    end else begin
      if (turbo_code != host_prev) begin
        host_prev <= turbo_code;
        if (turbo_code != cfg_speed_code)
          cfg_reg[2] <= (turbo_code != 3'd0);
      end
      if (cfg_wr_stb)
        cfg_reg <= cfg_wr_data;      // software wins on collision cycles
    end
  end

  wire accel = cfg_reg[2];           // $BC0000 bit 2

  // Engaged speed: the OSD sets the step; with the OSD at native (0) a
  // software engage runs at the card's rated speed (7.16 MHz, code 3) — a real
  // TWGS's "TransWarp" speed is fixed hardware, not host-dependent.
  wire [2:0] turbo_eff = (turbo_code == 3'd0) ? 3'd3 : turbo_code;

  // Engage turbo only when BOTH the GS Fast bit and the TWGS accel bit are set
  // — exactly GetCurISpeed's decode. The ~1 MHz tier is CYAREG.7=0, handled by
  // the core's normal slow/sync cycle timing (and by speed_code dropping to 0
  // here, which is the TWGS's built-in "never override System Speed Normal").
  assign accel_en       = cyareg7 & accel;
  assign speed_code     = accel_en ? turbo_eff : 3'd0;
  assign cfg_speed_code = accel    ? turbo_eff : 3'd0;
  assign cache_enable   = cfg_reg[1];
  assign irq_logic_en   = ~cfg_reg[3];

`ifdef VERILATOR
  reg accel_prev;
  always @(posedge clk) begin
    if (!reset && accel_en != accel_prev)
      $display("TWGS: accel %0d -> %0d (cfg=%02x speed_code=%0d)",
               accel_prev, accel_en, cfg_reg, speed_code);
    accel_prev <= accel_en;
  end
`endif

endmodule
