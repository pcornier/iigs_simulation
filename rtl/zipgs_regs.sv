// ============================================================================
// zipgs_regs.sv — ZipGS accelerator register interface ($C058-$C05F)
//
// Implements the ZipGS soft-switch protocol so period software (Zip control
// panel, ZIP-aware games) can detect and set the CPU speed. Bit semantics
// follow the KEGS lineage, verified against BOTH
//   software_emulators/gsplus/src/moremem.c  (cases 0x58-0x5f, read+write)
//   kegs-sdl-0.64/src/moremem.c              (identical protocol)
//
// Protocol summary:
//   - LOCKED (default): $C058-$C05F are the ordinary annunciator soft
//     switches. The iigs.sv I/O decode keeps handling them (AN3 = video);
//     this module stays out of the way (zip_unlocked = 0).
//   - Write $5x to $C05A four times -> UNLOCKED. Write $Ax -> relock.
//   - While unlocked:
//       write $C05A (other data) -> DISABLE acceleration (a command, not data)
//       write $C05B              -> ENABLE acceleration  (a command, not data)
//       write $C05D              -> set speed: high nibble, 0=100% .. $F=6.25%
//                                   (stored, read back via $C05A as {sp,$F})
//       write $C059              -> bits 7:3 stored (counter/followup config)
//       write $C058              -> clear $C059 (keep bit 2, "last reset cold")
//       write $C05C              -> stored (per-slot/speaker delay mask)
//       read  $C059/$C05A/$C05C  -> stored values
//       read  $C05B              -> bit7 = ~1ms toggling clock, bit6 = 1
//                                   (cache shadow updated), bit4 = disabled
//
// A host (MiSTer OSD / simulator --speed flag) shares the SAME state through
// host_speed: a change of value applies {enable, canonical speed}, so the
// software-visible registers and the host control always agree.
//
// speed_code output: 0 = native 2.864 MHz ... 4 = 14.32 MHz. The mapping from
// the Zip 16-step percentage to our five achievable clock-enable steps picks
// the largest step <= (16-sp)/16 * 14.32 MHz (see table in the code).
//
// Clock-enable friendly, no gated clocks. Strobes must be one-per-CPU-cycle
// (gate with phi2 in the caller): the unlock counter is edge-sensitive.
// ============================================================================

