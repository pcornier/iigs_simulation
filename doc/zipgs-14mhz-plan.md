# 14.32 MHz (speed step 4) on FPGA — Failure Analysis & Fix Plan

**Date:** 2026-07-06
**Branch context:** `fix/lc-registers` (7b98fde); accelerator history on `feat/zipgs-speed`, merged to master
**Status:** IMPLEMENTED (same day). Fixes 1-4 below are in the tree:
- Fix A (write back-pressure): `Apple-IIgs.sv` — `wr_pending` (2-FF synced `wr_ack`) into `mem_stall` on accelerated fastram writes; post + snoop gated identically.
- Fix C (snoop forwarding): `rtl/sdram_cache.sv` — comb forward of the pending write into `cpu_data_now` during the `wr_stb` cycle.
- Fix B (classification escape): `rtl/clock_divider.v` — `ph2_en` output comb-gated by `fast_escape` (accel && !dma && !slow && !slowMem && slow_class_now).
- Unclamp: OSD "14.3 MHz" restored, `host_speed` clamps at step 4.
- Validation: new `vsim/sdram_tb/tb_wstream.sv` reproduces problem A with the pre-fix bridge (29 dropped-write words in SDRAM, masked by the cache until eviction) and passes clean with the fix (450/450). `tb_accel` 36/36, `tb_ch3` 53/53 (both under iverilog; tb_accel needed negedge stimulus + a cache reset to run under a 4-state simulator — TB-only changes).

**HARDWARE VALIDATED (2026-07-07, DE10-Nano):** RBF (md5 0e036527..., timing +0.473ns setup / +0.245ns hold) deployed with CFG pre-seeded to speed 4 (byte1=0x48 = 14.3 MHz + ROM3). GS/OS 6.0.1 boots to the Finder desktop at 14.32 MHz: 3/3 cold boots, pixel-identical desktop screenshots, 3-minute soak clean. This is the configuration that crashed into the ROM self-test under load on the 682a767 build.

**Sim-side discovery (problem D, not in the original analysis):** `--speed 4` in the simulator was ALREADY broken (instant BRK-loop at reset, with or without these fixes) — e95310a's "14.3 works in sim" note was stale. Cause: the sim's unified fastram/ROM `dpram` has a registered (1-tick-late) read; at 1-tick cycles the CPU sampled the previous address's byte. Fix: `rtl/dpram.sv` gained a `sim_async_a` parameter exposing a combinational read mirror (`q_a_comb`; default 0, so synthesized instances keep BRAM inference), and `vsim/sim.v` muxes the CPU read byte by live `accel_active` — exactly mirroring the FPGA's accel_r datapath selection. Native MUST keep the registered path: an always-comb read shifted HDD DMA readback timing and moved the GS/OS boot progress bar (regression diff). With the mux, sim at speed 4 passes the full MMU test suite (1A/1A ALL TESTS PASSED at 14.32 MHz).

**Regression caveat:** GS/OS boot writes to `gsos.hdv`, so any speed-4 (or native) boot run mutates the disk image and can shift the blessed frame-320 progress-bar screenshot by one notch. The 10/10 all-pass run was done with all RTL fixes BEFORE the disk was touched; later GS/OS "failures" are disk-state drift, not RTL. Re-bless after confirming two consecutive native boots produce identical screenshots.

## 1. History

The 14.32 MHz step (1-tick fast cycle, `fast_thresh = 0`) was enabled once and reverted:

- **682a767** — OSD 14.3 MHz enabled; boots GS/OS to desktop on DE10-Nano, static timing met (+0.525ns).
- **e95310a** (2026-07-03) — reverted: "boots to the GS/OS desktop and passes static timing but **crashes into the ROM self-test under load** — a cycle-level race the 2-tick (7.16 MHz) step avoids by having a full extra CLK_14M tick of slack for the posted SDRAM write / miss-stall to settle." OSD clamped to step 3 (7.16); 14.3 left sim-only.

**The revert predates several major bug fixes**, each of which independently causes "crashes under load at high speed" and contaminated the original 14.3 test:

| Commit | Fix | Landed after revert? |
|--------|-----|---------------------|
| 31fbf1a | `sdram_cache` mem_ack CDC metastability (2-FF sync) — caused intermittent 7.16 boot crashes by itself | yes |
| 7b98fde | LC ladder phi0→phi2 gating — the flaky 7MHz "bad memory" | yes |
| dc6f254 | ZipGS IWM hold-off (native speed around floppy access) | yes |
| 5f76880 | Per-slot delay revert (7.2 MHz crash/beep) | yes |

