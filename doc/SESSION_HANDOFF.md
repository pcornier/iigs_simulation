# Session Handoff — MMU refactor, ZipGS accelerator, FloatBus accuracy

**Branch:** `feat/zipgs-speed` (pushed to origin, 25 commits ahead of master).
**Last commit:** `9f6c112`. **Working tree clean.**

This session did three big pieces of work in sequence. They're independent;
restart on whichever you want. The **live/unfinished** work is the FloatBus
floating-bus accuracy (bottom section) — everything above it is done.

---

## 1. MMU extraction (DONE, on branch `refactor/mmu-extraction`, merged in here)

Pulled the memory decode out of `iigs.sv` into pure-combinational
`rtl/mmu.sv` (translation, aux select, IO/slot decode, fast/slow CE, ROM CEs).
Replaced the `addr - 16'h1000 + 24'h10000` arithmetic with explicit bit ops.
Unit test: `cd vsim && make mmutest` (48M vectors vs a golden C++ model,
0 failures). Also fixed: E1 slow-cycle speed classification, three RDROM
mapping divergences. See memory `mmu-extraction.md`. Regression byte-identical.

---

## 2. ZipGS / TransWarp CPU accelerator (DONE and hardware-validated)

Full ZipGS-compatible CPU speed control: **OSD menu, `--speed` sim flag, and
the real ZipGS $C058-$C05F software protocol all share one state**
(`rtl/zipgs_regs.sv`). Speeds: 2.8 (native) / 3.6 / 4.8 / **7.16 MHz max**.
Doc: `doc/zipgs_speed.md`, memory `zipgs-speed.md`.

**Hardware state (MiSTer DE10-Nano, 192.168.1.196):** boots GS/OS 6.0.1 to the
desktop at 7.16 MHz reliably; the real ZipDA CDA reads 6.70-6.93 MHz; the
ZipGS.CDev control panel opens without lockup. Enable on FPGA = one qsf line:
`set_global_assignment -name VERILOG_MACRO "ACCEL_SDRAM=1"` (default OFF; the
committed bitstream is the known-good non-accel path).

**Bugs found + fixed on hardware, in order (each its own commit):**
- Combinational cache hit path (`b63f4d0`) — registered path missed the
  deadline above native.
- $C036 override (`d44f5bb`) — the Zip keeps the CPU fast regardless of the
  motherboard speed bit; ANY code that dropped to 1 MHz via $C036 was losing
  acceleration.
- $C05A bit7 = 1 ms clock (`d44f5bb`) — the CDA measures speed by polling
  $C05A bit 7, NOT $C05B as the FAQ/KEGS say (found by disassembling ZipDA).
- Per-slot delay reverted to always-slow (`5f76880`) — slot-ROM-fast crashed
  the slot-7 SmartPort/HDD firmware (beep + crash).
- **2-FF synchronizer on cache mem_ack** (`31fbf1a`) — THE 7.16 crash: single-FF
  CDC sample of the 114 MHz mem_ack was metastable, corrupting fills
  intermittently. This is the big one.
- Control-panel lockup fix (`c5e40f0`) — reverted an over-clever $C05A gate
  and neutralized the cache-disable path (it wedged the CPU: mem_stall =
  reading && !hit_now, hit_now forced low = never released).

**Known limits / TODO:**
- **14.32 MHz is sim-only.** On hardware the 1-tick step passes static timing
  but crashes under load (cycle-level posted-write / miss-stall race). Clamped
  off the hardware OSD (`e95310a`); available via sim `--speed 4`.
- $C05A speed-nibble display in the CDA jitters 100%/50% (bit 7 shares the
  1 ms clock) — cosmetic; the measured MHz is correct.
- $C05C per-slot mask and $C059 C/D-cache-disable are stored/displayed but
  cosmetic (cache-disable is a no-op after the wedge fix).
- **Disk-write validated at 7.16 (2026-07-04, on hardware):** benchmark run,
  text file created+saved to HDD, blank 3.5" WOZ formatted and written. The
  accelerator is always built in as of 46f90a9 (OSD default 2.8 Std; "ZipGS
  Registers" toggle). Remaining: broader game/title sweep at 7.16 (nice-to-
  have, no longer a ship blocker).

**Test rig (memory `fpga-test-rig`):** `sshpass -p 1 ssh root@192.168.1.196`.
Screenshot: `POST http://192.168.1.196:8182/api/screenshots`. Launch a disk
via MGL (`doc/mgl_fpga_testing.md`). Quartus: `~/intelFPGA_lite/quartus/bin`,
`quartus_sh --flow compile Apple-IIgs` (~7 min). **Gotchas:** the keyboard-raw
API reaches the CORE only, NOT the MiSTer OSD (can't drive the OSD remotely —
set speed via a 16-byte little-endian status CFG at
`/media/fat/config/Apple-IIgs.CFG`, speed in byte1 as `speed<<4`; an all-zero
CFG == native ROM3). SignalTap `.stp` hand-authoring is rejected by Quartus 17
headless — use an on-screen debug overlay decoded from HDMI screenshots
(`scratchpad/decode_overlay.py` technique) instead.

