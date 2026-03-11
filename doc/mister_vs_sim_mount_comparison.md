# MiSTer hps_io vs Simulation — Disk Mount Signal Comparison

## Clock Domains

Both MiSTer and our simulation use `clk_sys` for all mount signal processing:

| | MiSTer | Our Sim |
|---|--------|---------|
| `clk_sys` | Core-defined (likely 14 or 28 MHz) | `CLK_14M` (sim.v line 159: `wire clk_sys=CLK_14M`) |
| hps_io runs on | `clk_sys` (line 261: `always @(posedge clk_sys)`) | N/A (C++ drives signals directly) |
| Edge detect runs on | `clk_sys` | `clk_sys` (sim.v line 483) |
| woz_floppy_controller runs on | `clk_sys` | `clk_sys` |
| flux_drive runs on | `clk_sys` | `clk_sys` |

**Conclusion:** No clock domain mismatch. All proposed changes are valid regardless of clock speed.

---

## Signal Comparison Table

| Aspect | MiSTer (hps_io.sv + ARM user_io.cpp) | Our Sim (sim_blkdevice + sim.v) | Match? |
|--------|---------------------------------------|----------------------------------|--------|
| **img_mounted pulse width** | Multi-cycle: set on `io_strobe` (cmd 0x1c), cleared on next `~io_enable` (line 313). Duration = time between ARM SPI transactions (~10-100+ clk_sys cycles) | 1200 clk_sys cycles (ack_delay) | ~OK (both multi-cycle, sim is longer but edge-detect makes duration irrelevant) |
| **img_size timing** | Set via separate SPI cmd 0x1d **before** mount pulse 0x1c (user_io.cpp sends `UIO_SET_SDINFO` then `UIO_SET_SDSTAT`) | Set in same BeforeEval call, right before `bitset` | OK (both set img_size before img_mounted rises) |
| **img_mounted clearing** | `img_mounted <= 0` when `~io_enable` (hps_io.sv line 313) | `bitclear(*img_mounted, i)` when ack_delay reaches 1 (sim_blkdevice.cpp line 175) | OK |
| **Edge detection → woz_ctrl_mount** | Core latches on rising edge: `woz_ctrl_mount <= (img_size != 0)` | Same logic in sim.v line 487 | **MATCH** |
| **Fresh mount (empty slot)** | 1 pulse, img_size=file_size | 1 pulse, img_size=file_size | **MATCH** |
| **Disk swap (mount over existing)** | **1 pulse, img_size=new_size. NO unmount first.** ARM just sends new size + mount cmd. (user_io.cpp lines 2159-2184) | **2 pulses: unmount(size=0) + 1200-cycle gap + mount(size=new)**. remountPending mechanism. | **MISMATCH** |
| **Unmount/eject** | 1 pulse, img_size=0 (user_io.cpp sets `sd_image[index].size = 0`) | 1 pulse, img_size=0 | **MATCH** |

---

## Behavioral Consequences

| Behavior | MiSTer | Our Sim | Impact |
|----------|--------|---------|--------|
| **Swap: woz_ctrl_mount transitions** | Stays 1 (pulse detected, img_size!=0, latch unchanged) → **no edge for controller** | Goes 1→0→1 (two edges, controller unmounts then rescans) | On MiSTer the controller does NOT rescan on swap. Our sim forces a full rescan. |
| **Swap: disk_mounted signal** | **Stays 1 continuously** (no gap) | **Goes 1→0→1** (brief gap where drive appears empty) | GS/OS can see the empty state in our sim |
| **Swap: disk_switched in flux_drive** | **Unchanged** (DISK_MOUNTED never dropped, no edges) | **Goes 1→0→1** (removal sets 0, insertion sets 1) | No observable effect on MiSTer; our sim toggles needlessly |
| **Swap: GS/OS detection** | GS/OS reads new track data on next access; block checksums/IDs differ → OS detects change | GS/OS may see empty drive during gap, stop polling | MiSTer is seamless; our sim can lose GS/OS attention |
| **Fresh mount: disk_switched** | 1 ("no change") — same as cold boot | 1 ("no change") — same as cold boot | **MATCH — both wrong for hot-insert** |
| **Fresh mount: GS/OS detection** | Unknown — may require periodic /DIP poll by ROM VBL task | **NO** — disk_switched=1, GS/OS sees "no change", ignores | Both may have this issue |

