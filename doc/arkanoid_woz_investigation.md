# Arkanoid WOZ Boot Investigation

## Problem Statement
MAME boots Arkanoid IIgs WOZ disk in **1569 frames**, but vsim hasn't booted by **2200 frames** and is still searching for disk data.

## Key Findings

### 1. Track Access Pattern Divergence

**MAME (by frame 1568):**
- Progresses through tracks 0-45 (both sides)
- Final activity on **track 23**
- 266 step commands total
- 546 sectors successfully read (DATA COMPLETE)
- byte# counter reaches ~992,000

**vsim (by frame 2200):**
- Also accesses tracks 0-91 (physical tracks 0-45)
- But ends up **stuck alternating Track 0/1** (physical track 0, sides 0 and 1)
- Track 0 loaded 313 times, Track 1 loaded 302 times
- Higher tracks only loaded 2 times each
- 5,762 sector prologues detected (PROLOG_OK)
- byte_cnt reaches ~2,198,394 (MORE than MAME but doesn't boot)

### 2. IWM Data Return Values

**At end of MAME log (frame 1560):**
```
result=d6 active=1 data=d6 status=2f mode=0f floppy=Apple/Sony 3.5 DD
```
- Returns valid GCR bytes (d6, a6, f9, cb, etc.) with bit 7 set
- Floppy is active, reading from track 23

**At end of vsim log (frame 2200):**
```
read_iwm 0ec ret: 00 ... drive_on=1 bitpos=51992 bit_count=75215
```
- Returns 0x00 (bit 7 NOT set)
- CPU stuck in wait loop at FF:4C6A waiting for bit 7
- Drive is on but no valid data bytes being returned

### 3. Sector Detection Statistics

**MAME:**
- 1,040 ADDR FAIL events (all show T=96 - encoded track byte, expected)
- 546 DATA COMPLETE events (successful sector reads)
- Address checksum failures are informational, data still reads

**vsim:**
- 5,762 PROLOG_OK events (sector prologues found)
- 297 PROLOG_BAD events (all "d5 cc" at position 55855 - copy protection marker)
- No DATA COMPLETE equivalent logged

### 4. Copy Protection Marker

Both MAME and vsim detect `d5 cc` pattern at position 55855 on track 0:
- This is an intentional copy protection marker (fake sector prologue)
- vsim correctly detects this as PROLOG_BAD
- The game uses this to verify the disk is original

### 5. Track Switching Behavior

**End of vsim log shows:**
```
WOZ3 DATA: Track 1 loaded (bit_count=74992, side=1, physical_track=0)
WOZ3 DATA: Track 0 loaded (bit_count=75215, side=0, physical_track=0)
WOZ3 DATA: Track 1 loaded (bit_count=74992, side=1, physical_track=0)
... (repeats many times)
```
- Software is rapidly switching between sides on physical track 0
- Head never advances to higher tracks after initial loading

## Root Cause Hypothesis

The software appears to be stuck in a loop looking for specific data on track 0 that it can't find. Possible causes:

1. **Timing Issue**: vsim's byte generation timing may not match what the software expects
2. **Data Content Mismatch**: Something in the sector data differs from what MAME produces
3. **Copy Protection Check Failure**: The d5 cc marker is being detected but the subsequent check may be failing
4. **Byte Ready Flag**: vsim returns 0x00 (bit 7 clear) while MAME returns valid bytes

### 7. Track Access Sequence in vsim

The full track access pattern:
1. Initial: Track 0 -> 1 -> 0 -> 1 -> 0 (boot sector reads)
2. Seek forward: 2 -> 4 -> 6 -> ... -> 90 -> 91 (physical tracks 1-45)
3. Alternate: 90 <-> 91 several times (physical track 45, both sides)
4. Seek backward: 90 -> 88 -> ... -> 46 (back to physical track 23)
5. Continue backward: -> 44 -> ... -> 0 -> 1
6. **STUCK**: Track 0 <-> Track 1 cycling (159 + 154 = 313 loads)

This pattern suggests:
- Initial loading completed successfully (all tracks accessed)
- Software returned to track 0/1 for a verification check
- The check is failing, causing endless retry loop

### 8. Copy Protection Marker Details

The `d5 cc` marker at position 55855 on track 1:
- Detected as PROLOG_BAD (correct - it's an invalid sector prologue)
- Flux data after marker: 0x99
- Q6/Q7 vary on each detection (0,0 / 1,0 / 0,1 / etc.)
- CPU alternates between FF:4A71 and FF:FCDE at detection time

## Next Steps to Investigate

1. ~~Compare byte-by-byte data on track 0 between MAME and vsim~~
   - Both return 0x00 between valid bytes (same behavior)
2. Check what data follows the d5 cc copy protection marker more carefully
3. Compare the actual bytes being read during the copy protection check
4. Run vsim with shorter frame count to capture the frame number when it enters the track 0/1 loop
5. Check if vsim's byte timing differs from MAME's during critical reads

### 9. Sector Prologue Positions Comparison

**vsim prologue positions on track 0 (in bits):**
- 928, 6996, 13346, 19414, 25482, 31550, 37618, 43686, 49754, 57648
- Spacing: ~6000-8000 bits between sectors (typical for 512-byte sectors)

**MAME prologue positions:**
- All show pos=50475987 (appears to be time-based, not bit position)
- Different coordinate system makes direct position comparison difficult

### 10. Key Observation: Position Coordinate Systems

MAME and vsim use different position tracking:
- **vsim**: Bit position within track (0 to ~75000 for track 0)
- **MAME**: Appears to use time-based position (nanoseconds?)

This makes direct byte-for-byte comparison challenging without converting between coordinate systems.

### 11. Critical Timing Issue Found

**The CPU misses prologues by entering its read loop too late:**

```
Prologue at pos=6996 detected at cycle=24053937
CPU starts reading at pos=7575 at cycle=24070172
Gap: 16,235 cycles (~579 bits)
```

The prologue passed at position 6996, but by the time the CPU entered its read loop, the disk had advanced to position 7575. The CPU then reads random data bytes (b2, 9a, df, d3, ba, eb, d9, fa) instead of the prologue (D5 AA 96).

**Execution sequence before read loop:**
1. FF:4C58: jsr $4cc6 - calls IWM setup subroutine
2. $4CC6: lda $c0ee - sets Q6=1
3. $4CD5: lda $c0ec - initial data read
4. Returns to FF:4C5B
5. FF:4C5B-4C5F: setup retry counters
6. FF:4C61-4C6A: finally enters read loop

**Hypothesis:**
The time spent in the setup subroutine causes the CPU to miss the first available prologue. On subsequent passes, the timing alignment may or may not catch a prologue, leading to intermittent failures.

**Why this matters:**
- The prologue detection (PROLOG_OK) happens correctly in the IWM hardware
- But the CPU's read doesn't see those bytes because it arrives late
- The CPU keeps searching for D5 but only sees random sector data

### 12. ROOT CAUSE FOUND: CPU Reads Faster Than Disk Rotates

**Detailed trace of failed prologue read:**
```
D5 at disk position ~13330, AA at ~13338, 96 at ~13346

1. CPU reads D5 at pos=13330, cycle=24231523 - SUCCESS
2. D5 matches expected byte, CPU decrements counter
3. CPU goes back to read next byte (expecting AA)
4. ASYNC_CLEAR clears D5 at cycle=24231549 (26 cycles later)
5. CPU reads at cycle=24231634, pos=13333-13334 - gets 0x00!
6. AA hasn't been generated yet - it's at position ~13338
7. CPU loops waiting for bit 7, position advances past AA
8. Next valid byte is something other than AA - comparison fails
9. CPU restarts search from beginning
```

**The core issue:**
The CPU reads D5, then immediately tries to read AA. But:
- D5 was at position 13330
- AA is at position 13338 (8 bits away)
- When CPU reads, position is only 13333-13334
- AA hasn't rotated under the head yet!

**This explains everything:**
- Prologues ARE detected by hardware (PROLOG_OK works)
- CPU DOES read D5 correctly
- But AA is always 8 bits ahead, and CPU reads too fast
- Every prologue attempt fails at the AA byte

**Possible fixes:**
1. **Slow down CPU access timing** to match real hardware
2. **Speed up disk rotation** to generate bytes faster
3. **Hold bytes longer** in the data register
4. **Adjust the async clear delay** to keep bytes available longer

## Deep Dive: Async Mode and Data Ready

### 6. Async Clear Mechanism

vsim log shows valid bytes being generated then immediately cleared:
```
IWM_FLUX: ASYNC_CLEAR m_data ff -> 00 (cycle=528297897 bc=0 pending=1 byte_cnt=2198388)
IWM_FLUX: ASYNC_CLEAR m_data 9e -> 00 (cycle=528298122 bc=0 pending=1 byte_cnt=2198389)
IWM_FLUX: ASYNC_CLEAR m_data da -> 00 (cycle=528298346 bc=0 pending=1 byte_cnt=2198390)
```

The bytes have bit 7 set (valid GCR bytes: ff, 9e, da, cd, b2, f4, bf, ed, b4, cb).

**Async Clear Logic (iwm_flux.v):**
- After CPU accesses IWM while valid byte present, m_data clears ~2µs (28 14MHz cycles) later
- This is MAME-style async behavior for IIgs IWM

**Timing Between Bytes:**
- Bytes generated every ~200-250 cycles
- CPU polling loop (LDA $C0EC / BPL loop) takes ~8 cycles per iteration
- CPU polls 25-30 times between each valid byte

**Key Question:**
Does MAME return 0x00 or 0xFF when no new byte is ready? If MAME returns 0xFF (bit 7 set), software may treat that as valid data, causing different behavior.

## Log File Locations
- MAME: `ark_three_mame.log` (48M lines, covers frames 72-1569)
- vsim: `woz_vsim_2200.log` (208M lines, covers frames 72-2200)

---

## Fix Attempts (Jan 2026)

### Fix 1: Async Clear Deadline Timing

**Problem identified:** The `async_update_deadline` was based on `last_sync_14m` (last bit shift time), not the CPU access time. If the CPU reads shortly after a bit shift, the async_clear could fire almost immediately after the read instead of the expected 28 cycles.

**Example:**
- Bit shift at cycle 100, `last_sync_14m = 101`
- CPU reads at cycle 125 (25 cycles later)
- Deadline = 101 + 28 = 129
- Clear fires at cycle 129 - only **4 cycles** after the CPU read!

**Fix applied:** Changed `iwm_flux.v` line 823:
```verilog
// BEFORE:
async_update_deadline <= last_sync_14m + ASYNC_CLEAR_DELAY_14M;

// AFTER:
async_update_deadline <= async_tick_14m + ASYNC_CLEAR_DELAY_14M;
```

**Result:** Partial improvement - bytes are being read, but progress bar still stuck.

### Fix 2: Async Clear Gen Latching

**Problem identified:** When scheduling async_clear at the END of a CPU access cycle, `m_data_gen` may have already been incremented by a byte that completed DURING the access. This causes async_clear to incorrectly target the NEW byte instead of the one actually read.

**Timeline of bug:**
1. CPU access starts, m_data = byte_A, m_data_gen = N
2. During PHI2-high, byte_B completes: m_data = byte_B, m_data_gen = N+1
3. At PHI2 fall, async_clear scheduled with gen = m_data_gen = N+1 (WRONG!)
4. When async_clear fires, it clears byte_B instead of byte_A

**Fix applied:** Added `access_gen_latched` register captured at access START, used for `async_clear_gen`:
```verilog
// In iwm_flux.v:
reg [31:0] access_gen_latched;    // Captured at access START

// At access start:
access_gen_latched <= m_data_gen;

// At access end:
async_clear_gen <= access_gen_latched;  // Use START gen, not current gen
```

**Result:** Testing in progress (frame 2000 test running).

### Current Status

After both fixes, the simulation shows:
- Bytes ARE being read successfully (e.g., 0xf3, 0xea with bit 7 set)
- CPU is in sector data read routine (FF:4F1A-4F24), not just prologue search
- ASYNC_CLEAR fires correctly 28 cycles after CPU access
- BUT: Progress bar still not advancing significantly

**Next investigation areas:**
1. Compare sector checksum verification between MAME and vsim
2. Check if retries are happening (successful read but checksum fail?)
3. Look at track switching behavior during loading
4. Verify the async_clear gen matching is working correctly

**Note:** Basic regression tests PASS with these fixes, confirming no breakage of existing functionality.

### Observations from Frame 2000 Test

- CPU found byte 0x96 at position 68206 (third prologue byte D5 AA 96)
- CPU is still at FF:4C6A (prologue search loop) at end of trace
- This suggests: prologues ARE being found, but sector reads are failing
- Likely cause: data corruption, checksum mismatch, or byte timing issues during sector body read
- Progress bar stuck at same position throughout frames 1600-2000

### Key Difference from Original Issue

Original issue: CPU getting 0x00 repeatedly, never seeing valid bytes
After fixes: CPU IS reading valid bytes (0x96, 0xf3, 0xea, etc.)

The async_clear timing fixes helped with byte delivery, but there's still a higher-level issue preventing successful sector reads. Need to investigate:
1. What happens after prologue is found (sector data read)
2. Are there checksum failures?
3. Is the CPU missing bytes during data read (causing misalignment)?
