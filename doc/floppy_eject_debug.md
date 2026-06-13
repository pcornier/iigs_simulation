# 3.5" Floppy Eject — status & debugging handoff

**Branch:** `floppy-eject` (off `apple-iigs-disk-conversion` @ merge `d99a7d2`, which already has
`master` merged in). Pushed to origin.

**Goal:** make dragging a mounted 3.5" floppy to the Trash in the GS/OS Finder eject it
(icon disappears, drive reads empty), mirroring how `MacLC_MiSTer` handles Mac floppy eject.

## Current status (the bug to fix)

- ✅ Eject is recognized: dragging the 3.5" disk to the Trash removes the Finder icon.
- ❌ **After eject the mouse goes choppy and the machine hangs for 10–30 s at a time, repeatedly.**

Two implementations have been tried (both on this branch, in order):

| Attempt | Commit | What it does | Symptom |
|---|---|---|---|
| V1 | `5ed0b6e` | On eject, only gate `DISK_READY[2]` low (drive reports "no disk") | mouse froze/unfroze **rapidly** (short stalls) |
| V2 | `a356f3f` | V1 **plus** force `woz_ctrl_mount → 0` (fully unmount the woz controller) | mouse choppy, **10–30 s hangs** (worse) |
| probe | `33b57e6` | Mirror the eject latch into `vsim/sim.v` so the **simulator reproduces** the eject (was stubbed) | n/a — tooling only |

The current HEAD is V2 + the sim probe wiring.

## How it's wired (signal chain)

The eject command (Sony `sony_ctl == 4'h7`, previously a dead stub) now pulses up to a
top-level latch that drops disk presence:

```
flux_drive.v   eject cmd ──► EJECT_REQ (1-cyc pulse, gated to selected 3.5" drive)
   rtl/flux_drive.v  : output reg EJECT_REQ; set in the sony_cmd_strobe handler (sony_ctl==4'h7)
iwm_woz.v      drive35 EJECT_REQ ──► EJECT_35
   rtl/iwm_woz.v     : wire drive35_eject; assign EJECT_35 = drive35_eject;
iigs.sv        EJECT_35 ──► floppy35_eject  (new module output)
Apple-IIgs.sv  floppy35_eject ──► ejected35 latch
   Apple-IIgs.sv     : reg ejected35; set on floppy35_eject, cleared on img_mounted[2] rising
                       assign DISK_READY[2] = woz_ctrl_disk_mounted && !ejected35;
                       on eject also: woz_ctrl_mount <= 0 (V2 full unmount)
vsim/sim.v     same latch mirrored (uses img_mounted[5] for the 3.5" slot)
```

Why presence-drop works at all: in `flux_drive.v` the "disk in place" status is
`sense_35 = ~DISK_MOUNTED` (the CSTIN line), and the removal edge sets `disk_switched`
(`if (!DISK_MOUNTED && prev_disk_mounted) disk_switched <= 0`). So lowering `DISK_READY[2]`
makes the drive report no-disk + changed with no other changes to the drive's status logic.

### MiSTer framework constraint (important)
There is **no core→HPS unmount** in `hps_io`. The OSD slot stays "mounted" after eject; we can
only make the *machine-visible* drive look empty. Re-mounting the image from the OSD
(`img_mounted` pulse) clears `ejected35` and re-inserts. This matches every other core
(MacLC included).

## Leading hypothesis

GS/OS **never takes the volume offline** after the eject and keeps issuing block reads to it.
- V1: controller still mounted → reads return stale track data quickly → short, rapid stalls.
- V2: controller unmounted → **no track data loaded** → each read runs to a **data-mark timeout
  (~seconds)** before erroring → multi-second hangs.

So the real fix is probably to make the ejected drive **return a disk-switched / no-disk error
immediately on access** so GS/OS marks the volume offline and stops poking it — rather than only
dropping the presence bit and letting reads time out.

## How to reproduce + probe (on the sim machine)

The sim now reproduces the eject (commit `33b57e6`). It has built-in `printf` probes in
`vsim/sim_main.cpp` that fire at known ROM addresses:

- `WOZ_BASICSTAT #n: status_byte=XX (DSW=? Online=? WP=?)` — at `FF:3F74`, the SmartPort status
  routine. **This is the key probe**: shows what GS/OS reads for the disk. If `Online` stays `1`
  after eject, GS/OS still thinks the disk is mounted → confirms the hypothesis.