So the observed instability had multiple since-fixed contributors. However, a fresh read of the current RTL at a 1-tick cycle finds **three live structural problems**. Problem A is almost certainly the primary killer.

## 2. Clocking facts (baseline for the analysis)

- `clk_sys` = 14.318 MHz (PLL outclk_4); `clk_mem` = 114.5 MHz (8× clk_sys, same PLL).
- At step 4, `clock_divider` fires `ph2_en` on **every** clk_sys edge — every tick is a full CPU cycle.
- CPU enable: `EN = RDY_IN & CE` (P65C816.sv:117). `RDY_IN = ~hdd_dma & ~mem_stall` (iigs.sv:2004). RDY is **combinational** into the enable — it is the only control that can act within the same 1-tick cycle. Everything registered (including `ph2_en` itself) is decided one cycle before the cycle's address exists.
- Accelerated read path (already validated at 7.16): burst-8 line fill (`sdram_burst` ch1) → 8-line `sdram_cache`, combinational `hit_now`/`cpu_data_now`, `mem_stall = accel_r & ~we & (fastram_ce|rom_ce) & ~cache_hit_now` (Apple-IIgs.sv:402). Miss stalls are self-covering at any speed — **reads are not the problem**.

## 3. Problem A (smoking gun): SDRAM write channel silently drops writes

**Where:** `Apple-IIgs.sv:431-437` (post), `rtl/sdram_burst.sv:150-205` (service/ack).

**Mechanism:**

- The glue posts a write by toggling `wr_req` on every `phi2 & we & fastram_ce` — **it never checks `wr_ack`** (no back-pressure).
- In `sdram_burst`, one write occupies IDLE-dispatch + states 1..8 (`STATE_LAST_WR`) ≈ **9 clk_mem ≈ 78.6ns** of controller throughput. The ack is `ack0 <= req0` at `STATE_CONT` (line 195) — it samples the **live** req0.
- At 14.3 MHz the CPU can issue one write per **69.8ns** — faster than the controller can retire them. The 65C816 emits up to **4 back-to-back write cycles** (native-mode interrupt entry pushes PB, PCH, PCL, P consecutively; also MVN/MVP, stack-heavy code).
- When a queued `wr_req` toggle lands while a prior write is still in flight — guaranteed during write streaks, and made worse when a refresh (~70ns) or a burst line fill (~166ns) delays dispatch — `ack0 <= req0` captures the *post-toggle* value: **the queued write is acknowledged without ever reaching SDRAM**, and its data in `wr_addr/wr_din` may already be overwritten by the next post.

**Why it presents as "boots, then crashes under load":** the cache **write-snoop still applies the dropped write** to any cached line, so execution continues correctly — until that line is evicted (cache is only 8 lines × 16 bytes) and refetched from SDRAM, returning a stale byte somewhere unrelated, much later. Delayed, load-dependent memory corruption. A RAM self-test under interrupt load is the perfect trigger.

**Why 7.16 is immune:** at 139.7ns per write there is ~2× headroom over the 78.6ns service time; even refresh collisions don't accumulate.

## 4. Problem B: fast/sync speed classification is one cycle too late at 1 tick

**Where:** `rtl/clock_divider.v` — `slow_class_now` (line 93), the fire-hold (line 559-560), registered `slowMem`/`we_reg`.

**Mechanism:** `ph2_en` is a registered enable. The enable that ends cycle N is decided at the edge *before* cycle N's address is valid. The `slow_class_now` combinational mirror was added precisely because at 2-tick cycles the registered `slowMem` landed on the cycle-ending edge — but at **1-tick cycles even the comb mirror has no spare edge**: the fire it would suppress was already committed one edge earlier.

**Consequence:** the *first* access of every slow-classified run — I/O ($C0xx), banks E0/E1, shadowed video writes, slot space — completes as a 69ns fast cycle: wrong Mega II sync timing, and stale data from any device with a registered read path (slow-RAM BRAM, etc.). The registered `slowMem` then asserts one cycle late and imposes a spurious sync on the *following* access. Additionally `we_reg` is misaligned by a full cycle at 1-tick, misclassifying shadowed writes.

Subsequent accesses in a slow run classify correctly (predecessor is same class), which is why the machine could still boot in the 682a767 test — only run boundaries are wrong.

## 5. Problem C: cache write-snoop lands one tick late

**Where:** `Apple-IIgs.sv:440` (`snoop_stb <= phi2 & we & fastram_ce`), `rtl/sdram_cache.sv:119-126`.