module zipgs_regs (
    input  wire       clk,          // CLK_14M
    input  wire       reset,

    // CPU write strobe (one pulse per CPU I/O write to $C058-$C05F)
    input  wire       wr_stb,
    input  wire [2:0] wr_addr,      // addr[2:0]: 0=$C058 .. 7=$C05F
    input  wire [7:0] wr_data,

    // Combinational read port (mux into io_read when zip_unlocked)
    input  wire [2:0] rd_addr,      // addr[2:0] of the read being decoded
    output reg  [7:0] rd_data,

    // Motherboard speed switch is slow (CYAREG[7]==0). ZipDA forces this right
    // before its speed self-test, so it's the arming condition for exposing the
    // 1 ms clock on $C05A bit 7. When fast (normal operation) $C05A bit 7 is the
    // clean speed-nibble top bit that Control Panel cdevs read.
    input  wire       mtr_slow,

    // Host (OSD / CLI) speed control. Applied whenever the value changes
    // (and once out of reset), so a mid-session OSD change takes effect.
    //   0 = native (acceleration disabled), 1 = 3.58, 2 = 4.77, 3 = 7.16 MHz
    //   (4 = 14.32 MHz reserved; clamps to 3 until stall-on-miss exists)
    input  wire [2:0] host_speed,

    output wire       zip_unlocked, // 1 = $C058-$C05F are Zip registers
    output wire       accel_en,     // 1 = acceleration engaged
    output wire [2:0] speed_code,   // 0 = native .. 4 = 14.32 MHz

    // Zip cache control ($C059 bit 7): 1 = disable the read cache (every CPU
    // read goes to memory; used for self-modifying code / cache coherency
    // escapes). Only meaningful while accelerating.
    output wire       cache_disable,

    // Per-slot delay mask ($C05C bits 7..1, one per slot 1..7): 1 = that slot's
    // $Cn00 space runs at 1 MHz (delay enabled) when accelerating. Bit 0 is the
    // speaker delay (handled elsewhere). Default 0 => all slots fast.
    output wire [7:0] slot_delay
);

  reg [2:0] unlock;
  reg       disabled;      // $C05B bit 4 (1 = acceleration off)
  reg [3:0] sp;            // Zip speed nibble: 0 = 100% .. 15 = 6.25%
  reg [2:0] speed_reg;     // actual clock step 0..4 (both control paths write it)
  reg [7:0] reg_c059;
  reg [7:0] reg_c05c;

  assign zip_unlocked = (unlock >= 3'd4);
  assign accel_en     = ~disabled;
  assign speed_code   = disabled ? 3'd0 : speed_reg;
  assign cache_disable = ~disabled & reg_c059[7];
  assign slot_delay    = reg_c05c;

  // 1.024 ms-period toggle for $C05B bit 7, matching KEGS ((dcycs>>9)&1 =
  // 512 us half-period): 512 us x 14.31818 MHz = 7331 ticks. The Zip CDA
  // calibrates its speed measurement against this bit, so the period must be
  // exact or the reported MHz scales with the error.
  reg [12:0] ms_ctr;
  reg        ms_toggle;

  // Zip speed percentage nibble -> our clock-enable steps. The card's rated
  // "100%" (nibble 0) is 7.16 MHz (code 3) -- the 8 MHz-class ZipGS speed.
  // Software cannot request the 14.32 MHz overclock (code 4); that is an
  // OSD-only step above the card's spec (see the host path below).
  //   sp 0..8     ->  7.16 MHz (code 3)   (>= 50% of rated)
  //   sp 9..10    ->  4.77 MHz (code 2)
  //   sp 11..12   ->  3.58 MHz (code 1)
  //   sp 13..15   ->  2.86 MHz (code 0, native)
  function automatic [2:0] sp_to_code(input [3:0] s);
    sp_to_code = (s <= 4'd8)  ? 3'd3 :
                 (s <= 4'd10) ? 3'd2 :
                 (s <= 4'd12) ? 3'd1 : 3'd0;
  endfunction

  // Display nibble for the OSD steps, so the Zip CDA's setting line reads
  // sensibly after an OSD change. 7.16 and 14.32 both show as 100% (the card
  // has no ">100%" representation for the overclock).
  function automatic [3:0] host_to_sp(input [2:0 ] h);
    host_to_sp = (h >= 3'd3) ? 4'd0  :   // 7.16 / 14.32 -> 100%
                 (h == 3'd2) ? 4'd5  :   // 4.77 -> ~66%
                               4'd8;     // 3.58 -> 50%
  endfunction

  // Host change detection: host_prev resets to 0 (native), so a non-zero
  // boot-time value (sim --speed flag) applies on the first cycle after reset.
  reg [2:0] host_prev;

  always @(posedge clk) begin
    if (ms_ctr == 13'd7330) begin
      ms_ctr    <= 13'd0;
      ms_toggle <= ~ms_toggle;
    end else
      ms_ctr <= ms_ctr + 13'd1;

    if (reset) begin
      unlock    <= 3'd0;
      disabled  <= 1'b1;      // power-on: acceleration off (native machine)
      sp        <= 4'd0;      // 100% (of the enabled speed) once engaged
      speed_reg <= 3'd0;
      reg_c059  <= 8'h5F;     // KEGS/GSplus power-on value: the Zip CDA renders
                              // these bits as delay/follow-up checkmarks and an
                              // all-zero register displays as nonsense settings
      reg_c05c  <= 8'h00;     // all slots fast, no speaker delay
      host_prev <= 3'd0;
    end else begin
      // --- host (OSD / CLI) side ------------------------------------------
      // OSD host_speed IS the clock step directly (0..4), so the OSD can reach
      // the 14.32 MHz overclock (step 4) that software cannot.
      if (host_speed != host_prev) begin
        host_prev <= host_speed;
        if (host_speed == 3'd0) begin
          disabled  <= 1'b1;
          speed_reg <= 3'd0;
        end else begin
          disabled  <= 1'b0;
          speed_reg <= host_speed;
          sp        <= host_to_sp(host_speed);
        end
      end

      // --- software (ZipGS protocol) side ---------------------------------
      if (wr_stb) begin
        case (wr_addr)
          3'h2: begin   // $C05A: unlock / relock / (unlocked) disable
            if      ((wr_data & 8'hF0) == 8'h50) begin
              if (unlock != 3'd7) unlock <= unlock + 3'd1;
            end
            else if ((wr_data & 8'hF0) == 8'hA0) unlock <= 3'd0;
            else if (zip_unlocked)               disabled <= 1'b1;
          end
          3'h3: if (zip_unlocked) disabled <= 1'b0;              // $C05B: enable
          3'h5: if (zip_unlocked) begin                          // $C05D: speed
            sp        <= wr_data[7:4];
            speed_reg <= sp_to_code(wr_data[7:4]);
          end
          3'h1: if (zip_unlocked) reg_c059 <= {wr_data[7:3], reg_c059[2:0]};
          3'h0: if (zip_unlocked) reg_c059 <= reg_c059 & 8'h04;  // $C058
          3'h4: if (zip_unlocked) reg_c05c <= wr_data;           // $C05C
          default: ;   // $C05E/$C05F: Zip ignores (annunciators only when locked)
        endcase
      end
    end
  end

  // Combinational read data (only meaningful while unlocked; the caller muxes)
  //
  // $C05A: the real ZipDA CDA's speed self-test uses $C05A BIT 7 as its 1 ms
  // timebase (LDA $C05A / BPL edge-wait loop at $14b7 in the CDA), not $C05B
  // bit 7 as the register FAQ / KEGS document. But bit 7 is also the top of the
  // speed nibble that Control Panel cdevs read to detect/report the card, so a
  // permanently-toggling bit 7 makes them see a garbage state ("Zip OFF").
  // Expose the 1 ms clock on bit 7 ONLY while the motherboard is in slow mode
  // (mtr_slow) -- ZipDA clears $C036 right before measuring, so this is exactly
  // its measurement window; normal reads return the clean speed nibble {sp,$F}.
  always_comb begin
    case (rd_addr)
      3'h1:    rd_data = reg_c059;                              // $C059
      3'h2:    rd_data = mtr_slow ? {ms_toggle, sp[2:0], 4'hF}  // $C05A: 1ms clk (measuring)
                                  : {sp, 4'hF};                 //        clean speed nibble
      3'h3:    rd_data = {ms_toggle, 1'b1, 1'b0, disabled, 4'h0}; // $C05B
      3'h4:    rd_data = reg_c05c;                              // $C05C
      default: rd_data = 8'h00;                                 // $C058/5D/5E/5F
    endcase
  end

`ifdef VERILATOR
  // One line per state change — cheap, invaluable for validating the
  // software unlock path end-to-end in simulation.
  reg [2:0] dbg_code;
  reg       dbg_unlocked;
  always @(posedge clk) begin
    if (!reset) begin
      if (speed_code != dbg_code)
        $display("ZIPGS: speed_code %0d -> %0d (sp=%0d disabled=%0d)",
                 dbg_code, speed_code, sp, disabled);
      if (zip_unlocked != dbg_unlocked)
        $display("ZIPGS: %s", zip_unlocked ? "UNLOCKED" : "locked");
    end
    dbg_code     <= speed_code;
    dbg_unlocked <= zip_unlocked;
  end
`endif

endmodule
