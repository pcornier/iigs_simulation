# WOZ Disk Failure Tracking

This document tracks failures in the WOZ flux-level disk emulation and provides a systematic approach to debugging them.

## Overview

The WOZ disk emulation uses flux-level timing data to accurately simulate floppy disk reads. MAME successfully boots these same WOZ files, indicating bugs exist in our implementation rather than in the disk images.

## Known Failures

### AppleWorks 5 (AppleWorks5d1.woz)

| Field | Value |
|-------|-------|
| **Status** | FAILING |
| **Error** | "relocation / configuration error" |
| **Works in MAME** | Yes |
| **Copy Protected** | No |
| **Disk Type** | 3.5" |

**Symptoms:**
- ProDOS 8 V2.0.3 loads successfully (visible at frame ~400)
- AppleWorks starts but fails with "Relocation/Configuration Error" (frame ~550)
- Sector stats show: `addr_ok=47 addr_fail=0 data_complete=46 prologue_miss=0` (no read errors!)
- CPU ends up in infinite loop at `$00:22CB` (error handler)

**Root Cause Analysis (2024-01-31):**

| Issue | MAME | vsim | Status |
|-------|------|------|--------|
| Track stepping | 1849 steps, reaches track 40 | Only 2 steps, stays on track 0-1 | **BUG** |
| Step direction commands | 105 | 32 | Reduced |
| Sectors read | From multiple tracks | Only from track 0 | **BUG** |
| Data bytes read | `E5 A5 A5 AC` (valid sync) | `FF DA EA F7` (garbage) | **MAJOR BUG** |
| IWM events | 3.5M | 724K | Reduced |

**Key Findings (Updated 2026-01-31):**