---

## Root Cause Analysis

### Problem 1: Disk Swap Sends 2 Pulses Instead of 1

**MiSTer behavior:** ARM sends `UIO_SET_SDINFO` (new size) then `UIO_SET_SDSTAT` (mount pulse). Single mount event. `woz_ctrl_mount` stays at 1. Controller does NOT rescan — it just gets new data from the SD block device on the next track read.

**Our sim:** `remountPending` mechanism sends unmount (size=0) then mount (size=new). Two edges. Controller unmounts (clears `woz_valid`, resets state) then rescans. During the gap, `disk_mounted=0` and `DISK_MOUNTED=0`, which triggers `disk_switched` transitions and may cause GS/OS to lose track of the drive.

**Fix needed:** For disk swap, send a single mount pulse with the new img_size, matching MiSTer. But this means `woz_ctrl_mount` stays at 1 and the controller sees no edge. We need a way to tell the controller to rescan without a full unmount→mount cycle. Options:
- Use the unused `woz_ctrl_change` toggle signal to trigger rescans
- Briefly glitch `woz_ctrl_mount` to 0 for 1 cycle then back to 1 (creates edges but DISK_MOUNTED gap is minimal)
- Send 1→0→1 but with a very short gap (1-2 cycles instead of 1200)

### Problem 2: Fresh Mount to Empty Slot — disk_switched Wrong

**Both MiSTer and our sim:** After reset, `disk_switched=1` in flux_drive.v (line 596). On first mount (DISK_MOUNTED 0→1), insertion handler sets `disk_switched=1` (line 624). GS/OS polls `/DISKCHANGE` (sense cmd 0xC), gets `~disk_switched = 0` → "no change". GS/OS doesn't discover the disk.

**Real hardware (MAME):** Empty drive starts with `m_dskchg=0` ("changed"). When disk is inserted, `m_dskchg` stays 0 until firmware explicitly clears it via DskchgClear. GS/OS reads `/DISKCHANGE`, gets "changed", triggers discovery.

**This may affect MiSTer too** — unless MiSTer users always mount disks before booting (via OSD during reset), in which case GS/OS sees the disk on first scan and never needs hot-mount detection.

**Fix needed:** The flux_drive.v insertion handler (line 624) should NOT set `disk_switched=1` for runtime hot-inserts. Either:
- Remove the `disk_switched <= 1'b1` on insertion entirely (let firmware handle it via DskchgClear)
- Or differentiate cold-boot mount from runtime mount (e.g., check if drive was previously known to GS/OS)

---

## Proposed Changes (Priority Order)

### 1. sim_blkdevice.cpp — Fix disk swap to match MiSTer

Remove the `remountPending` 2-pulse mechanism. When mounting over an existing disk:
- Set img_size to new file size
- Send a single mount pulse
- sim.v edge detect catches the rising edge, latches `woz_ctrl_mount = 1` (no change since already 1)
- Need a mechanism in sim.v to force the controller to rescan (see #2)

### 2. sim.v — Add rescan trigger for disk swap

Since `woz_ctrl_mount` staying at 1 means no edge for the controller, add a brief 0-glitch:
- On mount event where `woz_ctrl_mount` is already 1, drive it to 0 for 1 cycle then back to 1
- This creates a falling+rising edge in rapid succession (1 clk_sys cycle gap)
- Controller sees unmount→mount with minimal gap
- `disk_mounted` drops for 1 cycle — too fast for GS/OS to notice

### 3. flux_drive.v — Fix disk_switched for hot-insert

Change line 624 from:
```verilog
disk_switched <= 1'b1;  // MAME: device_start() m_dskchg=1 when exists()
```
To not override disk_switched on insertion (let it stay at 0 from the removal or initial state), so GS/OS can detect the media change. The firmware will clear it via DskchgClear after acknowledging the new disk.

**Note:** This may break cold-boot (the comment at line 610-616 explains why it was added). A possible middle ground: only set `disk_switched=1` on insertion if the system is still in reset/early boot, not during runtime.
