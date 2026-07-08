# Lode Runner WOZ copy-protection hangs on FPGA — HW bisect handoff

**Status (2026-07-08):** Two distinct bugs were found while testing `Lode Runner.woz` at 2.8 and
14.3 MHz on both the Verilator sim and the DE10-Nano board.

- **BUG #1 — 14.3 MHz IWM wedge: FIXED (sim).** Committed on branch `fix/lc-registers`.
- **BUG #2 — protected 5.25" flux read hangs on real hardware: OPEN, but NOT in the core RTL.**
  Sim reproduction is **exhausted** (every modelable/analyzable cause ruled out — see below), and the
  **hardware git-bisect below was RUN and INVALIDATED the core-RTL hypothesis**: the supposed-good
  endpoint `74e3dfd` hangs identically to HEAD (6 builds, all hang; 5/5 repeat boots hang). See the
  "BISECT RESULT" section at the bottom — the regression is **outside the FPGA bitstream** (MiSTer
  HPS/OS environment or the disk image), so a future session should look there, NOT re-bisect the RTL.

This doc supersedes the pre-resolution hypotheses in `doc/loderunner_fpga_debug.md` (that doc's 2026-06-21
"RESOLVED" note was for the OLD pre-accelerator build).

---

## TL;DR for the next session

Lode Runner's half-track + weak-bit copy protection **passes in every sim configuration** (plain,
`SDRAM=sim`, and with realistic track-load latency) — it boots to the title screen and gameplay. On
the **accelerator board build (`ec729648`)** it hangs at the black load screen. Plain 5.25" WOZ disks
(816 Paint, Beagle BASIC) boot fine on the board, so the 5.25 flux path is healthy — only this
protection fails, and only on silicon. The old pre-accelerator build ran it to gameplay on HW.

**⇒ UPDATE: the hardware bisect (below) ran and DISPROVED this — `74e3dfd` hangs too. It is NOT a
core-RTL regression. The cause is outside the bitstream (MiSTer HPS/OS or disk image). See "BISECT
RESULT" at the bottom.**

---

## Symptom & how to reproduce on the board

- Board: DE10-Nano at `192.168.1.196` (see the `fpga-test-rig` memory / `doc/mgl_fpga_testing.md`).
  SSH: `sshpass -p 1 ssh root@192.168.1.196` (root / `1`).
- The board currently carries **exactly one** IIgs bitstream, deployed to BOTH canonical spots and
  byte-identical (md5 `ec729648b108f729cb428aad4070790a` = local `output_files/Apple-IIgs.rbf`):
  - `/media/fat/Apple-IIgs.rbf` (root — MGL `<rbf>` resolves here FIRST)
  - `/media/fat/_Computer/Apple-IIgs.rbf`
  - (All old `_Computer/iigs_old/*.rbf` variants were deleted 2026-07-08 to kill stale-shadow
    ambiguity — a trap that cost time twice before. **Always `find /media/fat -maxdepth 3 -iname
    '*apple*gs*.rbf'` and md5 both copies before diagnosing.**)
- Launch (native / all-zero CFG = pure ROM3 native 2.8 MHz):
  ```sh
  ssh root@192.168.1.196 '
    printf "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" > /media/fat/config/Apple-IIgs.CFG
    cat > /run/lr.mgl <<EOF
  <mistergamedescription>
   <rbf>Apple-IIgs</rbf>
   <file path="/media/fat/games/Apple-IIgs/Lode Runner.woz" delay="2" type="s" index="3" />
   <reset delay="3" hold="1" />
  </mistergamedescription>
  EOF
    echo "menu" > /dev/MiSTer_cmd; sleep 4
    echo "load_core /run/lr.mgl" > /dev/MiSTer_cmd'
  ```
- Screenshot: `POST http://192.168.1.196:8182/api/screenshots` → newest
  `/media/fat/screenshots/Apple-IIgs/*.png`, then `scp` it back.
- **Fail signature:** stuck ~forever on a black graphics box with a blue border (`~3191` byte PNG).
  It got past the boot ROM into Lode Runner's loader (video switched to graphics) but never draws the
  level — the protection read never completes. `Lode Runner.woz` md5 `f491b82b944c8d55c7ce82c3056df556`
  (identical on board and in `vsim/`).
- **Pass signature (what we want):** the level with ladders/gold/guards and
  `SCORE / MEN 003 / LEVEL 001`.

### Controls that discriminate the failure (already run, keep as regression checks)
- `816 Paint v3.1.woz` and `Beagle BASIC.woz` (plain 5.25 WOZ, same slot/index=3) → **boot fine on
  HW** to their menus. So the general 5.25 flux path works on silicon.
