# TWGS (tier B) integration into this core

Drop-in wiring for the `twgs_*` modules in this folder. Mirrors the existing
ZipGS block in `rtl/iigs.sv`. All four modules lint clean under Verilator
`-Wall`. This is **tier B** ("TWGS-lite"): detection + `JSL` API + 3-tier speed,
reusing the existing speed/cache engine. **No reset-vector overlay** — the TWGS
ROM does not run at boot, so there is no auto-installed CDA (that is tier C).

Files: `twgs_regs.sv`, `twgs_nvram.sv`, `twgs_rom.sv`, `twgs_card.sv`,
`twgs_rom.hex` (firmware image, 32768 bytes, one hex byte/line for `$readmemh`).

## 0. Add to the build

- Move the four `.sv` into `rtl/` and `twgs_rom.hex` where `$readmemh` can find
  it (Verilator: the sim CWD, i.e. `vsim/`; Quartus: add to project, or fix the
  path in `twgs_rom.sv`). Add the `.sv` to `files.qip` and the `vsim` file list.

## 1. Instantiate the card (rtl/iigs.sv, near the ZipGS block ~line 2551)

```systemverilog
wire        twgs_sel;
wire [7:0]  twgs_dout;
wire        twgs_accel_en;
wire [2:0]  twgs_speed_code;

twgs_card twgs (
    .clk(CLK_14M), .reset(reset),
    .enable(twgs_present),        // OSD toggle (step 5); tie 1'b1 to always-on
    .bank(bank_bef), .addr(addr_bef),
    .we(we), .phi2(phi2),
    .wr_data(dout),               // CPU write data (same net ZipGS uses)
    .cyareg7(CYAREG[7]),
    .turbo_code(host_speed),      // OSD "CPU Speed" = turbo ceiling when accel.
                                  //   Tie 3'd3 instead for a fixed authentic
                                  //   ~8 MHz TransWarp regardless of OSD.
    .sel(twgs_sel), .dout(twgs_dout),
    .accel_en(twgs_accel_en), .speed_code(twgs_speed_code),
    .cache_enable(), .irq_logic_en()
);
```

The `$BC0000.2` accel bit only *engages/disengages* turbo; the OSD `host_speed`
decides how fast turbo is. So a TWGS-aware program's on/off toggle rides on top
of whatever ceiling you set in the MiSTer OSD — including 14.32 MHz once that is
unlocked (see step 3a).

## 2. Overlay the CPU read (rtl/iigs.sv:1816)

`twgs_sel`/`twgs_dout` are keyed on `bank_bef`/`addr_bef` exactly like `din`, so
add the card ahead of the memory read the same way `io_dout` overlays IO:

```systemverilog
// was: ... : din;
wire [7:0] cpu_din = IO ? ((adb_read ? adb_dout : (iwm_strobe ? iwm_dout : io_dout)))
                        : (twgs_sel ? twgs_dout : din);
```

## 3. Combine into the ONE speed engine (rtl/iigs.sv:2627)

Both accelerators drive the same `fast_thresh` and can be active at once (Zip at
`$C05x`, TWGS at bank `$BC` — disjoint, no conflict). Combine **fastest-wins**:
`accel_en` if *either* engages, and the higher of the two requested steps (both
sources output step 0 when idle, so `max` is just the larger code):

```systemverilog
wire       eff_accel_en   = zip_accel_en | twgs_accel_en;
wire [2:0] eff_speed_code = (twgs_speed_code > zip_speed_code) ? twgs_speed_code
                                                              : zip_speed_code;

wire [3:0] fast_thresh = (accel_capable && eff_accel_en && eff_speed_code != 3'd0
                          && iwm_holdoff == 15'd0
                          && !floppy_motor_on && !floppy35_motor_on)
                         ? (4'd4 - {1'b0, eff_speed_code})
                         : 4'd4;
```

(If `accel_r` / the SDRAM read-path mux also keys off `zip_accel_en`, switch it
to `eff_accel_en` too — search near iigs.sv:2632.)

### 3a. Unlocking 14.32 MHz (speed code 4)

`fast_thresh` supports a 1-tick cycle (`4'd4 - 4 = 0`), but 14 MHz is clamped
until the CPU can stall on cache misses — at a 1-tick cycle the SDRAM/BRAM read
has zero slack (`doc/zipgs_speed.md`, `doc/sdram_accel/`). To enable it:
1. Finish stall-on-miss: wire `cache_stall` → the 65C816 `RDY_IN`.
2. Remove the OSD clamp at `Apple-IIgs.sv:210`
   (`host_speed = status[14:12]`, no `>3 ? 3` cap) — this is what lets the OSD
   ceiling (and thus `twgs .turbo_code`) reach 4.
3. Remove the code-4 clamp in `rtl/zipgs_regs.sv` (host path).

Until then everything caps at 7.16 MHz (code 3) — which is the authentic TWGS
speed, so tier B is fully faithful without doing any of this. 14 MHz is a pure
overclock on top, shared by both accelerator front-ends.

## 4. Run bank $BC at native pace (correctness guard)

Classify bank-`$BC` accesses as slow/sync when accelerated — same as the
existing external-slot (`slot_ce`) handling described in `doc/zipgs_speed.md`.
This (a) matches the real card (it runs its own ROM/regs at ≤1 MHz; every
`$BC0000` write drops to 1 MHz) and (b) gives the synchronous ROM BRAM its
read-latency slack under the combinational `cpu_din` overlay. Add
`(bank_bef == 8'hBC)` to whatever term forces a sync cycle for slots.

## 5. OSD "TransWarp GS" present toggle (Apple-IIgs.sv)

Pick a free `status[]` bit (next to the ZipGS toggle at `status[15]`), e.g.:

