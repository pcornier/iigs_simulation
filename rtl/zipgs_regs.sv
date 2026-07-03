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

    // Host (OSD / CLI) speed control. Applied whenever the value changes
    // (and once out of reset), so a mid-session OSD change takes effect.
    //   0 = native (acceleration disabled), 1 = 3.58, 2 = 4.77, 3 = 7.16 MHz
    //   (4 = 14.32 MHz reserved; clamps to 3 until stall-on-miss exists)
    input  wire [2:0] host_speed,

    output wire       zip_unlocked, // 1 = $C058-$C05F are Zip registers
    output wire       accel_en,     // 1 = acceleration engaged
    output reg  [2:0] speed_code    // 0 = native .. 4 = 14.32 MHz
);

  reg [2:0] unlock;
  reg       disabled;      // $C05B bit 4 (1 = acceleration off)
  reg [3:0] sp;            // Zip speed nibble: 0 = 100% .. 15 = 6.25%
  reg [7:0] reg_c059;
  reg [7:0] reg_c05c;

  assign zip_unlocked = (unlock >= 3'd4);
  assign accel_en     = ~disabled;

  // 1.024 ms-period toggle for $C05B bit 7, matching KEGS ((dcycs>>9)&1 =
  // 512 us half-period): 512 us x 14.31818 MHz = 7331 ticks. The Zip CDA
  // calibrates its speed measurement against this bit, so the period must be
  // exact or the reported MHz scales with the error.
  reg [12:0] ms_ctr;
  reg        ms_toggle;

  // Zip percentage -> our clock-enable steps. The accelerator's rated speed
  // ("100%") is 7.16 MHz: the 14.32 MHz single-tick step needs a cache with
  // stall-on-miss (see doc/sdram_accel/) before it is honest, so speed code 4
  // is reserved and everything clamps to code 3 for now.
  //   sp 0..8     ->  7.16 MHz (code 3)   (>= 50% of rated)
  //   sp 9..10    ->  4.77 MHz (code 2)
  //   sp 11..12   ->  3.58 MHz (code 1)
  //   sp 13..15   ->  2.86 MHz (code 0, native)
  function automatic [2:0] sp_to_code(input [3:0] s);
    sp_to_code = (s <= 4'd8)  ? 3'd3 :
                 (s <= 4'd10) ? 3'd2 :
                 (s <= 4'd12) ? 3'd1 : 3'd0;
  endfunction

  // Canonical Zip speed nibble for each host step, so software reading $C05A
  // after an OSD change sees a value that maps back to the same step.
  function automatic [3:0] code_to_sp(input [2:0] c);
    code_to_sp = (c >= 3'd3) ? 4'd0  :   // 7.16 MHz = 100% of rated speed
                 (c == 3'd2) ? 4'd10 :
                 (c == 3'd1) ? 4'd12 : 4'd15;
  endfunction

  always_comb speed_code = disabled ? 3'd0 : sp_to_code(sp);

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
      reg_c059  <= 8'h5F;     // KEGS/GSplus power-on value: the Zip CDA renders
                              // these bits as delay/follow-up checkmarks and an
                              // all-zero register displays as nonsense settings
      reg_c05c  <= 8'h00;
      host_prev <= 3'd0;
    end else begin
      // --- host (OSD / CLI) side ------------------------------------------
      if (host_speed != host_prev) begin
        host_prev <= host_speed;
        if (host_speed == 3'd0) begin
          disabled <= 1'b1;
        end else begin
          disabled <= 1'b0;
          sp       <= code_to_sp(host_speed);
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
          3'h5: if (zip_unlocked) sp       <= wr_data[7:4];      // $C05D: speed
          3'h1: if (zip_unlocked) reg_c059 <= {wr_data[7:3], reg_c059[2:0]};
          3'h0: if (zip_unlocked) reg_c059 <= reg_c059 & 8'h04;  // $C058
          3'h4: if (zip_unlocked) reg_c05c <= wr_data;           // $C05C
          default: ;   // $C05E/$C05F: Zip ignores (annunciators only when locked)
        endcase
      end
    end
  end

  // Combinational read data (only meaningful while unlocked; the caller muxes)
  always_comb begin
    case (rd_addr)
      3'h1:    rd_data = reg_c059;                              // $C059
      3'h2:    rd_data = {sp, 4'hF};                            // $C05A
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