- `Apple DOS 3.3 August 1980.dsk` → boots on HW (but `.dsk` may take the nibble path, not flux;
  the two WOZ disks above are the real flux-path controls).
- GS/OS HDD (`/run/gsos14.mgl`, index 0) → boots to Finder desktop → board/core healthy.

---

## What was ruled out (sim + static analysis — all NEGATIVE)

| Hypothesis (doc/loderunner_fpga_debug.md) | Verdict | Evidence |
|---|---|---|
| **#3 Track-load latency** | ❌ not it | Added `WOZ_ACK_DELAY` env knob (`vsim/sim/sim_blkdevice.cpp`; default 2 = instant, regression-safe). `WOZ_ACK_DELAY=1200 ./obj_dir/Vemu --woz "Lode Runner.woz" --speed 0` **boots to gameplay** (frames 1500 & 2500 = live play), just ~400 frames later. Sim passes the protection even at realistic per-block SD latency. |
| **#2 Timing closure** | ❌ not it | `quartus_sta` on the existing `output_files` DB: overall setup slack POSITIVE (clk_mem +1.381 ns, HDMI +0.220 ns, all met); **no flux/iwm/woz nodes among the worst paths** (they have margin). |
| **Memory coherency (accelerator cache/burst)** | ❌ not it | `make SDRAM=sim` (FPGA-accurate burst+cache+ch3 path WITH the golden `SDRAMSIM_VIOLATION` checker) running LR native: **0 violations** through the entire boot. |
| **Memory-path timing** | ❌ not it | Same `SDRAM=sim` run reaches the **Lode Runner title screen at frame 950** (`vsim/lr_shots/sdramval_TITLE_f950.png`) — which only appears AFTER the protection passes. |
| **Weak-bit LFSR (sim vs HW)** | ❌ not it | Deterministic 16-bit LFSR (seed `0xACE1`, `flux_drive.v`), identical in sim and on FPGA — per `doc/loderunner_fpga_debug.md`. |

Audit of `rtl/sdram_burst.sv` arbitration (lines ~150–196) confirms the native path is coherent by
inspection: `ch0` (write) has **higher priority** than `ch3` (read) at `STATE_IDLE`, plus
write-recovery guard states — so native write-then-read-same-address is ordered write-first. GS/OS
booting + byte-identical `gsos` regression corroborate.

**Conclusion:** no zero-delay simulator and no static-timing model reproduces or flags it. BUG #2 is
an analog/real-silicon effect (flux edge sampling / setup-hold on a path STA doesn't cover /
metastability) that only manifests on the accelerator hardware build.

---

## The bisect plan (next session starts here)

Goal: find the commit in `74e3dfd..HEAD` (branch `fix/lc-registers`) that broke the protection on HW.
Old build `74e3dfd` ("Apply 5.25 half-track track_id fix to FPGA top-level") ran LR to gameplay on
HW (2026-06-21). Current `HEAD`/board build hangs.

**Strong prior:** the accelerator is the biggest change and is in the datapath even at native
(`ACCEL_SDRAM` always builds it). First split point = a **pre-accelerator** commit.

