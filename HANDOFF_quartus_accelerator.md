# Handoff: SDRAM accelerator — Quartus box bring-up (START HERE)

Audience: the LLM/engineer working on the **Quartus / FPGA** machine with the real hardware.
Branch: `feat/sdram-accelerator`. This doc is the single start-here; deeper detail is linked.

## TL;DR — what you're picking up
A burst+cache SDRAM accelerator memory path has been **designed, prototyped, and
simulation-verified** for the Apple IIgs core. It is **folded into the FPGA build but gated OFF
by default** (`` `ifdef ACCEL_SDRAM ``), so the current known-good bitstream is unchanged. Your
job: synthesize with the macro on, close timing at 114.5 MHz, and validate on hardware — first
that it boots identically at native 2.8 MHz, then (next phase) raise the CPU clock for the
actual speedup.

**Everything below the RTL has been verified only in Verilator (module + bridge level). Nothing
here has been synthesized, timing-closed, or run on hardware. That is your job.**

## Why this exists
`rtl/sdram.sv` (the shipping controller) does one full SDRAM row cycle per 16-bit word
(~9 controller cycles ≈ 78.6 ns/word @ 114.5 MHz). That cannot sustain a CPU faster than
~2.8 MHz. Measured in sim against a behavioral chip model:

| path | SDRAM cyc/word | vs 9.0 |
|---|---|---|
| single-word (`rtl/sdram.sv`) | 9.00 | baseline |
| burst-8 (`rtl/sdram_burst.sv`) | 2.37 | 3.8× |
| cache+burst, hot loop | 0.29 | 31× |

So a burst read + small line buffer makes a 7–14 MHz CPU feasible. (Background on alternatives,
incl. why no MiSTer console controller uses open-row, is in `HANDOFF_sdram_accelerator.md`.)

## What changed in the repo (this branch)
Production RTL (in the Quartus build via `files.qip`):
- `rtl/sdram_burst.sv` — 3-channel controller; **ch1 = burst-8 read → 128-bit aligned line**
  (one ACTIVATE + READ(burst=8, auto-precharge)); ch0/ch2 single-word writes; refresh; init.
  Same pinout, `clk_mem` (114.5 MHz), `init`, toggle req/ack as `rtl/sdram.sv`. Drives
  `SDRAM_CLK` via the same `altddio_out` cell. **Mandatory address remap: column = low address
  bits** (the shipping controller puts the row in the low bits, which defeats bursts).
- `rtl/sdram_cache.sv` — 8-line × 8-word (64-word) line buffer on the CPU read path (clk_sys),
  with ch0 write-snoop coherency.
- `Apple-IIgs.sv` — under `` `ifdef ACCEL_SDRAM ``: instantiates `sdram_burst` + `icache`, routes
  CPU reads through the cache, snoops ch0 writes. The `` `else `` branch is the **original `sdram`
  path, byte-for-byte unchanged**.
- `files.qip` — adds the two modules (unused/dropped when the macro is off).

Not touched: `rtl/sdram.sv` keeps the old behavior (one safe change earlier: its `SDRAM_DQ`
moved from a registered `inout reg`/`<= 'Z` to the standard `inout` + `dq_oe`/`dq_out`
continuous-assign tristate — synthesis-equivalent, needed for Verilator; full regression passed).

## How to turn it on
In `Apple-IIgs.qsf`:
```
set_global_assignment -name VERILOG_MACRO "ACCEL_SDRAM=1"
```
Recompile. To roll back: delete that line (instant return to the known-good path).