1. **ProDOS Loads Successfully**: Despite the 1-byte offset, ProDOS 8 boots and displays its startup screen. This means:
   - Boot block data is readable (perhaps offset doesn't affect early boot?)
   - The error happens AFTER ProDOS is running
   - This is an AppleWorks initialization error, NOT a disk I/O error

2. **No Disk Read Errors**: All sector reads complete successfully:
   - 166 sectors read from track 0
   - addr_ok=47, addr_fail=0, data_complete=46, prologue_miss=0
   - GCR decoding works, just with 1-byte offset

3. **Head Never Seeks Beyond Track 0-1**: Only initial calibration steps occur:
   - MAME: Seeks through tracks 0-40 with 1849 step commands
   - vsim: Only 2 step commands during calibration
   - After ProDOS loads, no additional step commands are issued

4. **AppleWorks Initialization Fails**: "Relocation/Configuration Error" is caused by ProDOS I/O error:
   - **Root cause found**: ProDOS returns error $27 (I/O Error)
   - AppleWorks interprets this as "Relocation/Configuration Error"
   - The I/O error occurs when AppleWorks tries to load files after ProDOS is running
   - This links back to the disk reading issue - the head never seeks to higher tracks

5. **Data Has 1-Byte Offset**: When shifted, data matches MAME 100%:
   - Sector 0: -1 byte offset (boot block - tolerated)
   - **Sector 2: -2 byte offset** (volume directory header - CORRUPTED!)
   - Sectors 3+: -1 byte offset (directory entries - corrupted)
   - See `doc/sector_byte_map.md` for detailed byte-level analysis

**Root Cause Identified (2024-01-31):**

The sector data has a **1-byte offset** (sometimes 2 bytes) compared to MAME:

| Sector | Alignment Shift | Score |
|--------|-----------------|-------|
| Sector 0 | -1 | 100% match when shifted |
| Sector 2 | -2 | 100% match when shifted |
| Sectors 3-11 | -1 | 100% match when shifted |

When the vsim data is shifted by -1 byte, it matches MAME perfectly. This means:
- **GCR decoding is working correctly** - the bytes are right, just offset
- **The sector markers (D5 AA 96/AD) are found correctly**
- **A byte alignment issue** is causing data to start 1 byte early

The offset causes:
1. Boot block data to be misaligned
2. ProDOS can't parse volume directory correctly
3. ROM stays on track 0 because it can't find valid boot info
4. Eventually times out with I/O error $27

**Hypothesis (2026-01-31) - Independent Fractional Accumulators:**

**HYPOTHESIS DISPROVEN** by standalone testbench (see `vsim/tb_flux/`).

Original hypothesis: The 1-byte offset is caused by **independent fractional timing accumulators** in `flux_drive.v` and `iwm_flux.v` drifting apart over time.

| Module | Accumulators | Purpose |
|--------|--------------|---------|
| `flux_drive.v` | `bit_cell_frac`, `bit_half_frac` | Flux transition generation timing |
| `iwm_flux.v` | `full_window_frac`, `half_window_frac` | Byte assembly window timing |

**Testbench Results (2026-01-31):**

A standalone Verilator testbench (`vsim/tb_flux/`) was created to verify accumulator synchronization:

| Metric | Result |
|--------|--------|
| Max fractional difference | 388 (less than one step of 636) |
| Multi-step divergences | 0 |
| Accumulated drift over 500K cycles | None |
| Bytes decoded correctly | Yes (all 0x96 self-sync pattern) |

**Key Finding:** The fractional accumulators ARE properly synchronized. They update at slightly different sub-cycle times within each bit cell (2-cycle NBA timing offset), but they track each other exactly over time. No drift accumulates.

**Conclusion:** The 1-byte offset is NOT caused by accumulator drift. The root cause lies elsewhere.

**Evidence (still valid):**
```
--- Track 0 Sector 0 ---
MAME first non-0x96: position 17
vsim first non-0x96: position 16 (same byte value: 0x9A)
Best alignment shift: -1 (100% match when shifted)

--- Track 0 Sector 2 ---
MAME addr->data gap: 16 bytes
vsim addr->data gap: 17 bytes (1 extra byte in gap)
Best alignment shift: -2
```

**Remaining Hypotheses to Investigate:**

1. **Initial byte boundary alignment**: The S_IDLE → SR_WINDOW_EDGE_0 transition may start at wrong phase relative to actual sector data. Self-sync bytes (0x96) should align byte boundaries, but if we're starting one bit off, all subsequent bytes are shifted.

2. **BRAM read latency mismatch**: flux_drive.v has 1-cycle BRAM latency handling (`bram_first_read_pending`). If the first flux transition is generated before valid data is read, byte boundaries start wrong.

3. **Sector header/data gap handling**: The -2 offset for sector 2 vs -1 for others suggests something changes between sectors. Possibly gap byte handling or address-to-data field transition timing.

4. **Self-sync detection**: GCR format uses self-sync bytes (consecutive 1-bits) to establish byte boundaries. If vsim detects sync completion one bit early/late compared to MAME, all data is shifted.

**Fixes Attempted (2026-01-31):**

1. **Removed `side_reset_active` check from `iwm_disk_ready`** (`iwm_woz.v` line 684)
   - Fixed state machine resets mid-read caused by HEAD_SELECT changes
   - State machine toggles reduced from 5 to 1 per session
   - Did NOT fix the 1-byte offset

2. **Disabled fractional timing in `iwm_flux.v`** (line 176: `use_fractional_window = 1'b0`)
   - Offset remained at -1
   - Actually caused slight drift since flux_drive still uses fractional timing

3. **Wait for first flux edge in S_IDLE** (modified S_IDLE state)
   - Tried to synchronize window start to flux timing
   - Did NOT fix the offset

4. **Re-enabled fractional timing**
   - Needed to match flux_drive.v's fractional timing
   - Offset still -1 for most sectors, -2 for sector 2

5. **S_IDLE wait-for-flux fix attempt (2026-01-31)**
   - Changed S_IDLE to STAY in idle until first flux_edge detected
   - Hypothesis: variable timing between DISK_READY and first flux caused different numbers of zero-bits to shift in
   - Result: Made byte position WORSE (pos=15 instead of pos=16, further from MAME's pos=17)
   - Reverted - the immediate EDGE_0 transition is actually closer to correct
   - Added DEBUG_BYTE_OFFSET instrumentation to track S_IDLE transitions and first flux timing

**Detailed Analysis of S_IDLE Timing (2026-01-31):**

| Metric | Testbench | Full Sim | Notes |
|--------|-----------|----------|-------|
| S_IDLE → EDGE_0 transition | cycle=18721 | cycle=24911059 | Both start in EDGE_0 (no flux at activation) |
| Cycles before first flux | ~31 cycles | ~73 cycles | Different due to spinup timing |
| First flux position | pos=1 | pos=2 | After bit_position reset |
| First byte position | pos=17 | pos=16 | 1-bit difference |
| First byte value | 0x96 (sync) | 0x9b (data) | Different track data |

The timing difference (31 vs 73 cycles) between state machine activation and first flux is NOT the cause - changing S_IDLE to wait for flux made things worse. The root cause is elsewhere.

**Current Status (Updated 2026-01-31):**
- The 1-byte offset is still present
- Offset varies by sector: -1 for most, -2 for some
- **BUT**: ProDOS boots successfully despite the offset!
- The error is AppleWorks-specific, happens during app initialization

**Revised Analysis (2026-01-31):**

The 1-byte offset IS likely the root cause, but manifests differently than expected:

1. **Track 0 reads succeed**: 166 sectors read successfully from track 0
2. **ProDOS boots**: ProDOS loads successfully from track 0 data
3. **AppleWorks starts**: Enough code loads to begin initialization
4. **File read fails**: AppleWorks tries to read files from higher tracks
5. **Head never seeks**: Only 2 step commands issued (calibration only)
6. **ProDOS returns I/O error $27**: Can't read requested blocks
7. **AppleWorks shows error**: "Relocation/Configuration Error"

**Why head doesn't seek:**
The ROM disk driver reads block numbers from the volume directory.
If the 1-byte offset corrupts the directory structure, the ROM:
- Can't find valid block pointers
- Never requests reads from higher tracks
- Returns I/O error instead of seeking

**Key insight**: ProDOS boots because the boot blocks are simple.
AppleWorks fails because its file entries in the directory are corrupted by the offset.

**Fixes Attempted (2026-01-31 continued):**

6. **Startup delay in flux_drive.v** (flux_startup_delay)
   - Goal: Suppress FLUX_TRANSITION for first bit-cell after DRIVE_READY reset
   - This ensures bit_position advances from 0 to 1 before first flux is detected
   - Bug found: bram_first_read_pending was not being cleared in FLUX mode
   - Fixed by adding clear logic in FLUX track handling block
   - Result: Testbench passes, but AppleWorks still fails with same error
   - First flux moved from pos=0 to pos=2, but byte framing still off

7. **Window sync to FLUX_BIT_TIMER** (iwm_flux.v)
   - Goal: Align IWM window to flux_drive's bit-cell grid
   - Set window_counter = FLUX_BIT_TIMER when S_IDLE → EDGE_0
   - Result: Did not fix the 1-byte offset

**Updated Analysis (2026-01-31):**

The startup delay and window sync fixes changed the first flux position but did NOT fix the 1-byte offset. This suggests the byte framing issue is more fundamental:

| Metric | Before Fix | After Fix | Target |
|--------|------------|-----------|--------|
| First flux position | pos=0 | pos=2 | pos=1 |
| First byte position | pos=16 | pos=19 | pos=17 |
| Byte-flux delta | 16 | 17 | 16 |

The byte-to-flux-delta changed (16 → 17), which is unexpected. The delta should be consistent regardless of absolute positions.

**Current Hypothesis:**

The issue may be in how the FIRST flux transition is processed in EDGE_0 state, not in the timing of when it arrives. In MAME, when a flux arrives in EDGE_0:
- m_last_sync and m_next_state_change are set to the EXACT flux time
- The window is aligned to the flux transition

In vsim, we transition to EDGE_1 and load a half window, but we don't align the window timing to the flux arrival.

**Next Steps to Investigate:**
- Compare EDGE_0 → EDGE_1 transition handling between MAME and vsim
- Verify window timing is aligned to flux transitions, not just clock cycles
- Check if fractional window timing contributes to the offset
- Consider implementing MAME's exact timing alignment approach

**Suspected Location:**
- `iwm_flux.v` SR_WINDOW_EDGE_0 state: flux arrival handling
- `iwm_flux.v` load_half_window() task: window timing after flux
- `flux_drive.v` lines 275-302: `load_bit_timers()` task
- The initial S_IDLE to SR_WINDOW_EDGE_0 transition timing

---

### Arkanoid IIgs (ArkanoidIIgs.woz)

| Field | Value |
|-------|-------|
| **Status** | Unknown - needs testing |
| **Error** | TBD |
| **Works in MAME** | TBD |
| **Copy Protected** | Likely |
| **Disk Type** | 3.5" |

---

## Systematic Debugging Approach

### Phase 1: Comparison Infrastructure

Create tools to compare our simulation against MAME's behavior:

1. **MAME IWM logging** - Extract IWM register reads/writes from MAME
2. **Bit-level comparison** - Compare raw bits read from flux vs MAME's interpretation
3. **Sector decode comparison** - Compare decoded sector data byte-by-byte

### Phase 2: Isolated Unit Tests

Test individual components in isolation:

1. **Flux timing playback** - Verify flux transitions are generated at correct intervals
2. **GCR decoding** - Verify 10-bit to 8-bit decoding is correct
3. **Address field parsing** - Verify track/sector/side/checksum decoding
4. **Data field parsing** - Verify 524-byte sector data decoding

### Phase 3: Specific Bug Hunts

Based on AppleWorks failure analysis:

| Hypothesis | Test | Status |
|------------|------|--------|
| Flux timing drift | Compare cumulative timing vs expected over full track | **RULED OUT** - tb_flux shows no drift |
| Fractional accumulator sync | Standalone testbench comparing flux_drive vs iwm_flux fracs | **PASS** - max diff 388, no multi-step divergence |
| Initial byte boundary | Verify D5 prologue detected at correct bit position | TODO - next testbench |
| Self-sync detection | Verify sync-to-prologue transition | TODO - next testbench |
| Side selection bug | Log side bit in address fields vs expected | TODO |
| Track wrap timing | Verify bit_index wraps correctly at track end | TODO |
| Data field timeout | Check if data field timeout occurs before all bytes read | TODO |

---

## Key Files

| File | Purpose |
|------|---------|
| `rtl/flux_drive.v` | Physical drive emulation (motor, flux generation) |
| `rtl/iwm_woz.v` | IWM controller with WOZ interface |
| `rtl/iwm_flux.v` | Flux decoding and IWM register reads |
| `rtl/woz_track.sv` | Track data BRAM and loading |
| `vsim/sim_blkdevice.cpp` | WOZ file parsing in C++ |

### Testbenches

| Directory | Purpose | Status |
|-----------|---------|--------|
| `vsim/tb_flux/` | Accumulator synchronization test | **PASS** - no drift detected |
| `vsim/tb_flux_sync/` | Self-sync byte boundary test | TODO |

---

## Comparison Data Points

When comparing against MAME, capture these at each sector read:

1. **Track/Side requested** - What track is the driver seeking?
2. **Sector number found** - What sector address field was decoded?
3. **Data bytes read** - All 524 bytes of sector data
4. **Timing between sectors** - Time from address field to data field
5. **Retry count** - How many retries before success/failure?

---

## Debug Commands

```bash
# Run AppleWorks with full logging
./obj_dir/Vemu --woz AppleWorks5d1.woz > awk_debug.txt 2>&1

# Capture specific frames around failure
./obj_dir/Vemu --woz AppleWorks5d1.woz --screenshot 100,200,300 --stop-at-frame 350

# Compare IWM activity (if MAME log available)
python3 iwm_compare.py mame_log.txt vsim_log.txt
```

---

## Hypotheses to Test

### 1. Flux Timing Accuracy

The flux_drive module generates transitions based on stored timing data. Possible issues:
- Tick rate mismatch (should be 125ns per tick)
- ~~Cumulative drift over track rotation~~ **RULED OUT** by tb_flux testbench
- Incorrect handling of track wrap

**Status**: Fractional accumulator sync verified. No drift detected over 500K cycles.

### 2. Side Selection

The IWM uses CA2 for side selection on 3.5" drives. Possible issues:
- Side bit not correctly passed to track loader
- Track data loaded for wrong side
- Side field in address marks not matching

### 3. GCR Decoding

GCR self-sync and data decoding. Possible issues:
- Self-sync pattern detection (10 or more consecutive 1-bits)
- 10-bit to 8-bit translation table errors
- Bit ordering (MSB vs LSB first)

### 4. Sector Interleave

Apple 3.5" disks use 2:1 interleave. Possible issues:
- Physical sector order vs logical sector order confusion
- Interleave timing causing missed sectors

---

## Action Items

### High Priority (1-Byte Offset Bug)
- [x] **Compare first sector data byte-by-byte with MAME** - Found 1-byte offset
- [x] **Verify GCR decoding tables** - GCR decoding is correct
- [x] ~~**Identify root cause** - Independent fractional accumulators causing timing drift~~ **DISPROVEN**
- [x] **Accumulator sync testbench** - Built `vsim/tb_flux/`, confirmed accumulators ARE synchronized
- [x] **Self-sync byte boundary testbench** - Built `vsim/tb_flux_sync/`, **ALL TESTS PASS**
- [ ] **Verify addr->data gap matches MAME (16 bytes)**

### Self-Sync Byte Boundary Testbench: Results (2026-01-31)

**HYPOTHESIS RULED OUT**: The IWM/flux_drive isolated path correctly detects byte boundaries.

Built `vsim/tb_flux_sync/` testbench that feeds known patterns through flux_drive → iwm_flux and verifies decoded bytes.

**Test Results:**

| Test | Pattern | Expected Sync | Actual Sync | First Non-Sync | Result |
|------|---------|---------------|-------------|----------------|--------|
| Basic | 8x 0x96 + D5 AA 96 | 8 | 8 | D5 at pos=72 | **PASS** |
| Extended | 64x 0x96 + D5 AA 96 | 64 | 64 | D5 at pos=520 | **PASS** |
| Minimal | 2x 0x96 + D5 AA 96 | 2 | 2 | D5 at pos=24 | **PASS** |
| Drift | Multiple D5 AA 96 | - | - | All D5 correct | **PASS** |

**Key Findings:**
1. D5 prologue is detected at the **exact correct bit position** after sync bytes
2. No byte boundary drift over multiple prologues
3. The isolated flux_drive + iwm_flux path works correctly

**Conclusion:** The -1 byte offset bug is NOT in the IWM or flux_drive modules. The bug must be:
- In track data loading (WOZ parser or BRAM initialization)
- In the interaction between IWM and the rest of the system
- In how the full simulation initializes the read sequence

### WOZ Track Loading Testbench: Results (2026-01-31)

**HYPOTHESIS RULED OUT**: Track data is loaded correctly into BRAM with no off-by-one error.

Built `vsim/tb_woz_load/` testbench that simulates the full SD block interface and verifies BRAM contents after track loading.

**Test Results:**

| Check | Expected | Actual | Result |
|-------|----------|--------|--------|
| BRAM[0] | 0x96 | 0x96 | **PASS** |
| BRAM[8] (D5 prologue) | 0xD5 | 0xD5 | **PASS** |
| BRAM[9] | 0xAA | 0xAA | **PASS** |
| All 41 test bytes | Match | Match | **PASS** |
| Side 1 BRAM[0] | 0x69 | 0x69 | **PASS** |

**Key Findings:**
1. First byte of track data is at BRAM address 0 (no offset)
2. All bytes are in correct positions
3. Side selection and dual-BRAM loading works correctly
4. The `woz_floppy_controller` path is NOT the bug source

### Full Integrated Path Testbench: Results (2026-01-31)

**ALL ISOLATED TESTS PASS**: The integrated path (woz_floppy_controller → flux_drive → iwm_flux) works correctly.

Built `vsim/tb_woz_full/` testbench that tests the full integrated path with SD block interface and Sony motor command protocol.

**Test Results:**

| Check | Expected | Actual | Result |
|-------|----------|--------|--------|
| Motor spinning | Yes | Yes | **PASS** |
| Disk mounted | Yes | Yes | **PASS** |
| First non-sync byte | 0xD5 | 0xD5 | **PASS** |
| Bytes decoded | >50 | 101 | **PASS** |
| Bit count | 328 | 328 | **PASS** |

**Key Findings:**
1. The first non-sync byte is 0xD5 at the correct position
2. D5 AA 96 prologue sequence decoded correctly
3. No byte boundary offset in isolated testbench
4. Motor command protocol (Sony LSTRB pulse) works correctly

**Conclusion:** The -1 byte offset bug is NOT in any of the isolated modules:
- NOT in flux_drive → iwm_flux timing
- NOT in woz_floppy_controller BRAM loading
- NOT in the integrated path

### Next Investigation: Full IIgs System Integration

Since all isolated testbenches pass, the bug must be in the full IIgs system integration.

**Debug Instrumentation Added (2026-01-31):**

Added `DEBUG_BYTE_OFFSET` define to `iwm_flux.v` and `flux_drive.v` to trace:
- First flux transitions after motor ready
- First bytes decoded by IWM
- BRAM addresses at each byte boundary

**Key Finding: 1-Bit Position Offset**

Comparing testbench vs full simulation first byte position:
- **Testbench (tb_woz_flux):** byte[0] at pos=17
- **Full simulation:** byte[0] at pos=18

This 1-bit offset causes all subsequent byte boundaries to be shifted by 1 bit, which manifests as a 1-byte data offset when comparing with MAME.

**Additional Observations:**
- Testbench: First byte completion uses E0 state (SR_WINDOW_EDGE_0)
- Full sim: First byte completion uses E1 state (SR_WINDOW_EDGE_1)
- First flux position: testbench at pos=4, full sim at pos=2

**Possible Causes:**
1. **IWM state machine initial state**: Different window edge state at start
2. **First flux timing**: The 2-position difference in first flux could shift byte boundaries
3. **CPU activity during spinup**: ROM reads/writes affecting IWM state
4. **Concurrent state machines**: Multiple flux_drive instances affecting timing

**Diagnostic approach:**
- Add debug output to the full simulation at the module boundaries
- Compare signal timing between testbench and full simulation
- Check if bit_position/BRAM address values differ at first flux transition
- Trace IWM data register reads in the full system
- Focus on why IWM starts in E1 state (full sim) vs E0 state (testbench)

### Medium Priority (Head Stepping) - May self-resolve after byte fix
- [ ] Verify sony_cmd=4 (step) reaches the drive correctly
- [ ] Check step_busy status timing matches MAME
- [ ] Trace why ROM stops issuing step commands after calibration
- Note: ROM stays on track 0 because boot block data is misaligned

### Comparison Tools
- [x] `iwm_compare.py` - IWM event comparison (working, fixed vsim parsing)
- [x] `compare_mame_vsim.py` - Byte sequence comparison (working)
- [x] `--data-fields-by-sector` - Shows per-sector alignment shifts

### Standalone Testbenches
- [x] `vsim/tb_flux/` - Accumulator synchronization (PASS - no drift)
  - Tests: self-sync pattern (0x96), prologue pattern (D5 AA 96), long drift test
  - Results: Max frac diff 388 (<1 step), 0 multi-step divergences
- [x] `vsim/tb_flux_sync/` - Self-sync byte boundary detection (PASS - all tests)
  - Tests: Basic sync (8 bytes), extended sync (64 bytes), minimal sync (2 bytes), drift test
  - Results: D5 detected at correct position in all cases, no drift between prologues
  - **Conclusion**: IWM/flux_drive path is NOT the source of -1 byte offset
- [x] `vsim/tb_woz_load/` - WOZ track data loading (PASS - no offset)
  - Tests: WOZ file parsing, SD block interface, BRAM loading verification
  - Results: All bytes loaded to correct BRAM addresses, no off-by-one error
  - Both sides loaded correctly (side 0: 0x96 pattern, side 1: 0x69 inverted pattern)
  - **Conclusion**: woz_floppy_controller BRAM loading is NOT the source of -1 byte offset
- [x] `vsim/tb_woz_full/` - Full integrated path BITS format (PASS - correct byte decoding)
  - Tests: woz_floppy_controller → flux_drive → iwm_flux with SD block interface
  - Results: First non-sync byte is 0xD5 as expected, 101 bytes decoded correctly
  - Motor spinning, disk mounted, bit count = 328
  - **Conclusion**: Full integrated path works correctly in isolation (BITS format)
- [x] `vsim/tb_woz_flux/` - Full integrated path FLUX format (PASS - correct byte decoding)
  - Tests: woz_floppy_controller → flux_drive → iwm_flux with FLUX timing data
  - Results: D5 AA 96 prologue found correctly, 573 flux transitions, 151 bytes decoded
  - FLUX track detected, motor spinning, drive ready
  - **Conclusion**: FLUX format path works correctly in isolation

---

## Test Matrix

| Disk | Type | Protected | Boots | Loads Files | Notes |
|------|------|-----------|-------|-------------|-------|
| AppleWorks5d1.woz | 3.5" | No | **YES** (ProDOS) | No | AppleWorks "Relocation/Configuration Error" |
| ArkanoidIIgs.woz | 3.5" | Yes? | TBD | TBD | |
| 816.woz | TBD | TBD | TBD | TBD | |

---

## Next Steps

1. **Build Self-Sync Testbench**: Investigate byte boundary establishment
   - Testbench that feeds `96 96 96 96 D5 AA 96` pattern
   - Verify `D5` is decoded at correct bit position
   - Compare first flux edge handling vs MAME

2. **Trace MAME's Read Start Behavior**:
   - In MAME's `iwm.cpp`, how does it handle the first flux edge after read enable?
   - Lines 412-547 show the read state machine
   - Compare S_IDLE exit timing vs our implementation

3. **Check BRAM Latency at Track Load**:
   - When `TRACK_LOAD_COMPLETE` fires, is bit_position=0 starting with valid data?
   - `bram_first_read_pending` should stall first flux check
   - Verify stall is correct number of cycles

4. **Investigate Per-Sector Offset Variation**:
   - Sector 0: -1 offset, Sector 2: -2 offset
   - This suggests something changes between sectors
   - Possibly gap handling or address→data transition timing

5. **Compare Memory at Error Point**:
   - When AppleWorks shows error, compare memory state vs MAME
   - Check volume directory at $2000-$21FF
   - Verify file entries are correctly parsed

## Diagnostic Commands

```bash
# Compare MAME vs vsim logs
python3 iwm_compare.py wozdisks/aw5_mame.log awk.txt --summary
python3 iwm_compare.py wozdisks/aw5_mame.log awk.txt --sectors --limit 20
python3 iwm_compare.py wozdisks/aw5_mame.log awk.txt --show-bytes --limit 50
python3 iwm_compare.py wozdisks/aw5_mame.log awk.txt --tracks

# Find sector data in logs
strings awk.txt | grep "SECTOR:" | head -30
strings awk.txt | grep "cmd STEP"
strings awk.txt | grep "Physical track change"
```