**Mechanism:** the snoop strobe is registered one clk after the write commits, and the cache data array updates at the end of the *following* tick (nonblocking). At 1-tick cycles the next CPU read completes on that same edge — a cached read of the just-written address one cycle after the write returns **pre-write data**. The window is narrow (read-same-address exactly one cycle after a write: self-modifying code writing the next instruction byte, tight RMW-adjacent patterns), so this is a secondary contributor. At 2-tick cycles the snoop always lands before the read's sample point.

## 6. Non-problems (checked, OK at 1 tick)

- **Write-vs-read-fill ordering:** ch0 (writes) has top arbitration priority in `sdram_burst`, and a miss's `mem_req` launches ≥1 clk_sys after the write's `wr_req` — the write always dispatches first. The "write before read of following cycle" invariant holds.
- **Read misses:** stall via comb `mem_stall` → RDY; self-covering at every step.
- **HDD DMA / IWM / floppy:** already forced to native pace (`dma_active`, IWM hold-off).
- **I/O side-effect repeats during stalls:** the LC $C08x ladder is phi2-gated and stall-guarded (7b98fde); I/O classifies slow so phi2 fires once per access (modulo Problem B's run-boundary escape).

## 7. Fix plan (in order)

1. **Write back-pressure (fixes A).** Add a `wr_pending` term (wr_req vs wr_ack, ack synced into clk_sys) to the CPU stall: when the current cycle is a fastram **write** and the previous posted write has not been acked, hold RDY low so the post never overruns the controller. Reuses the exact `mem_stall` → `RDY_IN` structure already validated at 7.16. Cost: an occasional 1-tick stall during write streaks; zero effect at native (a write completes in well under 5 ticks).
   - Alternative considered: a small write FIFO / write-combining ("burst writes"). Correct but more machinery than needed — the sustained deficit is only 69.8 vs 78.6ns and only during short streaks. Back-pressure is sufficient and simpler. A 2-deep FIFO remains an option if benchmarks show the stalls matter.
2. **Snoop forwarding (fixes C).** In `sdram_cache`, combinationally compare the pending write (`wr_addr/wr_din/wr_be`, plus the not-yet-applied `snoop_stb` cycle) against `cpu_addr` and forward matching bytes into `cpu_data_now`. Byte-granular mux; no state change.
3. **Comb slow-classification hold (fixes B).** Export a combinational "this access classifies slow but the fast counter would fire" signal from `clock_divider` into the CPU RDY path (alongside `mem_stall`), so a slow-classified access at 1-tick is *held* rather than escaping fast; the registered `slowMem` then reroutes it to a proper sync cycle on the next edge. Align the `we_reg` term (use live `we` in the comb path — already the case in `slow_class_now`).
   - Deliberately **not** making `ph2_en` itself combinational: a comb enable would ripple into every ph2 consumer in iigs.sv; the RDY-stall reuses the already-proven structure. Must remain a provable no-op at `fast_thresh == 4` (native) — regression must stay byte-identical.
4. **Unclamp step 4.** `Apple-IIgs.sv:210` clamps `host_speed` to 3; `zipgs_regs.sv` caps software speed at code 3 (7.16 = Zip's rated max — keep that; 14.3 stays an OSD-only overclock as before). Restore the OSD entry removed in e95310a.
5. **Verify.**
   - Sim: `regression.sh` byte-identical at native; `--speed 4` boot + selftest + mmutest; targeted TB for the write back-pressure (consecutive-write streak with refresh collision).
   - Timing: the new comb terms feed the same addr→MMU→classify→RDY path that closed at +0.525ns — check slack after each fix.
   - Hardware: rebuild, verify board md5 vs output_files (see floppy35-72mhz lesson), then soak at 14.3: GS/OS desktop, ROM self-test loop, interrupt-heavy titles. Note this retest also carries the post-revert CDC (31fbf1a) and LC (7b98fde) fixes for the first time at 14.3.

## 8. Problem E (found on hardware 2026-07-07, root-caused in the new SDRAM-accurate sim):
## speed transitions shorten the in-flight cycle before the datapath catches up

**Hardware symptom:** GS/OS System 6.0.1 crashes during boot at sustained 14.3 (Zip registers
disabled; with them enabled the on-disk ZipGS.CDev re-clocks to 7.16 mid-boot, masking it).
Live-monitor forensics: BRK at $09/3925; exactly one byte of loaded code wrong vs the disk
($3924: $29→$85); the byte HEALED after a cache-eviction sweep — cache/SDRAM divergence.

**Root cause (caught by the `make SDRAM=sim` coherency checker, deterministic at boot):**
`fast_thresh` reverts combinationally when an IWM hold-off expires / HDD-DMA ends. The clock
divider's in-flight fire compare (`ph2_counter >= eff_thresh`) snaps to the accelerated value
immediately, producing 1-tick cycles while the top-level datapath select `accel_r` (latched at
phi2) is still NATIVE — so reads run 1-tick through the never-stalling ch3 path, whose
`nat_data` register is cold (no ch3 launches happen while accelerated). Stale bytes, no stall:
`SDRAMSIM_VIOLATION addr=ff59be got=fa exp=8f accel_r=0` right after the boot floppy-scan
hold-off. Boot toggles hold-offs constantly (floppy scan, every HDD sector), each expiry a
roulette spin — matches "boots sometimes, corrupts under disk-heavy load".

**Fix:** latch `eff_thresh` in clock_divider on each (gated) `ph2_en` fire — the same edge
where Apple-IIgs.sv latches `accel_r` — so cycle length and datapath select always change as
a matched pair and no in-flight cycle can shorten. `fast_escape` keys off the latched value
too. Native-neutral by construction (latch value is always 4 at native).

**Problem F (introduced by the E fix, caught on HW + reproduced deterministically in sim):**
with cycle length and `accel_r` now correctly paired, the FIRST native-path reads right
after a fast→native switch still lose: ch3 wasn't launching while accelerated (`nat_data`
cold) and its first request can queue behind an in-flight line fill. Boot wedge, 100%
reproducible: at the drive scan's first IWM access (`BIT $C0E8` → hold-off → switch), the
next instruction's operands fetched stale (`BIT $C0ED` executed as `BIT $2C8F`), skipping a
Sony-drive register access, after which the ROM's IWM handshake loop (`FF:4720 STY $C0EF /
EOR $C0EE / BNE`) spins forever → "stuck at the splash" at 14.3 on hardware, identical wedge
in `make SDRAM=sim` (violation showed `accel_r=0 hit_now=1` — the cache had the right bytes;
the mux pointed at cold nat_data).

**Fix (datapath-switch guard):** for the first 2 committed cycles after any `accel_r`
change, keep serving reads through the CACHE path — `use_cache_path = accel_r ||
guard_counter != 0` applied to the data mux, the stall rule, and the fill strobe — comb-hit
+ stall-on-miss is correct at any cycle length, and ch3 warms up underneath. Native-only
operation never transitions, so the guard is structurally inert there. Verified in the
SDRAM-accurate sim: 0 violations, the drive scan proceeds, HDD boot engages at speed 4.

**HARDWARE CONFIRMED (2026-07-08 00:52):** the latch+guard build (ec729648) boots GS/OS to
the Finder desktop at PURE 14.32 MHz (Zip registers disabled), 3/3 cold boots pixel-identical
plus a 3-minute soak. Note: an intervening debugging day was consumed by a **deployment
trap** — a stale RBF at `/media/fat/Apple-IIgs.rbf` (the SD root) shadowed every deploy to
`_Computer/`, because MiSTer Main resolves an MGL's `<rbf>` from the root first. Every "the
guard doesn't work on HW" observation and every "invisible debug instrumentation" mystery
was that. RULE: deploy to the root path (or both) and verify with an unmistakable marker
build when instrumentation seems dead. Side deliverables of the hunt, all kept: the
`DEBUG_PIXEL_OVERLAY` on-screen state overlay and `DEBUG_DDR_TRACE` (wickerwaka ddr_trace)
deep bus capture in Apple-IIgs.sv (ifdef'd off; note ddr_trace produced no DDR writes through
this framework's ram1 port even with trigger=1 — debug that before relying on it), the
`--speed-after` sim option, the sim_bus one-shot ioctl strobes, and the `--headless`
video-clock fix in sim_main.

**Tooling built for this (permanent):** `make SDRAM=sim` integrates the production
`sdram_burst` + `sdram_cache` + behavioral chip model into the Vemu sim with a verbatim copy
of the Apple-IIgs.sv bridge, an 8x clk_mem from sim_main, and a golden-model coherency
checker (`SDRAMSIM_VIOLATION` lines). Also fixed `sim_bus.cpp` to emit HPS-accurate one-shot
`ioctl_wr` strobes (was held-level, which deadlocks req/ack-toggle consumers). This closes
the "works in sim, fails on FPGA" gap called out in doc/sdram_accel/02_sim_model_spec.md.

## 9. Expected outcome

Problems A–C are all consistent with the e95310a symptom, and A alone fully explains "boots to desktop, corrupts memory under load." With back-pressure, snoop forwarding, and the classification hold in place — plus the since-landed CDC and LC fixes — there is no remaining *known* mechanism by which a 1-tick cycle differs unsafely from a 2-tick cycle: every data deadline is either met combinationally or covered by an RDY stall.
