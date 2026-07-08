# 14.32 MHz (speed step 4): failure analysis, fixes, and debugging history

**Status: COMPLETE (2026-07-08).** GS/OS 6.0.1 boots to the Finder desktop at pure,
sustained 14.32 MHz (Zip registers disabled) on real hardware — 3/3 cold boots
pixel-identical plus soak, native regression 10/10 byte-identical, timing met
(+0.220ns setup). Fix commits on `fix/lc-registers`: `df5460f` (problems A–D),
`f3372fa` (problems E–F + debug tooling), `2d55831` (sim infrastructure),
`a5a9d46` (docs). Architecture reference: `doc/accelerator-architecture.md`.

This document is the complete record: six distinct 1-tick bugs (A–F), how each
was found, and the debugging lessons — several of which cost real time and are
worth never re-learning.

---

## 1. Background

The 14.32 MHz step (1-tick fast cycle, `fast_thresh = 0`) was first enabled in
682a767 (booted GS/OS, timing met) and reverted in e95310a (2026-07-03):
"crashes into the ROM self-test under load." That revert predated four
independently crash-causing fixes (sdram_cache mem_ack CDC 31fbf1a, LC phi2
ladder 7b98fde, IWM hold-off dc6f254, per-slot delay revert 5f76880), so the
original evidence was contaminated — but a fresh analysis of the RTL at a
1-tick cycle found real structural problems, and fixing them surfaced more.

**The governing constraint at 1 tick:** the CPU enable is
`EN = RDY_IN & CE`; `ph2_en` (CE) is registered, decided one edge before the
cycle's address exists, so **the combinational RDY path is the only control
that can react to the current cycle's address**. Every fix below either uses
RDY or arranges for registered state to change only at cycle boundaries.

## 2. The six problems

### A. Write channel silently drops writes (the original corruption)
The ch0 write post was fire-and-forget (`wr_req` toggled without checking
`wr_ack`). One controller write takes ~9 clk_mem ≈ 78.6ns; a 1-tick CPU can
commit one write per 69.8ns (the 65C816 emits up to 4 back-to-back write
cycles on interrupt entry). A queued toggle landing mid-service is absorbed by
`ack0 <= req0` — the write never reaches SDRAM, and the cache snoop masks the
loss until eviction: delayed, load-dependent corruption. 7.16 has ~2× headroom.
**Fix:** `wr_pending` (2-FF-synced `wr_ack`) stalls an accelerated fastram
write through `mem_stall`/RDY; post and snoop gated identically.
**Proof:** `tb_wstream` — pre-fix bridge loses 29 words to SDRAM
(interrupt-push patterns swept across refresh phase); with back-pressure
1239/1239 clean, including a direct chip-memory compare immune to snoop
masking.

### B. Slow/fast classification one edge late
The `slow_class_now` fire-hold (which saved 7.16) has no spare edge at 1 tick:
the enable is already high when the address appears, so the first access of
every slow run (I/O, E0/E1, shadowed write, slot) would complete as a 69ns
fast cycle — wrong Mega II sync timing, stale data from registered-output
devices. **Fix:** `fast_escape` gates the `ph2_en` *output* combinationally;
the suppressed access stays uncommitted and the registered `slowMem` reroutes
it to a proper sync cycle. Provably inert at native and at ≥2-tick steps.

### C. Cache snoop lands one cycle after the write
A 1-tick read of the just-written address commits on the same edge the snoop
updates the array, sampling pre-write data. **Fix:** during the one `wr_stb`
cycle, the pending write's byte lanes are forwarded combinationally into
`cpu_data_now`.

### D. (Simulator) instant-BRAM fastram is registered-read
e95310a's "14.3 works in sim" was an artifact: the sim's `dpram` read is one
tick late, so `--speed 4` actually BRK-looped at reset once properly exercised.
**Fix:** `dpram sim_async_a` comb read mirror (default off — synthesized
instances keep BRAM inference), muxed in `sim.v` by live `accel_active`,
mirroring the FPGA datapath selection. Native keeps the registered path — an
always-comb read shifted HDD-DMA readback timing and broke GS/OS regression
byte-identity.

