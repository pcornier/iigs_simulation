# CPU Speed / Timing — Comparison and Fixes

Investigation into whether the core's 65C816 runs at the right speed, how it compares to reference
emulators, and two timing-accuracy fixes that came out of it.

## TL;DR

- The core's CPU timing is **accurate**. On the BENCHMARKv5 (TML Pascal) suite it matches **gssquared**
  — the most carefully-tuned reference — within ~1% on integer/loop code.
- **Clemens runs ~9% too fast** because it does not model Mega II RAM refresh. A real IIgs *has* refresh
  (`doc/fpi_timing.md`), so our slightly-higher numbers are the correct ones.
- Two accuracy fixes landed on branch `fix/iolc-ntsc-stretch` (`rtl/clock_divider.v`): an **IOLC shadow
  gate** for I/O sync cycles, and the **NTSC per-scanline stretch**.
- One open item: on **floating-point (SANE) tests we are ~8% *faster* than gssquared** — a 65C816
  per-instruction cycle-count difference, not a clock-divider issue.

## The timing model

`rtl/clock_divider.v` implements the FPI (Fast Processor Interface) clock. Units are 14.318 MHz "ticks".

| Cycle type | Ticks | Rate | When |
|---|---|---|---|
| Normal fast | 5 | 2.864 MHz | fast RAM/ROM, speed=fast |
| Fast refresh | 10 | — | every 10th fast-RAM cycle (ROM hides it) |
| Slow | 14 | 1.023 MHz | speed=slow (`$C036` bit 7 = 0) |
| Sync | 14–27 | — | fast CPU touching the 1 MHz bus (phase-locked to PH0) |

Effective fast-RAM rate with refresh ≈ **2.60 MHz**; ROM runs full 2.864 MHz. This matches
`doc/fpi_timing.md` (the Kruszyna FPI paper). The five conditions that force a SYNC/slow cycle —
speed=slow, enabled Disk-II motor, shadowed-video write, I/O `$C0xx`, banks `$E0/$E1` — all match the
spec's list, as do the I/O exceptions (FPI registers `$C035/36/37` fast r/w; SLOT/STATE `$C02D/$C068`
fast read, slow write).

## Reference emulators (`software_emulators/`)

| Emulator | Fast cycle | Refresh | Notes |
|---|---|---|---|
| **gssquared** (`src/NClock.hpp`) | 5×14M (2.857) | every 10th cycle, +5 → 10 | closest model; +2/scanline NTSC stretch |
| **Clemens** (`clem_cycle.h`, `clem_shared.h`) | 1000 = 5×200 (2.864) | **not modeled** → too fast | same base constants as us |
| **gsplus** (`sim65816.c`) | flat **2.5 MHz** | none (baked in) | loosest |
| **Our core** | 5 ticks (2.864) | every 10th = 10 ticks | matches gssquared |

## BENCHMARKv5 / TML Pascal results

Time in 60ths of a second — **lower = faster**. To run: `./obj_dir/Vemu --disk BENCHMARKv5.2mg`, then
`1`+Return (option 1), Return (set base speed), `1`+Return (times to run). Results appear ~frame 9500
(the sim is ~4 fps, so this is a ~30-minute run; use `--quiet`).

| Test | Clemens | gssquared | **Ours** | ours vs gssquared |
|---|---|---|---|---|
| Sieve of Eratosthenes (primes) | 373 | 409 | **407** | −0.5% |
| Selection sort (500 strings) | 1108 | 1154 | **1143** | −1.0% |
| Floating point (100 iter) | 454 | 485 | **445** | **−8.2%** |
| FPE Gamm units (instruction mix) | 1466 | 1569 | **1448** | **−7.7%** |
| Fibonacci (10 iter) | 1825 | 2006 | **1993** | −0.6% |
| Integer math (5000 iter) | 1413 | 1589 | **1544** | −2.8% |

**Reading the table:** on the integer/loop tests (primes, sort, Fibonacci) we land within ~1% of
gssquared, and ~3% on integer math — i.e. we are **not** too slow. Clemens is the fast outlier (no
refresh). The FP/FPE rows are the exception — see "open item" below.

## The two fixes (branch `fix/iolc-ntsc-stretch`)

### 1. IOLC shadow gate
`$C0xx` accesses in banks 00/01 now incur a SYNC (slow) cycle **only when I/O+Language-Card shadowing is
enabled** (`shadow[6] = 0`). When inhibited (`shadow[6] = 1`) that range is plain fast RAM and must not
be slowed. Matches gssquared's `is_iolc_shadowed()`. Normal operation has `shadow[6] = 0`, so the common
path is unchanged — this only fixes the rare IOLC-disabled case.

### 2. NTSC per-scanline stretch
The clock divider now counts PH0 cycles (65 per scanline) and adds **2 ticks to one fast cycle per
scanline**, so the CPU's effective line = 65×14 + 2 = **912 ticks**. This matches the VGC's 912-tick
line (`rtl/vgc.v` `HTOTAL = 911`) and gssquared's `extra_per_scanline = 2`. Previously the CPU (910/line)
and video scanner (912/line) **drifted by 2 ticks per scanline**; this re-aligns them over a frame.
Speed effect is small (~0.22%). (The `stretch` input to `clock_divider` — previously hard-wired to
`1'b0` at `iigs.sv:2629` — is superseded by this self-contained scanline counter; a fully VGC-tied
stretch is a possible future refinement.)

### Validation
- **ROM speed self-test 5** (`customtests/selftest05.2mg`): `TEST 05  00 PASS`.
- **Regression**: 7 PASS / 1 FAIL (only the pre-existing WOZ-Arkanoid failure). GS/OS, Total Replay,
  Arkanoid (all video-heavy) pass — no video-timing regression.
- **BENCHMARKv5**: numbers stay sane; the larger tests shift slightly toward gssquared
  (Integer 1542 → 1544, Fibonacci 1992 → 1993).

## Open item: floating-point path is ~8% too fast

On the FP and FPE tests we are ~8% faster than gssquared (445 vs 485, 1448 vs 1569) — the opposite
direction from everything else, and roughly matching Clemens. Floating-point (SANE) is ROM-heavy, so
this is **not** a clock-divider effect; it points to a **65C816 per-instruction cycle-count difference**
on the FP/SANE code path (either we under-count cycles for some instructions, or gssquared's FP memory
access hits more sync cycles). It makes us too *fast*, not slow, but it is the kind of cycle-exactness
that matters for the demos gssquared targets — worth auditing next.

## Quick speed check
Boot `customtests/selftest05.2mg` — it runs ROM speed test 5 in isolation and shows a clear
`TEST 05  00 PASS` / fail by ~frame 1800 (much faster than the full `--selftest` or the benchmark).
