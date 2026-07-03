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

---

## BRING-UP RESULTS (2026-07-03, on-hardware debug session)

Executed on the Quartus box with the DE10-Nano rig. **The accelerator now boots
GS/OS to the desktop on real hardware at native speed** (`ACCEL_SDRAM=1` +
`mem_stall` wired). Three hardware-only bugs were found and fixed — none were
visible in the module-level Verilator TBs:

1. **Quartus syntax/semantics** (sim-only constructs): bit-select of a function
   call (`a_col(cur)[8:3]` -> `cur_col` wire) and `rfs` driven from two always
   blocks (now a strobe + single owner). Verilator accepted both.
2. **DQ capture skew — scattered single-bit read errors** (reset vector read
   $FA63 instead of $FA62): letting SDRAM_DQ fan out to eight `line` registers
   through decode logic invalidated the `FAST_INPUT_REGISTER` qsf assignment
   (see the fitter's "Ignoring invalid fast I/O register assignments" warning),
   so DQ was captured in fabric with routing skew. Fixed with a dedicated
   `dq_in` register fed straight from the pins (IO-cell packable); the line
   demux now runs one state later (STATE_LDAT0/LDATL).
3. **Miss latency exceeds the native data deadline** — the doc above claims "no
   CPU stall is wired and none is needed" at 2.8 MHz; that is WRONG. A miss is
   ~7 clk_sys end to end (strobe+1, cache FSM+1, 19-cycle burst=2.4, ack CDC,
   ready, byte-mux register), but the CPU samples 5 clk_sys after the phi2
   edge — it read the *previous* read's byte (observed as PC={62,C1} from a
   stale vector fetch). Fix: `cache_stall` -> iigs `mem_stall` -> `RDY_IN`,
   extended by `cache_ready | cache_ready_d` to cover the sdram_dout register
   stage.

Debug methodology that worked (SignalTap .stp hand-authoring failed Q17's
validation; `quartus_stp --enable` -> warning 262004): a temporary on-screen
debug overlay in Apple-IIgs.sv latching fill addresses / CPU-visible
{addr,byte} pairs and rendering them as pixel blocks decoded from HDMI
screenshots (scratchpad decode_overlay.py).

### Remaining before OSD speeds work on hardware
At 2-tick (7.16 MHz) cycles even cache HITS miss the deadline: hit data reaches
`sdram_dout` at phi2+3 but the next enable is phi2+2, and the stall itself
registers too late to suppress that enable (verified on hardware: black screen
with the speed config applied; machine executes but samples stale bytes).
**The hit path must return combinationally** (the cache's `data` array is
already async-read; expose comb hit data + a comb `hit_now` into the byte mux)
before un-gating `accel_capable` for OSD speeds. Until then the committed
default keeps `ACCEL_SDRAM` off (bit-identical known-good path); the accel
build is one qsf macro away and is hardware-validated at native.
