# Session Handoff — 2026-07-04/05

**Branch:** `master` == `feat/zipgs-speed`, both pushed (HEAD `fe69596`).
**Working tree:** clean of source changes (untracked disks/artifacts remain).
**Board (192.168.1.196):** latest build = `_Computer/Apple-IIgs_dhr2.rbf`.
Superseded diagnostics still on the SD: `Apple-IIgs_bisect.rbf`,
`Apple-IIgs_zipgs_test.rbf`, `Apple-IIgs_natfix.rbf` — safe to delete once
dhr2 is confirmed; `Apple-IIgs.rbf` (Jun 24 release) can be replaced by dhr2.

---

## DONE this session (each hardware- or pixel-validated)

1. **Floating-bus accuracy** — RDVBL/$C019 edge moved to the Mega II counter
   wrap (266px earlier, `video_timing.v`); IIgs blanking = open bus
   (`m2_bus_driven` + `cpu_last_bus`, `iigs.sv`). FLOATBUS spots #1-#4 pass.
2. **PAL/50Hz scan** — LANGSEL $C02B bit 4 → 312-line frames (Sather preset
   $C8), switches at frame wrap. FLOATBUS modes 3/6 pass.
3. **ZipGS shipping config** — accelerator always built in (single RBF); OSD
   "CPU Speed" live (default 2.8 Std); new OSD "ZipGS Registers:
   Enabled/Disabled" (status[15]); speed menu NOT grayed when registers off
   (host-only turbo is a feature). ZipDA reads 6.7MHz; Disabled → "no ZipGS
   present". Disk-write DMA validated at 7.16 (HDD save, 3.5" format+write).
4. **Native-speed memory path (ch3)** — hardware bisect proved the always-on
   burst+cache stalls broke cycle exactness at 2.8 (textfunk flashing, FTA
   demo). New `sdram_burst` ch3 single-word read channel (first-beat ack);
   top selects datapath by live speed (`accel_active`). tb_ch3 53/53
   (Icarus — NOTE: local verilator is 4.204; the `--binary` TB scripts need
   v5, use `iverilog -g2012`).
5. **IWM hold-off** — any $C0E0-EF access forces native for ~2ms (refreshed),
   like a real Zip; fixes ROM3 3.5" boot at 7.16 ("Check startup device").
   Slot-7 HDD ($C0Fx) stays accelerated.
6. **16-color DHR** — AppleColor RGB decode (gssquared HiresColorTable →
   `rtl/dhr_lut.vh`, 11-bit window, DHR_PHASE=0 verified against a real PoP
   title photo). NEWVIDEO[5] honored (set=mono; A2Desktop sets it itself).
7. **DHR first-byte truncation** — every DHR line's first aux byte rendered
   5-of-7 px shifted right 2 (long-standing, pre-78c4d27). Init region now
   emits bits 0/1 directly + pre-shifted preload; window [BLE-1, BRE-2].
   A2Desktop = 12/12 rows pixel-perfect vs video memory.
8. **Regression suite hardened** — 9 tests: Total Replay now types P,R and
   guards the PoP color-DHR preview (frame 300) + menu (130); new A2Desktop
   DHR cell (frame 450); new sim `--fixed-time` flag (RTC determinism, epoch
   1986-09-15); WOZ Arkanoid green (old FAIL was a corrupt disk image, not
   RTL — replaced 2026-07-03).
9. **New tools** — `vsim/dhr_validate.py` (renders-vs-memory pixel checker;
   needs `--memory-dump` + screenshot from the SAME run — the cursor draws
   into video memory). GSSquared headless works as ground truth:
   `SDL_VIDEODRIVER=dummy .../GSSquared -p 5 --disk X --screenshot N
   --stop-at-frame N`.

---

## OUTSTANDING