---

## 3. FloatBus vaporlock / floating-bus accuracy (LIVE — restart here)

**Goal:** make the floating bus cycle-exact to real Mega II hardware, passing
arekkusu's FLOATBUS test in `vsim/FloatBus_260213/`. **Run at NATIVE speed only**
(the accelerator's $C036 override breaks the cycle-exact 1 MHz timing — which
is correct behavior; the test is a good turbo regression).

**Current state — modes 1,2,4,5,7,8 pass ALL spot checks.** Two root causes
were found and fixed, and they were NOT the ones this section previously
described (the old text and the old fix spec are preserved only in git
history; `doc/floatbus-hbl-fix.md` now has the corrected analysis):

1. **RDVBL ($C019) edge was 266px late** (`rtl/video_timing.v`): the flag
   flipped at the line boundary (hcount==HWL) instead of at the Mega II
   counter wrap (H_M2_WRAP, where m2_v increments). On IIgs the FLOATBUS
   sync is pure RDVBL cycle-counting, so our whole capture was phase-shifted
   ~19 chars — spot #1 (col 63,row 11) is really ACTIVE col 38 of line 11
   ($2CA6=$3E for HGR p1), not an HBL cell.
2. **IIgs blanking = open bus, not scan bytes** (`rtl/iigs.sv`): the Mega II
   refreshes slow RAM during HBL/VBL and drives nothing; a floating-bus read
   returns the CPU's own last bus byte (operand $C0 of `LDA $C05A`, $5A for
   the DP form — the test's `MG2gs` routine). Implemented as `m2_bus_driven`
   window (II modes: V∈[256,448) ∧ H∈[84,644); SHR: V∈[256,456)) +
   `cpu_last_bus` register. The Sather HBL scan address (old plan) is real
   IIe behavior but UNOBSERVABLE on a IIgs — implemented, verified
   display-safe, then removed as dead logic.

**GUARDS (both must hold at every commit):**
1. **textfunk** — `cd vsim && ./obj_dir/Vemu --disk textfunk.po --screenshot 438
   --stop-at-frame 439`, md5 of `screenshot_frame_0438.png` must stay
   **`7abff109f80d62083437e1c379389fb5`** (clean tunnel/grid; the beam-race
   regression).
2. **FLOATBUS** — enable `` `define DEBUG_FBSPOT `` in `rtl/iigs.sv` (line ~17),
   rebuild, `./obj_dir/Vemu --disk floatbus.po --stop-at-frame 1100 --quiet |
   grep FBSPOT`. Spot #1 `actual` must move toward the `expct1` table in
   `src/FLOATBUS.S` (`3E 00 3E 00 DF 00 DF A0 A0 FF FF` for modes 1..B). Full
   pass = no `FAIL` lines.
3. Full `./regression.sh` byte-identical (native path unchanged).

**Diagnostic tooling (committed, gated):** `DEBUG_FLOATBUS` logs each $C05A
floating-bus read with beam position + returned byte; `DEBUG_FBSPOT` logs the
test's per-mode spot-check results. Both in `rtl/iigs.sv`, off by default.

**Remaining:** (a) ~~modes 3/6/B PAL~~ **PAL/50Hz implemented 2026-07-04**
(video_timing v_load 200/312 lines from LANGSEL $C02B bit4; FLOATBUS modes
3 and 6 pass fully, B aligns and stops at the SHR spot like A — 8/11 modes
green); (b) mode 9 = text80 main-byte exposure; (c) modes A/B spot #5/#7/#8 =
SHR SCB/palette fetch cadence; (d) capture-cell↔beam mapping and per-spot
notes are in `doc/floatbus-hbl-fix.md`. Known FPGA issue under investigation:
textfunk flashes alternate frames on the always-on cache build (suspect
mem_stall stretches at native on late SDRAM fills; bisect RBF deployed).
FTA Xmas Demo: not bootable from HDD mount by design (wants 3.5"); cp2
PO→WOZ conversion does not boot in sim (WOZ-loader follow-up).

---

## Quick restart checklist
```bash
cd ~/mister/iigs_simulation && git checkout feat/zipgs-speed && git pull
cd vsim && make
# textfunk guard baseline:
./obj_dir/Vemu --disk textfunk.po --screenshot 438 --stop-at-frame 439 --quiet
md5sum screenshot_frame_0438.png   # expect 7abff109f80d62083437e1c379389fb5
# floatbus (needs FloatBus_260213/FloatBus_260213.po copied to vsim/floatbus.po):
./obj_dir/Vemu --disk floatbus.po --stop-at-frame 400 --screenshot 390
```
Regression: `./regression.sh` (8/8 — the long-standing WOZ 3.5" Arkanoid FAIL was
a corrupt disk image; replaced 2026-07-03, verified independent of RTL changes).

## Pre-existing baggage (not ours)
- `output_files/`, `obj_dir_mmu/`, `db/`, screenshots, `scratchpad/` are build
  artifacts — consider `.gitignore` before merging to master.
