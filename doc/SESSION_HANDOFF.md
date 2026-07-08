# Session Handoff — 2026-07-04/05 (final)

> **HISTORICAL — superseded 2026-07-08.** 14.32 MHz now works on hardware
> (see `doc/zipgs-14mhz-plan.md`); the "sim-only 1-tick race" note below is
> obsolete. Board RBF state has also changed since (old variants live in
> `_Computer/iigs_old/`; the active core is `/media/fat/Apple-IIgs.rbf` —
> note Main resolves MGL `<rbf>` from the SD root first).

**Branch:** `master` == `feat/zipgs-speed`, both pushed (HEAD `eb519ec`).
**Working tree:** clean of source changes (untracked disks/artifacts remain).
**Board (192.168.1.196):** latest build = **`_Computer/Apple-IIgs_fb11.rbf`**
(the everything-build; timing +0.714ns). Older RBFs on the SD are superseded
diagnostics, all safe to delete: `Apple-IIgs_bisect.rbf`, `Apple-IIgs_zipgs_
test.rbf`, `Apple-IIgs_natfix.rbf`, `Apple-IIgs_dhr.rbf`, `Apple-IIgs_dhr2.rbf`,
`Apple-IIgs_shr.rbf`. When fb11 is confirmed, it can replace `Apple-IIgs.rbf`
(the Jun 24 release core).

---

## HEADLINE: FLOATBUS 11/11 — every mode, every spot check

