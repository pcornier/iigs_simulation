# Lode Runner: works in sim, fails on FPGA — debug handoff

**Branch:** `fix/loderunner-woz-halftrack` @ `74e3dfd`.
**Symptom:** Lode Runner (5.25" WOZ, half-track + weak-bit copy protection) boots to gameplay in
the Verilator sim, but does **not** work on the FPGA.

## TL;DR — there is (probably) no RTL bug to patch

The half-track `track_id` fix is **already applied to the FPGA top-level, identically to the sim**:

- `7071fc1` added the shared plumbing (`flux_drive` exposes `HEAD_QTRACK` → `WOZ_TRACK1_QTRACK`
  through `iwm_woz`/`iigs`) and the real fix `track_id = qtrack − 2`, but **only in `vsim/sim.v`**.
- `74e3dfd` applied the **same** `woz_track1_id = (WOZ_TRACK1_QTRACK >= 2) ? QTRACK−2 : 0` and
  `.track_id(woz_track1_id)` wiring to **`Apple-IIgs.sv`**.

Verified equivalences (sim.v vs Apple-IIgs.sv): the `woz_track1_id` expression is byte-identical;
the `WOZ_TRACK1_QTRACK` routing is identical; the 5.25" `woz_floppy_controller` instances are
equivalent (only cosmetic diffs: SD slot index, an unused `ready`/`disk_type_mismatch`).

Also ruled out:
- **No `\`ifdef SIMULATION`** behavioral forks anywhere in the disk RTL — sim and FPGA execute the
  same disk logic.
- **Track data is served the same way** in both (controller `sd_lba`/`sd_buff` path; C++ feeds it
  in sim, HPS in FPGA — same RTL mechanism, no "smart" sim shortcut).
- **Weak bits** are a deterministic 16-bit LFSR (seed `0xACE1`, `flux_drive.v`), designed to vary —
  not a sim/FPGA discriminator.

⇒ The sim↔FPGA gap is **environmental** (build / timing / hardware), not the track_id logic.
A blind RTL edit is not warranted and can't be validated without the board.

## Ranked hypotheses

1. **Bitstream doesn't actually contain `74e3dfd`** (not rebuilt/reflashed, or built from `7071fc1`
   which fixed *only* the sim). This is the #1 trap — `74e3dfd` exists *because* sim≠FPGA was caught
   once already. Cheapest to rule out.
2. **Timing closure.** Copy protection reads precise flux/weak-bit edges; FPGA setup/hold violations
   (invisible to the zero-delay sim) make the marginal flux read fail while normal disks tolerate
   it. This branch has timing-closure history.
3. **Real-time timing / track-load latency.** Half-track seeks change `track_id` by 1–2 (not 4), so
   the protection may re-seek/re-read rapidly. On FPGA each track (re)load goes through HPS/SD with
   real latency; in the sim C++ serves it ~instantly. The protected read can time out on hardware
   waiting for the track that the sim always has ready. Also the address-mark search depends on the
   CPU-cycles↔flux-time relationship matching real silicon.
4. **HPS/SD serving** differences (less likely — other WOZ disks boot on FPGA).
5. **Wrong/corrupt Lode Runner `.woz` on the SD card** vs the sim's file.

## Debug plan (cheapest first; FPGA has no stdout)