Suggested first bisect build: **`ee543dc`** ("mmu: extract memory decode…") — it has the 5.25
half-track flux fix and the MMU extraction but **not** the SDRAM accelerator (which lands at
`efc3f18` / `c4d3985` / `b63f4d0`). If LR boots on HW at `ee543dc` → the accelerator broke it
(~6-commit range: `efc3f18, 8305fcb, 9284ce7, c4d3985, b63f4d0, …`). If it still hangs at `ee543dc`
→ suspect the MMU extraction (`ee543dc`) or LC (`7b98fde`) or the earlier floppy-hold-off commits
(`dc6f254` "native-speed hold-off around IWM access", `205f2f6` "keep accelerator native during
floppy-motor").

Full disk-path change list `74e3dfd..HEAD` (newest→oldest, prime suspects **bold**):
`f3372fa df5460f 7b98fde` **`205f2f6`** `60f91f9 41c3442 da7115a` **`dc6f254`** **`4ec6274`** `b8688be`
**`46f90a9`** `beba2c5 … ` **`efc3f18`** (accelerator) `… ` **`ee543dc`** (mmu) `8f5394d …`

### Build & deploy loop (Quartus is available locally)
- Toolchain: `~/intelFPGA_lite/quartus/bin/{quartus_sh,quartus_sta,quartus_pgm}` (verified present).
- Project: `Apple-IIgs.qpf` / `Apple-IIgs.qsf` in the repo root. Output → `output_files/Apple-IIgs.rbf`.
  Ensure `ACCEL_SDRAM` is set the same way the board build was (it's ON in the shipped build —
  check the qsf). A full compile is ~40 min.
- **Use a git worktree** so the current working tree (with the committed #1 fix + this doc) is not
  disturbed: `git worktree add ../iigs_bisect <commit>` then build there.
- Deploy the built `output_files/Apple-IIgs.rbf` to **both** `/media/fat/Apple-IIgs.rbf` (root) AND
  `/media/fat/_Computer/Apple-IIgs.rbf`, verify md5 on the board matches the local build, then run
  the launch recipe above. (Stale-RBF trap: always verify which file Main loaded.)

### If bisect narrows to the accelerator
Likely mechanisms to examine on HW (sim clean, so look for silicon-only effects):
- Real track-load / chunk-reload timing on the flux BRAM path (`rtl/woz_floppy_controller.sv`
  `sd_lba`/`ready`, `rtl/flux_drive.v` chunk streaming at line ~452) — a CDC or handshake that races
  only at real SD latency (the `31fbf1a` cache CDC bug was this class).
- The `dc6f254`/`205f2f6` IWM/floppy native-hold logic perturbing flux-read cycle timing.
- SignalTap on `woz_track1_id`, `WOZ_TRACK1_QTRACK`, `flux_drive` `head_phase`, `sd_lba`,
  `track_load_complete`, `ready`, and the IWM flux-read state during the protected seek (qtrack ≈ 54).
  ⚠️ HW observability has been flaky here: SignalTap `.stp` rejected by Q17 (warning 262004), pixel
  overlay renders in sim but not on FPGA, `ddr_trace` wrote nothing. Budget time for tooling.

---

## Handy sim commands (fast iteration; plain build)

```sh
cd vsim
make                      # default (plain-sim) build
make SDRAM=sim            # FPGA-accurate memory + SDRAMSIM_VIOLATION golden checker (slow, ~85 fps-sim)
# reach the title screen (~frame 950) = protection passed:
./obj_dir/Vemu --woz "Lode Runner.woz" --speed 0 --headless --quiet --no-cpu-log --screenshot 950 --stop-at-frame 1200
# model realistic SD track-load latency:
WOZ_ACK_DELAY=1200 ./obj_dir/Vemu --woz "Lode Runner.woz" --speed 0 --headless --quiet --no-cpu-log --screenshot 1500 --stop-at-frame 1510
```
`--quiet` suppresses the CPU trace (big speedup). `--no-cpu-log` alone does NOT (stdout trace stays on).

Reference screenshots collected in `vsim/lr_shots/` (untracked): `fpga_lr_clean_native.png` (HW hang),
`fpga_816paint.png` / `fpga_beaglebasic.png` (HW 5.25 controls pass), `repro_ack1200_GAMEPLAY_f1500.png`
and `sdramval_TITLE_f950.png` (sim passes the protection).

---

## BUG #1 (FIXED) — 14.3 MHz IWM wedge, for the record

At `--speed 4` the ROM's `SETIWMMODE` (`Bank FF/ad35driver_subroutines.asm` @ `$4710`) wedged forever
in the mode-register verify loop at `FF:4720` (`sty $c0ef / eor $c0ee / and #$1f / bne`). Root cause:
the plain-sim datapath (`vsim/sim.v:168`) lacked the datapath-switch guard that the `SDRAM_SIM` path
and `Apple-IIgs.sv` already have. The IWM `$C0Ex` hold-off flips `accel_active_w` 1→0 mid-run; the
registered BRAM read is one CLK_14M tick late and returned the PREVIOUS byte on the first native cycle
after the switch — so `BIT $C0ED`'s operand at `FF:4715` read back `$2C`, the CPU ran `BIT $C02C`, IWM
Q6 was never set, and the loop never matched. Fix: ported the 2-cycle accel-switch guard
(`accel_r_plain` / `accel_guard_plain`, serve the comb read during the switch) to `sim.v:168`.
Verified: CPU decodes `bit $c0ed`; Lode Runner boots to gameplay at `--speed 4`; **all 10 regression
tests pass** (guard is dormant at native → byte-identical). This was a SIM-ONLY path bug; the FPGA
already has the guard, so it is unrelated to BUG #2.

---

## BISECT RESULT (2026-07-08): NOT a core-RTL regression — look outside the bitstream

Ran the hardware bisect above (6 Quartus builds, ~6 min each). **Every commit tested hangs LR on
current hardware, including `74e3dfd` — the supposed-good endpoint.** Results (all black-box HANG,
~3191-byte screenshot): `74d3b23`, `220a7aa`, `e811002`, `0c3783f`, and `74e3dfd`. Plus 5/5 repeat
boots of the current build all hang (not a marginal weak-bit coin-flip).

`sys/` (the MiSTer framework) IS git-tracked, so the `74e3dfd` build used `74e3dfd`'s framework too —
so this is **not** a framework regression either.

**Conclusion:** LR's copy protection fails consistently on the current board across the *entire* core
RTL history (`74e3dfd..HEAD`) while passing in every sim mode. Since it worked on this exact board on
2026-06-21, the regression is **outside the FPGA bitstream / this git repo** — i.e. the **MiSTer Main
(HPS) binary or the SD-card OS/environment** (which serves the raw WOZ `sd_buff` blocks and is not
versioned here), or the specific `.woz` on the SD.

### Where to look next (all non-RTL)
1. **MiSTer OS / `Main_MiSTer`**: was it updated on the SD since 2026-06-21? The HPS binary serves the
   WOZ block reads (`sd_lba`/`sd_buff`). A change to its floppy/`sd_rd` timing or block serving would
   hit LR's marginal protection but not normal disks. Try reverting/pinning `/media/fat/MiSTer` to a
   June build.
2. **Different `Lode Runner.woz`**: try another dump of the disk on HW. The current one
   (`f491b82b944c8d55c7ce82c3056df556`) passes in sim, but a different pressing/dump might behave
   differently on silicon.
3. **Compare the board's SD contents / config** to the 2026-06-21 state if any backup exists.
4. Re-confirm the 2026-06-21 "works on HW" observation was this exact disk + board + launch.

The build/deploy/test harness (`scratchpad/bisect_step.sh`) and per-step screenshots
(`vsim/lr_shots/bisect_*.png`) are kept for reference. **Do not re-bisect the core RTL — it's proven
the bug is not there.**

---

## PROTECTION ALGORITHM STUDY (2026-07-08)

Studied the protection to look for a targeted flux-model fix (no builds). Findings:

- **The protection IS the data placement.** Parsing the WOZ1 TMAP (`scratchpad/wozparse.py`) shows the
  game data is stored on **quarter/half-tracks** a whole-track bit-copier misses: track 13 has data at
  `.00/.25/.50` (TRKS 11,12,13), track 14 has data ONLY at `.50/.75` (TRKS 14,15) — nothing at
  14.00/14.25 — and this pattern repeats up the disk. There is no separate "check + branch"; the
  loader simply must reach these fractional tracks to load the game.
- **Sim reads them correctly.** A head-position trace (`WOZ_TRACK1_QTRACK`) over the LR boot shows the
  loader sweeping quarter-track by quarter-track; `woz_track1_id = qtrack-2` maps each to the right
  TMAP index and the sim reads every data track, reaching the title screen (protection passes).
- **The flux model is deterministic RTL.** The 5.25 4-phase stepper (`flux_drive.v` ~L664), flux
  playback (`flux_phase_accum`, inc=1000/mod=1790), and weak-bit injection (`0xACE1` LFSR, triggers on
  >=4 zero-run) are all clocked on `CLK_14M` — no analog/timing dependence in the model, which is
  exactly why sim faithfully reproduces the protection.
- **The RE repo** (github.com/XekriRedmane/lode_runner_reveng) is a **cracked** disk
  (`..._cr_Reset_Vector`) re-mastered onto normal tracks; `main.asm` documents the game (standard
  track/sector RWTS for level/hi-score data on tracks 3+) but NOT the original half-track protection.
- **Latency stress is confounded.** Raising `WOZ_ACK_DELAY` (2 -> 1200 -> 8000) just stretches the
  whole boot (the load finishes at a later frame), so it can't cleanly reproduce a *hang* vs slow-load;
  it does not reproduce the HW failure.

**Study conclusion:** our flux model is a faithful, deterministic implementation of the half-track +
weak-bit read (hence sim passes at every latency). There is **no statically-identifiable RTL fix** —
the silicon failure is a physical flux/stepper/sampling-timing effect on the FPGA that a zero-delay
simulator cannot reproduce and STA does not flag. Combined with the bisect (fails at every commit
incl. the old good one) and the user's report that a fresh disk copy changes nothing, the most likely
truth is that LR's fractional-track protection **has never reliably worked on this silicon** — a
known sim-vs-FPGA fidelity limitation, not a regression. Closing it out requires on-hardware
observability (pixel-overlay/LED probe of head qtrack + address-mark-found + flux-read state during
the protected read), which this project's HW debug tooling has historically made unreliable.
