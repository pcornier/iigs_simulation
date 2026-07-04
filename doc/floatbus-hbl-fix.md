# FLOATBUS vaporlock test — floating-bus accuracy findings

**Status: modes 1,2,4,5,7,8 pass ALL spot checks** (RDVBL edge fix + IIgs
open-bus blanking). Modes 3/6/B are PAL tests (blocked on a 50Hz feature),
mode 9 needs text80 main-byte timing, mode A needs SHR fetch-cadence modeling.
Test: `vsim/FloatBus_260213/` (arekkusu). Run at **native speed only**.

## What the test actually measures (corrected understanding)

The capture is column-major: cell (col, row) at `$4050 + col*262 + row` (NTSC).
Cell (col, row) is read by an `LDA $C05A` whose **phi2 lands at
H = 14*col - 264 (mod 912)** of display line `row` (the store completes 4 CPU
cycles = 56px later). Column mapping: col 0 = Sather hcount $00, cols 1..24 =
$40..$57 (HBL), cols 25..64 = $58..$7F (active cols 0..39).

**The original spec in this doc was wrong on two counts:**

1. **Spot #1 (col 63, row 11) is NOT an HBL cell.** It is *active column 38 of
   line 11* ($2CA6 for HGR p1 = $3E, $4A6 for GR/TXT p1 = $DF/$A0 — exactly the
   `expct1` table). It looked like HBL in our sim because our capture phase was
   shifted 268px late.

2. **The Mega II does not put HBL/VBL scan bytes on the bus at all on a IIgs.**
   The IIe-style Sather HBL scan address (`(0x68+H+V3V4V3V4)&0x78`, no A12 on
   IIe) is real, but on the IIgs those cycles are **slow-RAM refresh: the bus
   is not driven** and the CPU reads back the byte it left there (its own
   operand fetch: $C0 for `LDA $C05A` abs, $5A for the DP form). This is what
   the test's `MG2gs` routine encodes ("MegaII refresh cycles") for spots
   #3/#4 on IIgs. The vaporlock (beacon) sync path is only used on non-GS
   machines; on IIgs the test syncs **purely off the RDVBL ($C019) edge**.

## Fixes landed

- **RDVBL edge (video_timing.v)** — the $C019 VBL flag flipped at the video
  line boundary (hcount==HWL). Real Mega II flips it when its vertical counter
  increments at the counter wrap, 266px earlier (H_M2_WRAP, where m2_v already
  advances). This 266px error was the whole capture phase shift; with it fixed,
  spots #1 and #2 pass in modes 1,2,4,5,7,8 (3/6 see below; 9/A/B need longer
  sim runs). textfunk md5 unchanged.

- **IIgs open-bus blanking (iigs.sv)** — floating-bus reads return `video_data`
  only inside the drive window (Apple II modes: V in [256,448) and
  H in [84,644); SHR: V in [256,456)), else `cpu_last_bus` (last byte the CPU
  transferred, registered at phi2). Targets spots #3/#4 ($C0/$5A expectations).

- A Sather HBL scan-address implementation in vgc.v was written, verified
  display-safe, then **removed** — with open-bus blanking it is unobservable
  on a IIgs.

## Open items

- **Modes 3/6/B (the "Hz"-tagged modes) are PAL tests — DIAGNOSED, needs a
  new feature.** The BASIC shell pokes LANGSEL ($C02B) bit 4 = 50Hz for these
  modes; the ASM re-checks it each syncBeam (sysHZ=$85 confirmed via the FBHZ
  watch) and cycle-counts 312-line frames. Our core stores the bit (C02BVAL)
  but the video timing has no PAL mode, so their captures land ~150 lines
  off. They cannot pass until 50Hz/PAL video timing (312 lines, LANGSEL-
  driven) is implemented.
- **SHR spots #7/#8 (palette/SCB)**: the real VGC fetches the next line's SCB
  + 32 palette bytes in late HBL (capture cols 16-17 ≈ H 872-886) — our VGC
  prefetches them elsewhere in the line, so those cells read open-bus $C0
  instead of palette/SCB bytes. Needs the SHR SCB/palette prefetch moved to
  the line-end window (display-safety: prefetch must still complete before
  the next line's pixels).
- **Mode 9 (TXT2+COL80)**: the real 80-col floating bus shows the MAIN-bank
  byte of the CURRENT column (the test calls COL80 a "nop"), but our text80
  sub-fetch pipeline does not expose that byte at the CPU sample point. A
  `video_data_main` latch was tried with 1- and 2-stage address/data pairing:
  each variant fixed one spot cell and broke another (run 7 instrumentation
  showed the latch never captures the main bytes — the sub-slot bank/data
  phase doesn't admit any fixed delay). Reverted to raw `video_data`; fixing
  this needs the text80 sub-fetches re-timed like the real Mega II (aux first
  half-cycle, main second, CPU latches main).
- $C061-$C067 style reads still splice `video_data[6:0]` into bits 6:0 even
  during blanking; real HW would show open-bus bits there too. Out of scope.

## Guards (all must hold at every commit)

- textfunk: `--disk textfunk.po --screenshot 438 --stop-at-frame 439`,
  md5 of screenshot_frame_0438.png stays `7abff109f80d62083437e1c379389fb5`.
- FLOATBUS: build with `DEBUG_FBSPOT` (rtl/iigs.sv), run
  `--disk floatbus.po --stop-at-frame 1500 --quiet | grep FBSPOT`.
  No regressions vs the per-mode pass/fail table in the session log.
- Full `./regression.sh` green (8/8 — the RDVBL edge fix also resolved the
  long-standing WOZ 3.5" Arkanoid "UNABLE TO LOAD PRODOS" failure).

## Diagnostic tooling (committed, gated)

- `DEBUG_FLOATBUS` (iigs.sv): logs every $C05A floating-bus read with V/H and
  the returned byte.
- `DEBUG_FBSPOT` (iigs.sv): logs the test's per-mode spot results ($301-$303
  writes) plus the snap store to capture cell (63,11) ($80D5), the sysHZ
  variable ($3CB: $06=NTSC/$85=PAL), and the test-phase arg ($300) — enough to
  see each mode's unpk/snap/test/pack flow and Hz decision with beam positions.