### E. Speed transitions shorten the in-flight cycle (hold-off expiry)
`fast_thresh` reverts combinationally when an IWM hold-off expires or HDD-DMA
ends; the divider's in-flight fire compare snapped to the accelerated value
while the datapath select `accel_r` (latched at phi2) was still native →
1-tick reads through the never-stalling, **cold** ch3 path (`nat_data` doesn't
launch while accelerated). Boot toggles hold-offs on every floppy scan and HDD
sector; each expiry was a corruption roulette spin. Found on hardware as a
one-byte code corruption (monitor forensics: `$09/3924` read `$85` instead of
`$29`, healed by cache eviction — cache/SDRAM divergence), then reproduced
deterministically by the `make SDRAM=sim` coherency checker
(`SDRAMSIM_VIOLATION addr=ff59be … accel_r=0` right after the boot floppy-scan
hold-off). **Fix:** `eff_thresh` is latched in clock_divider on each gated
`ph2_en` fire — the same edge Apple-IIgs.sv latches `accel_r` — so cycle
length and datapath select change as a matched pair and no in-flight cycle can
shorten. `fast_escape` keys off the latched value.

### F. Cold ch3 after a fast→native switch (exposed by the E fix)
With lengths and datapath correctly paired, the *first* native-path reads
after a fast→native switch still lose: ch3 wasn't launching while accelerated
and its first request can queue behind an in-flight line fill. Deterministic
boot wedge: at the drive scan's first IWM access, `BIT $C0ED`'s operands
fetched stale (executed as `BIT $2C8F`), skipping a Sony-drive register
access, after which the ROM's IWM handshake loop (`FF:4720 STY $C0EF /
EOR $C0EE / BNE`) spins forever — "stuck at the splash." Identical in sim and
on hardware; the sim violation showed `hit_now=1` (the cache had the correct
bytes; the mux pointed at cold `nat_data`). **Fix:** a 2-cycle
**datapath-switch guard** — after any `accel_r` change, reads keep flowing
through the cache path (`use_cache_path` on the data mux, the stall rule, and
the fill strobe; comb-hit + stall-on-miss is correct at any cycle length)
while ch3 warms up. Native-only operation never transitions, so the guard is
structurally inert there.

## 3. Non-problems (checked and cleared at 1 tick)

- **Write-vs-fill ordering:** ch0 has top arbitration priority and a fill
  request launches ≥1 clk_sys after a posted write — writes always dispatch
  first, so fills always contain earlier committed writes.
- **Read misses:** comb `mem_stall` → RDY is self-covering at every step.
- **HDD DMA / IWM / floppy:** forced to native pace; the CPU is RDY-held for
  the whole DMA, so DMA never overlaps CPU cache activity.
- **I/O side-effect repeats during stalls:** the LC $C08x ladder is phi2-gated
  and stall-guarded (7b98fde); I/O classifies slow, so phi2 fires once per
  access.
- **ROM self-test error 05014000/05012B00** at 14.3/7.16 is EXPECTED, not a
  bug: test 05 is the FPI speed test (`diag.tests.asm:584` FPI_SPEED), which
  counts loop iterations per VERTCNT line against fixed limits ($19/$1A). Any
  accelerator fails it; the measured values ($40 at 14.3, $2B at 7.16) even
  confirm the speed steps are real.

## 4. Validation summary

- `vsim/sdram_tb/tb_wstream.sv` (iverilog, `build_wstream.sh`): 1-tick bridge
  mirror; reproduces A pre-fix, clean post-fix. `tb_accel` 36/36, `tb_ch3`
  53/53.
- `make SDRAM=sim` (see §5): 0 coherency violations through cold boot at
  speed 4, HPS-late speed arrival (`--speed-after` at multiple ticks), and
  warm reset; GS/OS boots. The pre-fix builds show the E and F violations
  deterministically.
- Native regression 10/10 byte-identical after every change (all fixes are
  structurally inert with the accelerator off).
- Hardware (DE10-Nano, build ec729648): GS/OS desktop at pure 14.32 MHz,
  3/3 cold boots pixel-identical + 3-minute soak; 7.16 unchanged-stable.
- Benchmarks (Alan's accelerator comparison sheet): MiSTer at 14.3 lands in
  real TWGS-15/ZipGS-16 territory (Sieve 99 vs 99/98), 6–20% behind real
  14–16 MHz cards on write-heavy tests — consistent with 1 MHz I/O syncs plus
  write back-pressure.

## 5. Tooling built during the hunt (permanent)

- **`make SDRAM=sim`** — the Vemu sim with the PRODUCTION `sdram_burst` +
  `sdram_cache` + behavioral chip model, glued by a verbatim copy of the
  Apple-IIgs.sv bridge, `clk_mem_ext` at 8× from sim_main, and a golden-model
  coherency checker that prints `SDRAMSIM_VIOLATION` the moment any committed
  CPU read returns stale data. Closes the "works in sim, fails on FPGA" gap
  for the memory path (doc/sdram_accel/02). ~6× slower than the plain sim.
- **`--speed-after <tick>:<code>`** — switches `host_speed` mid-run, modeling
  the real MiSTer where the OSD status word arrives after the ROM is running.
- **`--headless` fixed** — it had never clocked the video model, so
  `count_frame` stayed 0: every frame-gated headless run silently never fired
  its `--stop-at-frame`/`--screenshot` triggers, and screenshot copies picked
  up stale files. `video.Clock` now runs unconditionally.
- **`sim_bus` one-shot ioctl strobes** — `ioctl_wr` deasserts while
  `ioctl_wait` throttles, matching HPS `data_io`; held-level strobes deadlock
  req/ack-toggle consumers.
- **`DEBUG_PIXEL_OVERLAY`** (Apple-IIgs.sv, ifdef'd off) — frame-latched
  {CPU-activity counter, accel_r, mem_stall, bus address} rendered as 8×8
  bit-blocks in the video output; readable from HDMI screenshots even when
  the CPU is wedged. Validated by rendering in the sim.
- **`DEBUG_DDR_TRACE`** (Apple-IIgs.sv, ifdef'd off) — wickerwaka's
  `ddr_trace` (rtl/ddr_trace.v) on the otherwise-unused DDRAM port: on-change
  bus records to HPS DDR3 at 0x30000000 (verified free on this system:
  Linux `mem=511M`, scaler fb at 0x20000000); decode with
  `tools/decode_ddr_trace.py`. **Caveat:** in the one hardware attempt, no DDR
  writes appeared even with `trigger=1` — the ram1 bridge path needs its own
  debugging before this tool can be relied on. Read `/dev/mem` via mmap only
  (`devmem` / python mmap / wickerwaka's `devmem_read.py`); plain
  `dd`/`read()`/`write()` are blocked by this kernel.

## 6. Debugging lessons (each cost real time)

1. **MiSTer Main resolves an MGL's `<rbf>` from `/media/fat` (SD root) BEFORE
   `_Computer/`.** A stale root RBF shadowed every `_Computer/` deploy for a
   full day, faking "the fix doesn't work on hardware" and making all debug
   instrumentation invisible (while the fit reports truthfully showed the
   logic present). Deploy to the root (or both), and when instrumentation
   looks dead, verify with an unmistakable marker build (e.g. a solid-color
   video channel).
2. **`--headless` + frame-gated automation had never worked** (see §5); a
   `--stop-at-frame` run that exits 124 means the frame gate never fired —
   suspect the gate before suspecting sim speed, and never trust a copied
   screenshot without confirming the run reached its stop frame.
3. **GS/OS boot writes to gsos.hdv.** Any boot run mutates the image and can
   shift the blessed frame-320 regression screenshot by one notch. Verify two
   consecutive native boots produce identical screenshots, then re-bless —
   don't chase RTL.
4. **Zip software displays % of rated speed** (rated = 7.16), so the control
   panel reads ~6.7 MHz even at a true 14.3 — benchmarks are the real
   speedometer. The on-disk ZipGS.CDev also re-clocks the machine to its
   saved speed during GS/OS boot; test pure 14.3 with the OSD "ZipGS
   Registers: Disabled".
5. **Live-monitor forensics work well remotely:** a BRK wedge drops to the
   monitor; a human typing `<bank>/<addr>.<addr>` dumps plus a disk-image
   ground-truth search (`grep` the code bytes in the .hdv) pinpointed the E
   corruption to a single byte, and an eviction-sweep dump (reading 1.5KB
   through the cache) proved cache/SDRAM divergence.
6. **Verify which file the board actually loaded** — this project has now hit
   the stale-bitstream trap twice (see also `floppy35-72mhz` memory);
   `find /media/fat -maxdepth 3 -iname '*apple*gs*.rbf'` first.

## 7. Remaining known items

- ddr_trace ram1 writes (§5 caveat) — debug if deep HW tracing is ever needed.
- The Zip CDA/CDev "% of rated" display clamp at step 4 — cosmetic.
- $C05C per-slot delay is stored but not applied (all slots slow when
  accelerated — matches Zip defaults).
- TWGS detection shim (fake 'TWGS' table + $C06A-$C06D) — follow-on for
  TWGS-aware titles.