## Bring-up checklist (do in order)
1. **Compile, macro OFF first.** Confirm the project still builds and is bit-identical in
   behavior to today (sanity that the additive changes didn't disturb the default path).
2. **Compile with `ACCEL_SDRAM=1`.** `sdram_burst` + `sdram_cache` should elaborate;
   `altddio_out` resolves to the same megafunction `sdram.sv` uses.
3. **Timing** (`sys/sys_top.sdc`, `timing_paths.tcl`):
   - `clk_mem` Fmax must still meet **114.5 MHz**. The burst controller's per-cycle logic is
     comparable to `sdram.sv` (same RAS/CAS); only the read *round* is longer (~19 vs 9 cycles),
     so Fmax should be similar — verify, don't assume.
   - New: 128-bit `rd_line` bus; the cache BRAM (8×128b data + tags) — confirm it infers BRAM
     and meets clk_sys (14.3 MHz, easy).
   - SDRAM_DQ/-A/command IO timing constraints must still pass.
4. **CDC review.** `sdram_cache` (clk_sys) samples the controller's `ack1` (clk_mem) with a
   single FF, matching the original bridge's practice. Consider a 2-FF synchronizer on `mem_ack`
   before relying on it long-term.
5. **HW functional test at native 2.8 MHz.** Boot the regression set on hardware:
   GS/OS, Total Replay, Total Replay II, Arkanoid, BASIC, WOZ 3.5". **Behavior must match the
   non-accel build exactly.** At 2.8 MHz a cache miss (one ~19-cycle `clk_mem` burst ≈ 2.4
   clk_sys) completes within a CPU cycle, so **no CPU stall is wired and none is needed**.
   - If it misbehaves, suspect (in order): address-remap bijection in `sdram_burst.sv`; the
     write-snoop timing (`snoop_stb` is one clk_sys late, when `wr_addr`/`wr_din` hold the
     committed write); the cache CDC; the cache `reset` wiring.
6. **Only after 2.8 MHz is solid: go faster** (this is the payoff phase — see
   `doc/sdram_accel/03_speed_control_design.md`):
   - Drive `cache_stall` (exposed by `icache` in `Apple-IIgs.sv`) into the CPU `RDY_IN`
     (currently `~hdd_dma` inside `rtl/iigs.sv`). A miss MUST stall the CPU at higher clocks.
   - Shorten the `clock_divider` fast cycle: replace the hardcoded `4'd4` threshold
     (`rtl/clock_divider.v:377` and the refresh branch) with a speed-selected value
     (2 ticks = 7.16 MHz, 1 tick = 14.3 MHz). Sketches: `doc/sdram_accel/clock_divider_speed.sv`.
   - Optionally expose it to software via ZipGS `$C059-$C05F` (`doc/sdram_accel/zipgs_regs.sv`,
     semantics from `software_emulators/kegs/src/moremem.c`). Or a simple turbo bit to start.
   - Validate stall coverage carefully: a single un-stalled miss path at 14 MHz = silent
     corruption.

## Important correctness notes
- **Address remap is internal and consistent.** All channels (ch0 write, ch1 read, ch2 upload)
  use the same `a_bank/a_row/a_col` in `sdram_burst.sv`, so ROM/disk images load and read back
  consistently. It must remain a bijection over the used 24-bit word-address space.
- **Coherency scope is just CPU writes.** Video scans out of BRAM (banks E0/E1), not SDRAM, so
  the cache only snoops ch0. This covers self-modifying code / data writes. ch2 upload runs
  before normal execution.
- **No speedup at 2.8 MHz, by design.** The accel path is the *substrate*; it's functionally
  identical and no faster until step 6 raises the clock. Don't expect a benchmark win at native.

## Verify the sim claims yourself (on any box with Verilator)
```
cd vsim/sdram_tb
./build.sh       && ./obj_dir/Vtb_sdram    # single-word baseline (9.00 cyc/word)
./build_burst.sh && ./obj_dir/Vtb_burst    # burst-8 (2.37)
./build_cache.sh && ./obj_dir/Vtb_cache    # locality: hot loop 0.29, coherency PASS
./build_accel.sh && ./obj_dir/Vtb_accel    # production ctrl+cache+bridge: 36/36
```
And the main sim regression (proves the default path is intact):
```
cd vsim && make && ./regression.sh         # 8/8
```

## Map of the docs
- `HANDOFF_quartus_accelerator.md` — this file (start here).
- `HANDOFF_sdram_accelerator.md` — feasibility, controller comparison, design-artifact index.
- `doc/sdram_accel/01_burst_linebuffer_design.md` — burst+cache design + measured results.
- `doc/sdram_accel/02_sim_model_spec.md` — the cycle-accurate chip model + why main-sim
  integration is deferred (collapsed clocks, ~8× slower).
- `doc/sdram_accel/03_speed_control_design.md` — the clock-step / ZipGS speed layer (step 6).
- `doc/sdram_accel/04_fpga_integration.md` — the FPGA wiring detail (this file's source material).
- `ref/sdram_refs/` — NeoGeo/Saturn/PSX/N64 reference controllers used in the comparison.
