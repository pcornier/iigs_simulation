# (speed) CPU speed-step + ZipGS register design

Ties the memory work (doc `01_*`, burst + line buffer) to an actual faster CPU. Three parts:
1. variable clock-enable steps in `rtl/clock_divider.v` (2.86 / 3.58 / 4.77 / 7.16 / 14.3 MHz),
2. stall-on-miss so a cache miss is honest at any speed (`RDY_IN`),
3. a software-visible **ZipGS `$C059-$C05F`** register interface to select the speed.

Status: DESIGN + RTL SKETCH. `clock_divider_speed.sv` and `zipgs_regs.sv` lint clean in
Verilator; neither is wired into the build. Validate in the doc-02 cycle-accurate sim first.

---

## 1. Where the speed actually comes from

`clock_divider.v` fast mode fires the CPU clock-enable `ph2_en` when `ph2_counter >= 4'd4`
(5 ticks of CLK_14M = 2.8636 MHz) — `clock_divider.v:377`. Speed = pick a smaller threshold:

| threshold (`ph2_counter >=`) | ticks/cycle | CPU MHz (14.318/ticks) |
|---|---|---|
| 4 (today) | 5 | 2.86 |
| 3 | 4 | 3.58 |
| 2 | 3 | 4.77 |
| 1 | 2 | 7.16 |
| 0 | 1 | 14.32 |

Only integer tick counts are possible (it's a clock-enable divider), so these are the whole
menu. The slow (1.024 MHz) and sync (E0/E1, I/O) paths are **unchanged** — acceleration only
shortens the *fast* cycle; every `slowMem` access still runs at 1 MHz for video/Mega2/soft-
switch correctness.

### Minimal edit to `clock_divider.v`
Replace the two hard-coded fast thresholds with a wire:
```verilog
// fast_thresh: 4 = 2.86MHz (default/native), down to 0 = 14.3MHz
wire [3:0] fast_thresh;   // driven by the speed selector (see §3)
...
// was: if (ph2_counter >= 4'd4)
   if (ph2_counter >= fast_thresh) begin ... end
```
Refresh penalty (`clock_divider.v:365-394`): the "every 9th fast cycle takes 10 ticks" rule
is tuned for the 5-tick cycle. At shorter cycles the *absolute* refresh interval must stay
constant, so re-derive the refresh cadence from CLK_14M ticks, not from a fixed cycle count
(e.g. count ticks to the DRAM refresh period and insert a refresh-stall when due) — otherwise
faster cycles refresh too often and waste bandwidth. With the burst controller (doc 01),
refresh is the controller's job (`sdram.sv:110-164`) and this penalty can be dropped entirely;
the clock_divider then only needs to stall for cache misses (§2).

---

## 2. Stall-on-miss (the missing piece at any speed > native)

Today nothing stalls the CPU for memory; the 5-tick cycle just assumes data arrived in time.
That holds at 2.86 MHz with the instant-ish SDRAM, but **not** once the cycle is 1-2 ticks. The
line buffer (doc 01, `sdram_cache.sv`) exposes `cpu_stall`; wire it to the CPU's existing
`RDY_IN` (`rtl/iigs.sv:2058-2075`, gated into `EN` at `P65C816.sv:117`):
```verilog
// in iigs.sv where RDY_IN is driven (currently ~hdd_dma):
assign cpu_rdy = ~hdd_dma & ~cache_stall;   // hold CPU during a line fill
```
Semantics: `clock_divider` keeps pulsing `ph2_en` at the fast rate, but `EN = RDY_IN & CE`
means a pulse with `RDY_IN=0` is ignored, so the CPU simply waits an integer number of fast
periods for the fill. A **hit** completes within the fast step (no stall); a **miss** costs one
burst round trip. This is what makes high clock steps safe: average speed = fast-step ×
hit-rate + miss penalty, all self-regulating.

---

## 3. ZipGS register interface (`$C059-$C05F`)

`zipgs_regs.sv` (sketch) implements the documented ZipGS protocol; bit semantics follow the
KEGS/GSplus reference (`software_emulators/kegs/src/moremem.c:1322-1374,1949-2015`):
- **Unlock**: writes to `$C05A` with `(val & 0xF0)==0x50` increment an unlock counter; `0xA0`
  resets it. Speed/enable bits are writable only once `unlock >= 4`. This stops random pokes
  from changing CPU speed.
- **`$C05A` speed register**: holds the speed value once unlocked. Map its field to `fast_thresh`
  via a small LUT (real ZipGS exposes 16 increments; we collapse to the 5 achievable steps).
- **`$C05B` bit 4**: disable/enable acceleration (1 = disabled → force native 2.86 MHz).
- Outputs: `accel_en`, `speed_code[2:0]` → `fast_thresh`.

### Hooking into the I/O decode
`$C05x` currently routes through the soft-switch path and is marked `slowMem` (it's I/O). Add a
read/write tap for `$C059-$C05F` in `rtl/iigs.sv` next to the other `$C0xx` handlers
(`iigs.sv:864` reads, `:1149` writes), feeding `zipgs_regs`. The speed selector then is:
```verilog
// native CYAREG[7]=0 -> slow path handles it (1 MHz); when fast:
assign fast_thresh = (accel_en & cyareg[7]) ? thresh_lut[speed_code] : 4'd4;
```
So with the accelerator locked/disabled the machine behaves exactly as today (2.86 MHz native).

### Alternative: GSSquared-style turbo (no ZipGS)
For a first bring-up, skip the register file: drive `speed_code` from a MiSTer OSD/config bit
(or overload an unused CYAREG path). Proves the clock-step + stall plumbing before adding the
unlock state machine. ZipGS is only needed for *software* (Zip control panel, games) to detect
and set the speed.

---

## 4. Bring-up order (depends on docs 01 and 02)
1. Land the cycle-accurate sim (doc 02) — without it none of this is measurable.
2. Land burst + line buffer (doc 01) with `cache_stall` exposed.
3. Add `fast_thresh` + stall-on-miss; drive `speed_code` from a config bit (turbo). Step the
   clock down 5→4→3→2→1 ticks in sim, watching assertions, hit-rate, and `stall_cycles`.
4. Add `zipgs_regs` for software-controlled speed; verify with a Zip-aware boot.
5. (Optional) open-row (doc 01 §5) and/or mem clock bump for extra margin at 14.3 MHz.

## 5. Risk notes
- 14.3 MHz (1 tick) is only safe if the cache hit-rate is high AND misses reliably stall; a
  single un-stalled miss path = silent data corruption. Prove stall coverage in sim.
- Timing-sensitive software (some demos/games) may assume 1 or 2.8 MHz; ZipGS disable
  (`$C05B`) and CYAREG must always be able to drop back to native.
- Self-modifying code: the cache write-snoop (doc 01) must catch writes to cached lines or
  accelerated SMC will execute stale bytes.