arekkusu's FLOATBUS vaporlock test (`vsim/FloatBus_260213/`) passes
COMPLETELY — the floating bus is cycle-exact to real Mega II hardware.
(Clemens returns 0 for all blanking and lists vaporlock as broken.)
Run at NATIVE speed: enable `` `define DEBUG_FBSPOT `` (iigs.sv ~line 19),
rebuild, `./obj_dir/Vemu --disk floatbus.po --stop-at-frame 1500 --quiet |
grep FBSPOT` → 11 mode markers, zero FAIL lines. Per-spot analysis and the
capture geometry (cell↔beam mapping, its traps) in `doc/floatbus-hbl-fix.md`.

What it took (each its own commit):
| Fix | Commit |
|---|---|
| RDVBL/$C019 edge at the Mega II counter wrap (266px earlier) | d6fb8ba |
| IIgs blanking = open bus (refresh cycles; `cpu_last_bus`) | beba2c5 |
| PAL/50Hz scan from LANGSEL bit 4 (modes 3/6/B are 50Hz tests) | b8688be |
| SHR bus schedule: group-LAST byte visible — pixels 4k+3 via a 160-byte replay buffer, palette 4/slot (cols 9-16 = bytes 3..31), SCB odd-of-pair for the next row at col 17 | da7115a |
| text80 shows the pair's MAIN byte: one-tick fetch-address override at xpos 6 (display consumes video_data only there → invisible) | 6c5aab4 |

---

## ALSO DONE this session

1. **ZipGS ships in one RBF** (46f90a9): accelerator always built in; OSD
   "CPU Speed" (default 2.8 Std) + "ZipGS Registers: Enabled/Disabled"
   (status[15]; Disabled = stock IIgs, speed menu still live as host-only
   turbo). Hardware-validated: ZipDA 6.7MHz, toggle reports "no ZipGS
   present", disk-write DMA at 7.16 (HDD save + 3.5" format/write).
2. **Cycle-exact native memory path** (4ec6274): hardware bisect showed the
   always-on cache stalls broke 2.8 cycle exactness (textfunk flashing, FTA
   demo). New `sdram_burst` ch3 single-word read channel (first-beat ack);
   datapath selected by live speed (`accel_active`). tb_ch3 53/53 (Icarus;
   local verilator is 4.204 — the `--binary` TB scripts need v5, use
   `iverilog -g2012`).
3. **IWM hold-off** (dc6f254): $C0E0-EF access → native for ~2ms (refreshed),
   like a real Zip; fixes ROM3 3.5" boot at 7.16 ("Check startup device").
   Slot-7 HDD stays accelerated.
4. **16-color DHR** (91a288b): AppleColor RGB decode (gssquared
   HiresColorTable → `rtl/dhr_lut.vh`, 11-bit window, DHR_PHASE=0 verified
   against a real PoP title photo). NEWVIDEO[5] honored (A2Desktop sets mono
   itself — bit-identical rendering).
5. **DHR first-byte truncation fixed** (fe69596): every DHR line's first aux
   byte rendered 5-of-7 px shifted right 2 (long-standing, pre-78c4d27; the
   A2Desktop "doubled corner cursor"). Init region emits bits 0/1 directly +
   pre-shifted preload; window [BLE-1, BRE-2]. 12/12 rows pixel-perfect vs
   video memory.
6. **Regression suite: 9 cells** (4f1c785): Total Replay menu + PoP color-DHR
   preview (P,R type-ahead), A2Desktop DHR desktop, new `--fixed-time` sim
   flag (RTC determinism, epoch 1986-09-15). WOZ Arkanoid green (old FAIL
   was a corrupt disk image, replaced 2026-07-03 — verified independent of
   RTL by testing pre-fix RTL against the new disk).
7. **Tools**: `vsim/dhr_validate.py` (renders-vs-memory pixel checker; needs
   `--memory-dump` + screenshot from the SAME run). GSSquared headless as
   ground truth: `SDL_VIDEODRIVER=dummy .../GSSquared -p 5 --disk X
   --screenshot N --stop-at-frame N`. `--woz file.po` auto-converts .po
   floppies. tb_ch3 SDRAM testbench (`vsim/sdram_tb/`, iverilog).

---

## OUTSTANDING

### Hardware validation owed (fb11 RBF — your court)
- textfunk at 2.8 and 7.2; A2Desktop corner cursor; PoP preview color;
  80-column text screens (Pitch Dark / GS/OS finder — text80 datapath got
  the final touch); FTA Xmas Demo pace (first PAL bitstream on the board
  was dhr; fb11 has it too).

### Nice-to-haves / follow-ups
- OSD "Region: NTSC/PAL" = C02BVAL[4] reset value (real PAL IIgs powers up
  at 50Hz; useful for EU software that doesn't poke $C02B). One-line-ish.
- ZipGS: casual game sweep at 7.16; ~~14.32 stays sim-only (1-tick race)~~ (DONE 2026-07-08: 14.32 works on HW — doc/zipgs-14mhz-plan.md);
  $C05C/$C059 cosmetic; $C05A nibble jitter cosmetic.
- $C061-$C067 reads splice `video_data[6:0]` during blanking; real HW would
  show open-bus bits there (minor fidelity).
- DHR floating-bus (AN3=0 + GR + 80col) still shows the aux-biased stream —
  untested by FLOATBUS (no DHR mode in its 11); same xpos-6 trick would
  apply if a test ever demands it, but dhires display consumes video_data
  continuously, so it needs more care than text80 did.
- hires40 could adopt the same 11-bit LUT decode as DHR (gssquared does,
  phase_offset=0) instead of basis-vector artifacting — quality upgrade.
- PAL pixel clock is NTSC-derived → 50.3Hz vs true 50.08 (cosmetic).

### Sim gaps
- cp2-generated WOZs don't boot in sim (Applesauce WOZs do) — WOZ loader
  follow-up. `.po` floppies: use `--woz file.po` (auto-converts, boots).
- FTA Xmas Demo in sim: HDD mount hangs by design (wants a 3.5" drive);
  cp2 conversion doesn't boot (above). Boots fine on FPGA S2.
- `--screenshot-name` is single-shot (last frame wins).

### Older threads (untouched)
- Wolf3D ADB/SRQ WIP — `doc/wolfenstein-3d-iigs-adb-handoff.md`.
- `.gitignore` for build artifacts (output_files/, db/, obj_dir*, pngs).

---

## GUARDS (all must hold at every commit)
1. `cd vsim && ./regression.sh` — 9/9.
2. textfunk: `./obj_dir/Vemu --disk textfunk.po --screenshot 438
   --stop-at-frame 439`, md5 stays `7abff109f80d62083437e1c379389fb5`.
3. FLOATBUS (any timing/bus/video change): 11/11, zero FAIL lines (build
   with DEBUG_FBSPOT, `--stop-at-frame 1500`).
4. DHR pixel truth (any vgc change): `--disk A2DeskTop... --fixed-time
   --screenshot 450 --memory-dump 450 --stop-at-frame 450` then
   `python3 dhr_validate.py screenshot_frame_0450.png
   memdump_frame_0450_slowram.bin 84 12` → 12/12.

## Quick restart
```bash
cd ~/mister/iigs_simulation && git pull && cd vsim && make -j8
./regression.sh                            # expect 9/9
# FPGA build: PATH+=~/intelFPGA_lite/quartus/bin; quartus_sh --flow compile Apple-IIgs (~7 min)
# deploy: sshpass -p 1 scp output_files/Apple-IIgs.rbf root@192.168.1.196:/media/fat/_Computer/...
```