### FLOATBUS — COMPLETE: ALL 11 MODES PASS ALL SPOT CHECKS (2026-07-05)
Run: enable `` `define DEBUG_FBSPOT `` (iigs.sv ~line 19), rebuild,
`./obj_dir/Vemu --disk floatbus.po --stop-at-frame 1500 --quiet | grep FBSPOT`
— a full pass prints only the 11 mode markers, no FAIL lines.
Full per-spot analysis in `doc/floatbus-hbl-fix.md`.

- ~~Mode 9 (TXT2+COL80)~~ **FIXED**: the text path consumes video_data only
  at xpos 6 (char ROM lookup), so a one-tick fetch-address override there
  puts the pair's MAIN byte on video_data exactly at the CPU sample tick
  (xpos 0 of the aux half), invisible to the display (`fb_main_slot`).
- ~~Modes A/B (SHR)~~ **FIXED (2026-07-05): modes A and B pass ALL spots.**
  Bus model: every fetch group shows its LAST byte (pixels = byte 4k+3 via a
  160-byte replay buffer; palette = 4/slot, cols 9-16 = bytes 3..31; SCB =
  even/odd pair for the NEXT row, odd byte at col 17). Display pipeline
  untouched. Note the capture geometry trap: cells (c, r) for the late-HBL
  columns read at the END of line r-1.
- Minor: $C061-$C067 reads splice `video_data[6:0]` into bits 6:0 during
  blanking; real HW would show open-bus bits there.

### ZipGS / accelerator
- Broader title sweep at 7.16 (casual; disk-write DMA + GS/OS already pass).
- 14.32 MHz remains sim-only (1-tick posted-write/miss-stall race on HW).
- $C05C per-slot mask + $C059 cache-disable stored but cosmetic.
- $C05A speed-nibble jitter in the CDA display (cosmetic).

### PAL
- Optional OSD "Region: NTSC/PAL" = C02BVAL[4] reset value (a real PAL IIgs
  powers up at 50Hz; useful for European software that doesn't poke $C02B).
- Pixel clock is NTSC-derived → 50.3Hz vs true 50.08 (cosmetic).
- Verify FTA Xmas Demo runs at correct 50Hz pace on the dhr2 RBF (it ran on
  the no-PAL bisect build, just ~20% fast).

### Sim gaps
- cp2-generated WOZs don't boot in sim (Applesauce WOZs do) — WOZ loader
  follow-up. Workaround for .po floppies: `--woz file.po` auto-converts.
- FTA Xmas Demo in sim: HDD mount hangs by design (wants a 3.5" drive);
  cp2-conversion doesn't boot (above). Boots fine on FPGA S2.
- `--screenshot-name` is single-shot (last frame wins) — fine, just know it.

### Hardware validation owed (dhr2 RBF)
- A2Desktop corner cursor clean; PoP preview colors; textfunk still solid;
  quick hires-game glance (vgc.v was touched).

### Older threads (untouched this session)
- Wolf3D ADB/SRQ WIP — `doc/wolfenstein-3d-iigs-adb-handoff.md`.
- hires40 could share the 11-bit LUT decode (gssquared does, phase_offset=0)
  instead of the basis-vector artifacting — potential quality upgrade.
- `.gitignore` for build artifacts (output_files/, db/, obj_dir*, screenshots).

---

## GUARDS (all must hold at every commit)
1. `cd vsim && ./regression.sh` — 9/9 (includes both DHR cells; A2Desktop
   uses `--fixed-time`).
2. textfunk: `./obj_dir/Vemu --disk textfunk.po --screenshot 438
   --stop-at-frame 439`, md5 stays `7abff109f80d62083437e1c379389fb5`.
3. FLOATBUS (when touching timing/bus/video): 11/11 modes, zero FAIL lines.
4. DHR pixel truth (when touching vgc): `--disk A2DeskTop... --fixed-time
   --screenshot 450 --memory-dump 450 --stop-at-frame 450` then
   `python3 dhr_validate.py screenshot_frame_0450.png
   memdump_frame_0450_slowram.bin 84 12` → 12/12.

## Quick restart
```bash
cd ~/mister/iigs_simulation && git pull && cd vsim && make -j8
./regression.sh                            # expect 9/9
# FPGA: quartus_sh --flow compile Apple-IIgs  (~7 min, PATH+=~/intelFPGA_lite/quartus/bin)
# deploy: sshpass -p 1 scp output_files/Apple-IIgs.rbf root@192.168.1.196:/media/fat/_Computer/...
```