- `WOZ_DM_TIMEOUT` — data-mark read timeout (the multi-second hang).
- `WOZ_TRYMORE`, `WOZ_READDATA_ERR`, `WOZ_CTRL` — retry / error / mount events.

Steps:
```bash
git checkout floppy-eject && git pull
cd vsim && make
# windowed; GS/OS off HDD + a 3.5" image mounted; suppress the CPU instruction firehose
./obj_dir/Vemu --disk gsos.hdv --woz "<some 3.5 image>.woz" --no-cpu-log > eject.log 2>&1
# In the window: boot to Finder, eject the 3.5" (drag to Trash, or Open-Apple+Shift+1),
# let it hang a few seconds, then quit.
grep -E "WOZ_BASICSTAT|WOZ_DM_TIMEOUT|WOZ_TRYMORE|WOZ_READDATA_ERR|WOZ_CTRL" eject.log | tail -150
```

If a windowed/interactive eject is awkward to script, add a deterministic `--eject-at-frame N`
option (force `floppy35_eject` for one cycle at frame N in `sim_main.cpp`, following the existing
`--reset-at-frame` pattern) so the capture is repeatable.

Full CPU trace fallback: drop `--no-cpu-log`; `sim_main.cpp` has GS/OS address→name tables, so the
repeating PC/function during the hang names the routine GS/OS is stuck in.

## What the probe output should decide

- **`Online=1` persists after eject** → GS/OS hasn't taken the volume offline. Fix: make access
  return disk-switched/offline so it does. Look at how `disk_switched`/`sense_35` reach the
  SmartPort status byte; the eject may need to assert "disk switched" in a way the status call
  reports (not just the presence/CSTIN bit).
- **`WOZ_DM_TIMEOUT` repeating** → confirms reads are hanging on the gone disk. A faster failure
  path (immediate no-disk error instead of timeout) would at least shorten the hangs.

## Candidate fixes to try (after confirming with the probe)

1. Ensure the SmartPort/Sony **status call returns disk-switched + offline** right after eject so
   GS/OS dismounts the volume (stops all I/O). This is the "right" fix if `Online` stays 1.
2. If GS/OS still issues reads, make the IWM/flux read path **error immediately** when
   `DISK_MOUNTED==0` instead of waiting for a data-mark timeout (turns 10–30 s hangs into quick
   errors).
3. Reconsider V1 vs V2: V2 (full unmount) made it worse; V1 may be a better base once the
   offline/disk-switched signaling is correct. Consider keeping the controller responsive (so
   reads fail fast) but reporting no-disk + switched.

## Reference implementation

`../MacLC_MiSTer/MacLC.sv` (same RTC/PRAM chip family) handles the identical Mac eject:
- `rtl/floppy.v` decodes the eject command → `diskEject`.
- `MacLC.sv` clears its `dsk_int_ins` "disk inserted" flag on `diskEject` (lines ~1009-1025).
The Mac OS then sees a clean empty drive. The difference for us is GS/OS's SmartPort/block layer
keeping the volume online — that's what the probe needs to confirm.

## Key files / locations

- `rtl/flux_drive.v` — `EJECT_REQ` output + eject decode (`sony_ctl==4'h7`); `sense_35`/`disk_switched`.
- `rtl/iwm_woz.v` — `EJECT_35` output; `smartport_dev` instance (block I/O currently stubbed).
- `rtl/iigs.sv` — `floppy35_eject` pass-through; `iwm_woz` instance.
- `Apple-IIgs.sv` — `ejected35` latch, `DISK_READY[2]` gate, `woz_ctrl_mount` unmount (FPGA top).
- `vsim/sim.v` — same eject latch mirrored (3.5" slot = `img_mounted[5]`).
- `vsim/sim_main.cpp` — `WOZ_BASICSTAT` / `WOZ_DM_TIMEOUT` / etc. probes; GS/OS name tables.
- `rtl/woz_floppy_controller.sv` — `disk_mounted = img_mounted && woz_valid`; unmount handler ~L554.

## Build / validation notes

- Regression (`vsim/regression.sh`) should be **unchanged**: `ejected35` only asserts on an eject
  command, which the regression scripts never issue, so `DISK_READY[2]` is ungated during all
  regression runs.
- The eject latch + gating is in files the Verilator sim compiles, so `make` validates it builds.
- FPGA (Quartus) build validates the `Apple-IIgs.sv` path.