### A. Cheap checks (no code, do these first)
1. **Characterize the symptom**: black screen at boot (== pre-fix), or does it seek/spin then hang
   later? Drive LED/motor activity? Black-screen-identical-to-pre-fix ⇒ suspect the build (#1).
2. **Confirm the build**: rebuild this branch HEAD, confirm `74e3dfd` is in the compiled `Apple-IIgs.sv`,
   reflash.
3. **Quartus timing report**: check setup/hold violations, especially `CLK_14M`/IWM/flux paths and
   the new `WOZ_TRACK1_QTRACK` combinational chain. Fix violations — protection breaks first.
4. **Same `.woz`**: checksum the SD-card Lode Runner image against the one used in the sim.
5. **Narrow the class** on FPGA: boot a known **non-protected 5.25" WOZ** (does the general 5.25"
   path work on hardware at all?), and boot **Arkanoid IIgs** (3.5" weak-bit protection — if it
   works, weak bits/flux are fine on hardware, narrowing to the 5.25"/half-track path).

### B. Sim "golden trace" (reference for the FPGA comparison)
Run Lode Runner in the sim and log, around the protected seek:
- `woz_track1_id` and `WOZ_TRACK1_QTRACK` (the new signals) and `drive525` `head_phase`
- track loads: `track_load_complete`, the requested track, `woz_valid`/`disk_mounted`
- the existing `WOZ_*` probes in `vsim/sim_main.cpp` (`WOZ_GRABHEADR`, `WOZ_TRYMORE`,
  `WOZ_DM_TIMEOUT`, `WOZ_BASICSTAT`, etc.)

Where to add it: a `$display` in `vsim/sim.v` on `woz_track1_id` change is simplest, or a
`verilator_public` probe in `sim_main.cpp`. Capture the sequence for the protected "track 14"
(expected: head → qtrack 54, TMAP index 54 loads real data, address mark found, gameplay).

### C. SignalTap on hardware (pinpoint the divergence)
Probe the same signals on the board during the Lode Runner boot:
`woz_track1_id`, `WOZ_TRACK1_QTRACK`, `drive525` `head_phase`, `sd_lba` / `track_load_complete` /
`woz_valid`, and the IWM flux-read state. Trigger when the head reaches the protected half-track
(qtrack ≈ 54) or on the seek. Compare to the golden trace; the divergence point localizes it:
- **wrong `track_id`** → stepper/real-time timing (head parks at a different qtrack)
- **track never loads / loads late** → SD/HPS latency (#3) or serving (#4)
- **flux read stalls / address mark never found** → timing closure (#2) or weak-bit/flux timing

### D. If SignalTap isn't wired — coarse LED/OSD probe
Latch go/no-go signals to LEDs: e.g. "head reached qtrack 54 **and** `track_load_complete` **and**
`woz_valid`" → LED1; "IWM stuck in address-mark search > N ms" → LED2. Cheap visibility without a
logic analyzer.

## Lead suspicion
If the build genuinely contains `74e3dfd`, the prime suspect is **timing** (#2/#3): the track_id
logic is provably identical to the sim, so what's left is the analog-ish flux/seek/track-load
timing fidelity that only real silicon exposes. Steps A1–A2 are cheap enough to do first regardless.

## Key files / commits
- Fix commits: `7071fc1` (sim.v + shared plumbing), `74e3dfd` (Apple-IIgs.sv).
- Weak-bit commits: `401fd3a` (LFSR flux weak bits), `ee95685` (bitstream weak bits).
- `rtl/flux_drive.v` — `HEAD_QTRACK`, `head_phase` stepper, LFSR weak bits, flux playback timing.
- `rtl/iwm_woz.v` / `rtl/iigs.sv` — `WOZ_TRACK1_QTRACK` routing.
- `Apple-IIgs.sv` (FPGA top) / `vsim/sim.v` (sim top) — `woz_track1_id`, 5.25" controller instance.
- `rtl/woz_floppy_controller.sv` — TMAP lookup, track load, `track_load_complete`.
- `vsim/sim_main.cpp` — existing `WOZ_*` probes + GS/OS address→name tables.

## Note for the FPGA-side LLM
You can build/flash/probe; this analysis was done where that wasn't possible. Start at A1–A2
(symptom + confirm the bitstream has `74e3dfd`). Don't re-patch `track_id` — it's already correct
and identical to the working sim; changing it will likely break the sim without fixing the board.

## RESOLUTION (2026-06-21) — it works on the FPGA; there was no RTL bug

Lode Runner **boots to gameplay on real hardware** with the deployed bitstream (built from this
branch, contains `74e3dfd`). Verified over USB Blaster JTAG + MiSTer remote: the protected disk
loads and runs identically to the sim (same level/score/attract animation). Reaching gameplay means
the half-track + weak-bit copy protection **passes on silicon** — the `track_id = qtrack − 2` fix is
correct on FPGA, exactly as predicted here.

The earlier "fails on FPGA" symptom was a **disk-mount / launch artifact, not an RTL fault**: the
`.woz` was never actually getting mounted, so the boot ROM found no startup device (blue
"Check startup device!" screen) and the protected read never even happened. The lead suspicion
above (timing closure / track-load latency) was a false trail — moot once the disk actually mounts.

How to launch it remotely (for future regression on hardware), via `/dev/MiSTer_cmd`:
- `load_core <mgl>` re-execs MiSTer and runs the MGL menu-navigation state machine, which mounts
  `type="s"` SD images and can also issue a `<reset>`. Two gotchas that cost time here:
  1. **MGL `<file>` `path` must be absolute** (leading `/`). A relative path is resolved against
     `HomeDir()` = the core's games dir (`/media/fat/games/<core>`), so `games/Apple-IIgs/x.woz`
     gets doubled to `…/games/Apple-IIgs/games/Apple-IIgs/x.woz`, the file isn't found, and the
     mount **silently** fails (`menu.cpp` "F/S option not found -> deactivate mgl").
  2. The IIgs 5.25 boot is one-shot, and the MGL mounts the disk *after* the cold-boot scan, so the
     MGL needs a trailing `<reset>` to re-scan with the disk present.
- Working MGL (5.25" = slot index 3, `type="s"`):
  ```xml
  <mistergamedescription>
   <rbf>Apple-IIgs</rbf>
   <file path="/media/fat/games/Apple-IIgs/Lode Runner.woz" delay="2" type="s" index="3" />
   <reset delay="3" hold="1" />
  </mistergamedescription>
  ```

Bottom line: **no SignalTap and no RTL change were needed.** The fix is correct and shipped; this
doc's pre-resolution hypotheses are retained above only for historical context.