```systemverilog
wire twgs_present = status[16];   // add to the OSD CONF string / menu
```

and route it to `.enable(twgs_present)` above. `enable=0` ⇒ the card vanishes
(bank $BC falls through to `din`, no signature, accel off). You can gate it with
your existing `accel_capable` if you want it to follow the memory-path guard.

## 6. Validate in sim (the one thing to eyeball)

The genuinely uncertain part is **NVRAM read-bit alignment** — whether the
serial DO on `$BC4000` reads lands on the exact CPU-latch edge. Everything else
is a plain latch/ROM. Exercise it:

- The `JSL` API is callable once the ROM is mapped. From the monitor or a tiny
  test, `JSL $BCFF10` (GetMaxSpeed) should return ~7000 in A; `JSL $BCFF44`
  (GetCacheSize) → 32. These read NVRAM words 7/8 and exercise the read path.
- The `ifdef VERILATOR` `$display`s in `twgs_regs`/`twgs_nvram` print accel
  changes and each decoded NVRAM command (`TWGS-NVRAM: cmd=.. op=.. addr=..`) —
  watch for `op=110`→addr 7/8 reads returning `0x58`/`0x1B`.
- If reads are off by one bit, adjust the read advance in `twgs_nvram.sv`
  (present `shiftout[7]` one cycle earlier/later relative to `data_stb`); the
  `--dump-vcd` flow on the first NVRAM access nails it quickly.

Detection (`'TWGS'` at `$BCFF00`) and speed switching (`$BC0000` bit 2 →
`fast_thresh`) do **not** depend on this and will work immediately.

## 7. Transparent slowdown windows (the beep / paddle / interrupt fix)

Independent of the registers, and the most important thing for compatibility.
See `README.md §4.9` for the *why*. This generalizes the existing `iwm_holdoff`
(iigs.sv:2617) into a small set of address-triggered, retriggerable
"force-native-for-N-ms" windows. **Policy:** ZipGS arms a window only if its
delay setting is on; TWGS arms unconditionally while accelerating.

```systemverilog
// --- per-access strobes (IO space, one pulse/cycle via phi2) --------------
wire acc_spkr  = IO && phi2 && (addr_bef[7:0] == 8'h30);          // $C030 speaker
wire acc_ptrig = IO && phi2 && (addr_bef[7:4] == 4'h7);           // $C070-$C07F trigger
wire acc_pdl   = IO && phi2 && (addr_bef[7:2] == 6'h19);          // $C064-$C067 read
//   NB decode $C030 EXACTLY — do not slow the whole $C03x page (CYAREG $C036,
//   SCC $C038-B, Ensoniq $C03C-F all live there and must NOT be throttled).

// --- policy: who arms these windows ---------------------------------------
// TWGS: always (hardware). ZipGS: only if the matching delay setting is set.
wire spkr_arm = (twgs_present && twgs_accel_en) || (zip_accel_en && zip_slot_delay[0]);
wire pdl_arm  = (twgs_present && twgs_accel_en) ||  zip_accel_en;   // Zip has no
                        // separate paddle bit in $C05C today -> default on when accel

// --- retriggerable down-counters @ 14.318 MHz ------------------------------
localparam [15:0] MS2 = 16'd28636;   // 2 ms   (speaker)
localparam [15:0] MS4 = 16'd57272;   // 4 ms   (full paddle scan ~2.9 ms + margin)
reg [15:0] beep_hold, pdl_hold;
always @(posedge CLK_14M) begin
  if (reset)                          beep_hold <= 16'd0;
  else if (acc_spkr && spkr_arm)      beep_hold <= MS2;            // retrigger
  else if (beep_hold != 16'd0)        beep_hold <= beep_hold - 16'd1;

  if (reset)                          pdl_hold  <= 16'd0;
  else if ((acc_ptrig|acc_pdl)&&pdl_arm) pdl_hold <= MS4;
  else if (pdl_hold != 16'd0)         pdl_hold  <= pdl_hold - 16'd1;
end
wire io_slow_hold = (beep_hold != 16'd0) || (pdl_hold != 16'd0);
```

Then add `&& !io_slow_hold` to the `fast_thresh` condition from step 3 (right
alongside the existing `iwm_holdoff == 0 && !floppy_motor_on ...` — same idea,
more triggers). While any hold is nonzero the CPU runs native, so the beep's
toggle loop and the paddle count loop run at 1 MHz cadence.

Notes:
- **Disk is already done** (`iwm_holdoff` + `floppy*_motor_on`) — this only adds
  speaker + paddles. Keep the disk logic as-is.
- **Interrupts** (`README.md §4.9`): for correct ISR timing you can arm a hold on
  interrupt entry (BRK/IRQ/NMI vector fetch) until `RTI`. TWGS gates this with
  `$BC0000` bit 3 (IRQ-logic enable); it's optional and more involved than the
  address windows — add later if music players / mouse ISRs run fast.
- Durations are tunable. Too short and low speaker tones/long paddle throws
  glitch back to turbo mid-event; too long wastes turbo after the event. 2 ms /
  4 ms are safe starts; expose them (and the ZipGS enables) if you want the
  period-authentic per-category menu control.

## Tier C later (the AE control panel)

Add the reset overlay: enter the CPU at the `$BCFFFC` vector so the TWGS ROM
runs first, keep `$00FFFC/FD` = the genuine GS ROM vector so the hand-off
(`LFB07`) chains to normal boot, and wire the `$BCFFEA` NMI overlay for the
CDA-install deferral. With the NVRAM pre-seeded (word6=`$AE`) the boot ROM's
work is minimal. This is the only part that touches your reset/vector logic.
