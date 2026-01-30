# WOZ FLUX Chunk Debugging Session

## Current Status

**Status: WORKING - WOZ v2 BITSTREAM and WOZ v3 FLUX tracks both functional (2026-01-30)**

### Summary of WOZ Version Support

| WOZ Version | Format | Status | Notes |
|------------|--------|--------|-------|
| WOZ v1 | BITSTREAM | Working | Karateka 5.25" boots |
| WOZ v2 | BITSTREAM | Working | BeagleDraw, system disks boot |
| WOZ v2 | Copy-protected | STUCK | ArkanoidIIgs.woz stuck at 25% progress bar |
| WOZ v3 | FLUX tracks (Applesauce) | **WORKING** | Sectors decode correctly (addr_ok=38+, data_complete=50+) |
| WOZ v3 | FLUX tracks (MAME) | **WORKING** | AppleWorks v3.0 800K.woz boots (fixed BRAM address truncation) |
| WOZ v3 | BITSTREAM (cracked) | Partial | ArkanoidCrack.woz doesn't reach splash screen |

### Critical Fix (2026-01-29): FLUX Chunk Scan Limit

**Problem**: WOZ v3 files with FLUX chunks were failing with "WOZ scan limit reached without required chunks" because the FLUX chunk appears AFTER the TRKS chunk in the file, and the TRKS chunk can be very large (3-4MB).

**Root Cause**: `SCAN_BLOCK_LIMIT` in `woz_floppy_controller.sv` was set to 3000 blocks (1.5MB), but typical WOZ v3 files have:
- TRKS chunk data: ~3.8MB (starting at block ~3)
- FLUX chunk: appears after TRKS (e.g., at block 7746)

The scanner would hit the 1.5MB limit and stop before reaching the FLUX chunk.

**Fix**: Increased `SCAN_BLOCK_LIMIT` from 3000 to 16000 blocks (8MB) to accommodate larger WOZ files:

```verilog
// rtl/woz_floppy_controller.sv line 264
localparam [15:0] SCAN_BLOCK_LIMIT = 16'd16000; // 8MB to cover FLUX chunk after large TRKS
```

**Result**: FLUX chunk now parses correctly:
```
FLUX_SCAN: FLUX[0] = 0 (0x00)
WOZ_SCAN: FLUX chunk parsed (160 bytes)
WOZ_CTRL: Parsed INFO/TMAP/TRKS/FLUX (ver=3 type=2 timing=16 flux_block=7746), entering IDLE
WOZ_CTRL: Track 0 has FLUX data at TRKS entry 0
WOZ_CTRL: FLUX Track Info: StartBlock=3 BlockCount=95 FluxBytes=48240
```

### Critical Fix (2026-01-30): TRKS Chunk Skip Optimization

**Problem**: Even with the 16000-block scan limit, scanning through a 1.3MB+ TRKS chunk byte-by-byte was extremely slow. The scanner had to process every byte of track data just to reach the FLUX chunk at the end of the file.

**Root Cause**: The WOZ v3 file structure places track data (TRKS chunk) before the FLUX timing chunk. For a typical WOZ v3 file:
- TRKS chunk starts at block ~3
- TRKS chunk size: 1.3MB+ (2600+ blocks)
- FLUX chunk appears AFTER all track data

The streaming scanner processed each TRKS byte sequentially, even though we only need the first 1280 bytes (track metadata) - the actual track data is loaded separately later.

**Fix**: Added TRKS skip optimization to `woz_floppy_controller.sv`:

```verilog
// After parsing TRKS metadata (first 1280 bytes), skip to FLUX chunk
if (chunk_id == "TRKS" && chunk_index == 32'd1280 && chunk_left > 32'd512 && need_flux) begin
    scan_skip_target <= 16'd3 + chunk_left[24:9];  // Calculate target block
    scan_skip_active <= 1'b1;
    $display("WOZ_SCAN: TRKS skip - seeking to FLUX at block %0d", ...);
end

// In S_SCAN_WOZ state, execute skip by jumping sd_lba
if (scan_skip_active) begin
    sd_lba <= {16'b0, scan_skip_target} - 32'd1;
    scan_blocks <= scan_skip_target - 16'd1;
    scan_skip_active <= 1'b0;
    scan_skip_discard <= 1'b1;  // Discard remaining bytes in current block
    // Reset chunk parser state
    chunk_id <= 32'd0;
    chunk_hdr_pos <= 3'd0;
    ...
end
```

**Result**: FLUX chunk parsing is now fast - the scanner jumps directly from TRKS metadata to the FLUX chunk instead of reading through megabytes of track data.

### Critical Fix (2026-01-30): FLUX Timing - Fixed 125ns Tick Rate

**Problem**: FLUX tracks loaded correctly but sector decoding only got 1 out of 12 sectors on track 0. The decoded bytes had incorrect timing, causing IWM byte sync failures.

**Root Cause**: The phase accumulator in `flux_drive.v` was **scaling** FLUX timing based on `FLUX_TOTAL_TICKS`, stretching the flux data to fill a full 200ms rotation. This was WRONG.

The original code calculated:
```
flux_phase_inc = (ROTATION_CYCLES_14M * 1000) / FLUX_TOTAL_TICKS
```

For a WOZ file with `flux_total_ticks=112000`, this produced:
- `flux_phase_inc ≈ 2350` (instead of 1000)
- Effective tick duration: 2.35 cycles (instead of 1.79 cycles)
- This caused timing mismatch with `iwm_flux.v`'s fixed 28-cycle (2µs) window

**The Fix**: Disabled scaling entirely - use fixed 125ns tick rate:

```verilog
// rtl/flux_drive.v - FLUX timing fix
// FLUX timing: Always use fixed 125ns tick rate (1.79 clocks at 14MHz).
// WOZ FLUX format encodes real 125ns tick counts between transitions.
// Do NOT scale based on FLUX_TOTAL_TICKS - that caused timing mismatch
// with iwm_flux.v's fixed 28-cycle (2µs) window timing.
// The track data may not fill a full 200ms rotation, which is fine.
wire        flux_use_scaling = 1'b0;  // Disabled - use real 125ns timing
wire [31:0] flux_phase_inc = 32'd1000;
wire [31:0] flux_phase_mod = 32'd1790;
```

**Why fixed timing is correct**:
1. WOZ FLUX format stores actual 125ns tick counts between real flux transitions
2. The IWM hardware expects ~2µs (16 ticks × 125ns) bit cells
3. `iwm_flux.v` uses a fixed 28-cycle window for byte decoding
4. Scaling would stretch/compress timing, breaking the IWM window alignment

**Result**: FLUX sectors now decode correctly:
```
SECTOR: D5 AA AD at pos=1371 (data prologue)
SECTOR: DATA COMPLETE rawT=00 rawS=00 (512 bytes read)
SECTOR: *** STATS *** addr_ok=38 addr_fail=0 data_complete=50
```

### Critical Fix (2026-01-30): BRAM Address Truncation for Large FLUX Tracks

**Problem**: MAME-created FLUX WOZ files (e.g., `wozdisks/AppleWorks v3.0 800K.woz`) failed to boot with "Check startup device!" error, even though Applesauce-created BITSTREAM WOZ files worked. Debug showed BRAM reads returning wrong data - addresses 0-19 were being written multiple times with different values.

**Root Cause**: The `track_load_addr` calculation in `woz_floppy_controller.sv` used only 5 bits of `blocks_processed`:

```verilog
track_load_addr <= {blocks_processed[4:0], sd_buff_addr};  // 5+9=14 bits = 16KB max
```

This caused addresses to wrap after 32 blocks:
- Blocks 0-31: addresses 0-16383 ✓
- Block 32: wraps to address 0, **overwrites** block 0's data!
- Block 33: wraps to address 512, **overwrites** block 1's data!
- etc.

FLUX tracks can have 98+ blocks (50KB), so blocks 32-63 and 64-95 completely overwrote the data from blocks 0-31, corrupting the flux timing data.

**The Fix**: Increased all address widths from 14 to 16 bits to support FLUX tracks up to 64KB:

| File | Change |
|------|--------|
| `woz_floppy_controller.sv` | `track_load_addr`: 14→16 bits, BRAM: 16KB→64KB, `blocks_processed[4:0]`→`[6:0]` |
| `flux_drive.v` | `BRAM_ADDR` output: 14→16 bits, `byte_index` signals: 14→16 bits |
| `iwm_woz.v` | `WOZ_TRACK3_BIT_ADDR`: 14→16 bits |
| `iigs.sv` | Port declaration: 14→16 bits |
| `sim.v` | All related wires/registers: 14→16 bits |

```verilog
// rtl/woz_floppy_controller.sv - Fixed address calculation
track_load_addr <= {blocks_processed[6:0], sd_buff_addr};  // 7+9=16 bits = 128 blocks max
```

**Result**: MAME-created FLUX WOZ files now boot successfully. The AppleWorks splash screen loads correctly.

### Configuration Note: BRAM_LATENCY

For simulation, `WOZ_BRAM_LATENCY` must be set to 0 in `vsim/sim.v`:

```verilog
`define WOZ_BRAM_LATENCY 0  // 0=combinational (simulation), 1=registered (FPGA)
```

With `BRAM_LATENCY=1` (FPGA mode), there are known issues with motor spinning and position tracking that are still being resolved for FPGA synthesis.

### Resolved Issues with FLUX Tracks (2026-01-30)

The following issues from the previous session have been **RESOLVED**:

#### Previous Problem (Now Fixed)
Testing with `wozdisks/AppleWorks v3.0 800K.woz` previously showed:
- Only 1 out of 12 sectors on track 0 completed
- FLUX timing was stretched due to phase accumulator scaling
- FLUX chunk parsing was extremely slow (reading 1.3MB byte-by-byte)

#### Current Working State
After the fixes described above:
- Track 0 FLUX format (is_flux=1, flux_bytes=50060) - **WORKING**
- FLUX transitions generated with correct timing
- GCR bytes decoded with proper IWM window alignment
- **53+ sectors complete** (addr_ok=53, data_complete=53, prologue_miss=0)
- Both FLUX and BITSTREAM tracks read correctly

The FLUX decoding pipeline (flux_drive.v → iwm_flux.v) is now fully functional for WOZ v3 FLUX tracks.

### WOZ File Version Reference

Files in vsim/:
- `ArkanoidCrack.woz` - v3 (FLUX available, cracked version)
- `ArkanoidIIgs.woz` - v2 (BITSTREAM only, copy protected)
- `beagle.woz` - v2 (BITSTREAM)
- `BeagleDraw IIgs.woz` - v2 (BITSTREAM, works!)
- `Karateka.woz` - v3 (FLUX available)
- `Karateka side B.woz` - v1 (5.25" disk)

Files in wozdisks/:
- `ArkanoidIIgs.woz` - v3 (FLUX available)
- `beagle.woz` - v3 (FLUX available)
- Various other v2/v3 disks

### Completed FLUX Debugging Steps (2026-01-30)

1. ✅ **Fixed FLUX timing in flux_drive.v**: Disabled scaling, use fixed 125ns tick rate (1000/1790 ratio)
2. ✅ **Added TRKS skip optimization**: Fast FLUX chunk parsing by jumping over track data
3. ✅ **Verified sector decoding**: 53+ sectors complete with zero address failures
4. ✅ **Regression tests pass**: All 7 standard regression tests pass after fixes

### Remaining Work

1. **FPGA synthesis (BRAM_LATENCY=1)**: Still has motor/position issues
2. **Copy-protected WOZ v2 disks**: ArkanoidIIgs.woz (v2 BITSTREAM) still stuck at 25%
3. **Additional WOZ v3 FLUX testing**: Test more FLUX-format disks for broader compatibility

---

## Previous Status (before FLUX scan fix)

Testing WOZ disk images with the Apple IIgs simulator. WOZ v2 BITSTREAM format (ArkanoidIIgs.woz) boots successfully. All regression tests pass:

### CRITICAL FIX (2026-01-29): Sector Detection Timing Bug

**Bug**: The sector detection state machine in `iwm_flux.v` was checking `m_rsh` for prologue bytes (D5, AA, 96/AD) when `new_byte` fired, but due to Verilog non-blocking assignment (`m_rsh <= shifted_rsh`), `m_rsh` still contained the **old** value at that moment.

**Root Cause**: When `new_byte` fires (edge of `byte_completing`):
- `shifted_rsh` = the just-completed byte (blocking assignment in the main always block)
- `m_rsh` = the **previous** byte (non-blocking assignment, updates next cycle)
- `byte_complete_data` = combinational wire giving the completed byte value immediately

The sector detection was checking `m_rsh` instead of the combinationally-available `byte_complete_data`, causing all sector detections to fail.

**Fix Location**: `rtl/iwm_flux.v` lines 1207-1306

**Before (broken)**:
```verilog
if (new_byte) begin
    case (sec_state)
        SEC_IDLE: begin
            if (m_rsh == 8'hD5) begin  // WRONG: m_rsh has old value!
```

**After (fixed)**:
```verilog
if (new_byte) begin
    case (sec_state)
        SEC_IDLE: begin
            if (byte_complete_data == 8'hD5) begin  // CORRECT: use combinational value
```

**Impact**: Before the fix, sector stats showed `addr_ok=0, addr_fail=0, data_complete=0` because D5 never matched. After the fix, all 12 sectors per track are detected correctly.

---

Previous status:
- Arkanoid: PASS
- Total Replay: PASS
- Pitch Dark: PASS
- GS/OS: PASS
- Total Replay II: PASS
- BASIC boot: PASS
- MMU test: PASS

The false D5 AA AD detection at bit position ~1066 was thoroughly investigated and documented (see False Positives section below). It does NOT block boot - the system correctly rejects it and continues to find real sectors.

### CRITICAL FINDING (2026-01-29): FALSE POSITIVE D5 AA AD Detection

**Discovery**: The D5 AA AD sequence that vsim detects at bit position 1042-1066 is NOT a real data prologue - it's a FALSE POSITIVE that occurs when byte boundary alignment in the self-sync area happens to decode as the prologue pattern.

**Analysis Details**:

When decoding from bit position 1042 using standard GCR shift register rules (MSB=1 = byte complete):
```
Start bit 1042:
  Byte 0xD5 completes at bit 1050
  Byte 0xAA completes at bit 1058
  Byte 0xAD completes at bit 1066
  Byte 0xA6 completes at bit 1074  <-- NOT 0x9A!
  Byte 0x96 completes at bit 1082
```

**The Real Prologues**:

Python analysis of the raw WOZ track 0 data found only 3 real D5 AA AD sequences:
```
#1 byte=2441 bit=19528: D5 AA AD 9B 96 96 96 96 96 96 96 96 96 96 96
#2 byte=3958 bit=31664: D5 AA AD 9D 96 96 96 96 96 96 96 96 96 96 96
#3 byte=5475 bit=43800: D5 AA AD 9E 96 96 96 96 96 96 96 96 96 96 96
```

**Why the False Positive Occurs**:

The self-sync area contains bytes like `FF 3F F5 6A AB 69...` which are designed to help the disk controller regain byte synchronization. When byte boundaries align at bit 1042 (which is within the sync area), the shift register happens to decode:
- `0xD5` = 11010101
- `0xAA` = 10101010
- `0xAD` = 10101101
- `0xA6` = 10100110 (NOT the expected 0x9A for real sector data)

**Implications**:

1. The 0x9A byte was NEVER there at bit position 1066 - it's a false prologue
2. The real D5 AA AD prologues start around bit 19528+, much later in the track
3. vsim and MAME both see the same raw bits, but may start at different byte boundary alignments
4. The ROM/GS/OS should recognize the checksum failure on this false sector and continue searching

**MAME Position Comparison**:

MAME shows first D5 AA AD at position 19032196 (microseconds scale), corresponding to the real prologue at bit ~19528. vsim's false detection at bit ~1066 is in the sync area and should fail checksum validation.

**Detailed Byte Analysis (2026-01-29)**:

The raw BRAM bytes in the sync area:
```
byte 0x7B = FF (sync)
byte 0x7C = 3F (sync)
byte 0x7D = CF (sync)
byte 0x7E = F3 (sync)
byte 0x7F = FC (sync)
byte 0x80 = FF (sync)
byte 0x81 = 3F (sync)
byte 0x82 = F5 (sync)
byte 0x83 = 6A (sync)
byte 0x84 = AB (sync)
byte 0x85 = 69 (sync)
byte 0x86 = A5 (sync)
```

The M_DATA_CHANGE events show how these decode:
```
M_DATA_CHANGE #90: ff -> d5 @pos=1050 (from F5 6A bit pattern)
M_DATA_CHANGE #91: d5 -> aa @pos=1058 (from 6A AB bit pattern)
M_DATA_CHANGE #92: aa -> ad @pos=1066 (from AB 69 bit pattern)
M_DATA_CHANGE #93: ad -> a6 @pos=1074 (from 69 A5 bit pattern) <-- NOT 0x9A!
M_DATA_CHANGE #94: a6 -> 96 @pos=1082 (from A5 ...)
```

**Key Observation**: The real header prologue at pos=928 uses LITERAL BRAM bytes (0x71=D5, 0x72=AA, 0x73=96), while the false data prologue emerges from sync pattern BIT alignment.

**Next Investigation**:
1. Check why the ROM doesn't continue searching after checksum fails on the false prologue
2. Verify byte boundary alignment between vsim and MAME at track start
3. Investigate if there's a synchronization issue causing vsim to lock onto the wrong byte alignment
4. Check if the ROM ever actually reads the bytes after D5 AA AD and detects the A6 instead of 9A

**Update (2026-01-29): Extended Prologue Analysis**

Running for 200 frames shows the system DOES continue past the false positive:
```
IWM_PROLOG_OK: d5 aa 96 pos=928   <-- First header (sector 0)
IWM_PROLOG_OK: d5 aa ad pos=1066  <-- FALSE POSITIVE (in sync area)
IWM_PROLOG_OK: d5 aa 96 pos=6996  <-- Second header (sector 1)
IWM_PROLOG_OK: d5 aa ad pos=7157  <-- Data prologue (sector 1)
IWM_PROLOG_OK: d5 aa 96 pos=13346 <-- Third header (sector 2)
... continues with more sectors ...
```

The system wraps around the track (75215 bits) and detects prologues repeatedly. This confirms:
1. The false positive at pos=1066 does NOT block subsequent sector reads
2. The ROM/driver continues searching after checksum failure
3. Multiple disk rotations occur with sectors being read

**Comparison with WOZ File (Byte-Aligned)**:
- WOZ file has literal D5 AA 96 at bit 904, 57624 (only 2 headers)
- WOZ file has literal D5 AA AD at bit 19528, 31664, 43800 (only 3 data prologues)
- vsim detects many more at different positions

This difference exists because:
1. WOZ stores RAW BITS, not bytes
2. The IWM shift register determines byte boundaries dynamically
3. Self-sync bytes establish correct alignment after gaps
4. The "extra" prologues vsim detects are where bit patterns align correctly

**Next Steps**:
1. Focus on why boot hangs at 65% despite successful sector reads
2. Check if specific track/sector combinations have issues
3. Investigate M_DATA_CHANGE oscillation patterns (00->val->00) seen in later trace

---

### CONFIRMED ROOT CAUSE (2026-01-28): Missing First Data Byte After D5 AA AD

**Critical Finding - Byte-level comparison confirms the issue:**

MAME reads after D5 AA AD prologue:
```
D5 AA AD 9A 96 96 96 96 96 96 96 96 96 96 96 96 96 96 96 96 96 9B B2 ...
         ^^-- First data byte is 0x9A (CORRECT)
```

vsim reads after D5 AA AD prologue:
```
D5 AA AD 96 96 96 96 96 96 96 96 96 96 96 96 96 96 96 96 96 96 96 96 ...
         ^^-- First data byte is 0x96 (WRONG - 0x9A is MISSING!)
```

**Impact**: The missing 0x9A byte causes:
1. GCR checksum errors on EVERY sector data read
2. OS retries the sector read multiple times
3. After repeated failures, OS does a full disk scan (tracks 0→45→0)
4. Progress bar stalls at ~65% because required data can never be read correctly

### Update (2026-01-28): ACTUAL Root Cause - Byte Overwrite in Async Mode

**New Analysis**:

The earlier "race condition" hypothesis was WRONG. Debug logs showed:
```
IWM_9A_DEBUG: byte=9a rd_in_progress=0 rd_consumes=0 rd_from_compl=0 ...
```

When 0x9A completes, `rd_in_progress=0` - the CPU is NOT reading at that moment!

**Actual timing sequence**:
1. pos=7161: CPU reads DATA register (@8, q6=0) -> gets `ad`
2. pos=7167: CPU reads STATUS register (@c, q6=1) -> 0x9A is in m_data but CPU reads status, not data!
3. pos=7207: CPU reads DATA register (@8, q6=0) -> gets `0x96` (0x9A was OVERWRITTEN)

**Real Root Cause**:

Between pos=7165 (when 0x9A completes) and pos=7207 (when CPU next reads DATA), approximately 5 bytes complete:
- 0x9A @ pos=7165
- 0x96 @ pos=7173
- 0x96 @ pos=7181
- ... etc

In vsim, each completing byte UNCONDITIONALLY overwrites `m_data`, even if the previous byte hasn't been read yet!

**MAME's behavior**:

In MAME's async mode (`iwm.cpp`), a newly completed byte does NOT overwrite `m_data` if:
1. `m_data` already has bit7=1 (valid byte present), AND
2. `m_data_read` is false (CPU hasn't consumed it yet)

This preserves 0x9A until the CPU reads it, even though 0x96 bytes complete afterward.

**FIX APPLIED** (2026-01-28):

Modified byte completion logic in `rtl/iwm_flux.v` (both EDGE_0 and EDGE_1 paths):

```verilog
// MAME async mode: only update m_data if:
// 1. Sync mode (always update), OR
// 2. No valid unread byte in m_data (!m_data[7]), OR
// 3. CPU has read the previous byte (m_data_read), OR
// 4. CPU is reading this completing byte (rd_consumes_byte)
// This prevents new bytes from overwriting unread bytes in async mode.
if (!is_async || !m_data[7] || m_data_read || rd_consumes_byte) begin
    m_data <= shifted_rsh;
    m_data_gen <= m_data_gen + 32'd1;
    m_data_read <= (rd_consumes_byte && (rd_data_latched == shifted_rsh)) ? 1'b1 : 1'b0;
    async_update_pending <= 1'b0;
    // ... latch mode handling ...
end
```

This matches MAME's async mode semantics: bytes that complete while a previous unread byte is still in m_data are DROPPED instead of overwriting.

**Status**: FIX REVERTED - Needs Different Approach

### Update (2026-01-28): Async Protection Fix REVERTED

**What Happened**:

The "MAME async mode" protection fix that prevented bytes from overwriting unread bytes was too aggressive. It caused D5, AA, and AD prologue bytes to be DROPPED because an earlier byte (FE) was blocking:

```
IWM_9A_DROP(E1): byte=ad DROPPED pos=7157 async=1 m_data=fe m_data_read=0 (unread byte blocking)
```

Detailed trace showed:
1. FE byte was in m_data with m_data_read=0 (CPU hadn't read it yet)
2. D5 completed at pos=7141 - DROPPED (FE blocking)
3. AA completed at pos=7149 - DROPPED (FE blocking)
4. AD completed at pos=7157 - DROPPED (FE blocking)
5. CPU finally read FE at pos=7161
6. 9A completed at pos=7165 - STORED (m_data_read=1 now)
7. CPU read 9A at pos=7167
8. 96 completed at pos=7173 - STORED (m_data_read=1)

**Result**: The CPU byte stream was `..., FE, 9A, 96, ...` instead of `..., FE, D5, AA, AD, 9A, 96, ...`

This completely broke sector framing by dropping the D5 AA AD data prologue!

**Why The Fix Failed**:

The fix checked `!is_async || !m_data[7] || m_data_read || rd_consumes_byte` to decide whether to store a new byte. This correctly identifies that FE is an "unread valid byte" that shouldn't be overwritten. But it doesn't distinguish between:

1. **FE blocking D5**: FE is "stale" - the CPU is polling and will read it soon, but D5/AA/AD arrive before the CPU reads. These bytes SHOULD overwrite because the CPU is actively reading.

2. **96 overwriting 9A**: 9A is "fresh" - it just arrived and the CPU is pausing (processing the D5 AA AD prologue). 96 should NOT overwrite because the CPU hasn't had time to read 9A.

**Correct Behavior (MAME)**:

After analyzing the actual MAME logs and comparing, the correct behavior appears to be:
- Bytes always overwrite m_data (no dropping based on m_data_read)
- The async_clear mechanism is used to clear m_data after a timeout
- The CPU must read fast enough to not miss bytes

**Current State**:

Reverted all async protection changes. The original behavior is restored:
- All bytes overwrite m_data unconditionally
- 9A will be overwritten by 96 before the CPU reads it (original bug)
- But D5 AA AD prologue is correctly preserved

**Next Steps for Future Investigation**:

1. Compare actual MAME CPU read timing vs vsim CPU read timing
2. Check if vsim's clock divider is causing the CPU to poll too slowly
3. Investigate if the `latch_mode` (bit 0 of IWM mode register) should extend byte availability
4. Check MOTOR_ACTIVE transitions during the critical window

**Key Insight from Debug Trace**:

The detailed trace showed that at pos=7167, the CPU DOES successfully read 9A:
```
read_iwm 0ec ret: 9a ... pos=7167 ...
IWM_FLUX: READ DATA @c -> 9a cycle=24192896 pos=7167 (active=0 spin=1 ...)
```

However, `active=0` means MOTOR_ACTIVE is low at this point (even though motor is spinning). The comparison scripts filter out `active=0` reads, making it APPEAR that 9A was never read.

This suggests the actual issue may be:
1. A comparison artifact (the CPU gets 9A but it's not counted), OR
2. Something in the ROM/GS/OS code that depends on MOTOR_ACTIVE being high, OR
3. The original 9A overwrite problem is ALSO happening in addition to the active=0 filtering

**Files Changed**:
- `rtl/iwm_flux.v`: Reverted async protection fix in both EDGE_0 and EDGE_1 paths

---

### Update (2026-01-28): Byte Stream Corruption After Header Epilogue

**Problem Summary**:
- MAME: Reads ~770K valid bytes in ~1323 frames, then game starts
- vsim: Reads ~1.4M valid bytes in ~2300 frames, progress bar stuck at ~65%
- vsim reads valid sector headers but data AFTER the DE AA epilogue is corrupted

**How to Reproduce**:
```bash
cd vsim
make clean && make

# Run vsim (1500 frames is sufficient to see the issue)
./obj_dir/Vemu --woz ArkanoidIIgs.woz --stop-at-frame 1500 2>&1 | tee vsim_ark_compare.log

# Compare with MAME log (ark_three_mame.log already captured)
python3 compare_sectors.py
python3 analyze_byte_streams.py
```

**Key Findings**:

1. **486-byte offset**: vsim reads 486 garbage bytes before finding first sector header
   - MAME: First D5 AA 96 header at byte index 32
   - vsim: First D5 AA 96 header at byte index 518
   - This is normal - they start at different disk positions after spinup

2. **Sector header correctly decoded**:
   - WOZ file sector 1: `d5 aa 96 96 9a 96 d9 d6 de aa ff ff ff ff e7 f9 fe ff ff d5 aa ad 9a 96...`
   - vsim reads:        `d5 aa 96 96 9a 96 d9 d6 de aa dd ff b7 ad fd fd da ae 9d f2...`
   - First 10 bytes match perfectly (`d5 aa 96 96 9a 96 d9 d6 de aa`)

3. **Corruption starts after DE AA header epilogue**:
   - Expected (from WOZ): `de aa ff ff ff ff e7 f9 fe ff ff d5 aa ad`
   - vsim reads:          `de aa dd ff b7 ad fd fd da ae 9d f2`
   - First byte after epilogue: should be `ff`, vsim gets `dd`
   - `0xDD` = 11011101, `0xFF` = 11111111 (2 bits different)

4. **Position tracking appears correct**:
   - vsim reads D5 at position 6980
   - WOZ has D5 at position 6979
   - Only 1 bit difference - close enough

**Root Cause Hypothesis**:
The header is decoded correctly (10 bytes match). The corruption happens during the sync-byte gap between header and data. Possible causes:
1. Timing drift after DE AA causes bit slip
2. Window alignment issue during FF sync bytes
3. IWM state machine issue after reading the header epilogue

**Scripts Used**:
- `compare_sectors.py` - Compare D5 AA markers between MAME and vsim
- `analyze_byte_streams.py` - Analyze byte distribution and sector markers
- `check_track_data.py` - Decode WOZ track data at specific positions
- `compare_aligned.py` - Compare bytes with offset alignment

**Files Modified (FIX9)**:
- `rtl/iwm_flux.v` - Added continuous async deadline check (MAME-style)

**Root Cause Identified**:

After reading the header epilogue (DE AA), the CPU takes a **229µs pause** before attempting to read more data:
- cycle=24189690 pos=7053: AA (last header byte, DATA read q6=0)
- cycle=24192896 pos=7167: 9a (STATUS read q6=1) - **3206 cycles later!**

This 229µs gap far exceeds the async deadline (2µs / 28 cycles), so any FF sync bytes in m_data get cleared. When the CPU finally reads DATA again, m_data is 00 and the driver sees "no data". It eventually gives up on the sector.

In contrast, MAME continues reading DATA bytes (FF sync) with ~19µs spacing after DE AA.

**Detailed Analysis**:

The WOZ track at position 7140+ shows: `d5 aa ad 9a 96 96...` (data prologue + sector data)

At cycle 24192896 (pos=7167), vsim returns `data=9a` - which is CORRECT! This matches the first data byte after D5 AA AD in the WOZ file. The IWM is decoding correctly.

**However**, the read at pos=7167 has `active=0` (MOTOR_ACTIVE=0), so:
1. Comparison scripts filter this out (`active=1 spin=1` required)
2. The byte appears "missing" in comparisons even though it was returned correctly

**What happens after DE AA**:
1. cycle=24189690 pos=7053: AA byte read (active=1, motor on)
2. Something causes MOTOR_ACTIVE to go low (drive_on command changes?)
3. cycle=24192896 pos=7167: 9A byte read (active=0, motor still spinning but command off)

The data IS being read correctly, but MOTOR_ACTIVE drops, causing the comparison to think bytes are missing.

**Key Question**: Why does iwm_active (MOTOR_ACTIVE) go low after the header epilogue? The motor is still spinning (spin=1), so the delay timer is counting down.

This could be caused by:
1. Mode register bit 2 set (immediate motor off)
2. drive_on command going low between accesses
3. IWM delay counter expiring

### Update (2026-01-28): Motor Toggling Investigation Complete

**Findings from motor_test_1500.log**:

The motor is being toggled on/off very frequently during boot - dozens of times. Each transition shows:
```
IWM_WOZ: drive_on 0 -> 1 (is_35=1 ready=0100 motor_spinning=0)
IWM_WOZ: iwm_active 0 -> 1 (drive_on=1 mode=0f delay_cnt=14000000)
IWM_WOZ: drive_on 1 -> 0 (is_35=1 ready=0100 motor_spinning=0)
IWM_WOZ: iwm_active 1 -> 0 (drive_on=0 mode=0f delay_cnt=0)  <-- delay_cnt=0 means IMMEDIATE off
```

**Critical observation**: `mode=0f` has bit 2 set, which triggers **immediate motor off** (no 1-second delay).
This is correct behavior per the IWM spec - the ROM sets mode=0x0F intentionally.

**Comparison with MAME**:
MAME log shows `m_motors_active=00` consistently! This means MAME does NOT use the IWM motor softswitch
state to gate 3.5" drive operations. The 3.5" Sony drives are controlled via Sony commands (sent via
phase lines), not the IWM motor command.

**Key code paths in iwm_flux.v**:
- Line 480: `if (MOTOR_SPINNING && DISK_READY)` - State machine runs on physical spinning, NOT motor command
- Line 340: Motor command changes reset read/write state but don't stop flux decoding
- The data IS being read correctly even when MOTOR_ACTIVE=0

**Specific timing at DE AA transition**:
```
pos=7053: AA byte read (active=1, motor command on)
pos=7074: ff byte read (active=1)
pos=7109: f9 byte read (active=0) <-- Motor command went off between pos 7074-7109
pos=7167: 9a byte read (active=0, q6=1 = STATUS read)
```

**Root Cause Update**:
The original hypothesis about 229µs async timeout was WRONG. The data is NOT being lost due to async clear.
The bytes ARE being decoded correctly:
- pos=7109: f9 (data prologue sync)
- pos=7161: ad (data prologue marker)
- pos=7167: 9a (first data byte after D5 AA AD)

The comparison scripts were filtering out `active=0` reads, making it APPEAR that bytes were missing.
In reality, the bytes are there but the motor command (iwm_active) is off.

**Updated Byte Count Comparison (2026-01-28)**:

Re-measured byte counts with more precise filtering (non-zero, non-ff, active=1):
- MAME: 730,997 data bytes (frames 72-1323)
- vsim: 824,941 data bytes (frames 0-1323)
- Ratio: 1.13x (only 13% more, NOT 2x as originally thought!)

The earlier "2x" claim was likely based on total IWM reads including inactive/placeholder bytes.

Sector header count:
- MAME: 1,310 D5 markers
- vsim: 1,667 D5 AA 96 patterns

The 13% difference could be explained by:
1. vsim starting ~72 frames earlier (before MAME begins logging)
2. Different byte decoding timing at bit boundaries
3. Motor toggling creating extra overhead reads

**Track Seek Pattern Difference**:

MAME track access pattern (frame 0-1323):
- Tracks 0-9: Many reads (boot blocks, catalog)
- Tracks 10-31: Almost no reads (1-2 bytes each)
- Tracks 32-36: Heavy reads (game code/data)
- Ends on track 33 when boot completes

vsim track access pattern (frame 0-1323):
- Full linear sweep: 0 -> 45 -> 0 (visiting each track twice)
- Then oscillates between tracks 0-7
- Ends bouncing between tracks 0-4

**Key Difference**: vsim does a linear sweep of ALL tracks, while MAME jumps directly to specific tracks (0-9, then 32-36). This suggests:
1. vsim's GS/OS disk driver is not finding files in the catalog correctly
2. Or some sector read is failing, causing a full disk scan
3. Or the directory structure is being misread

**Sector Detection Working**:
Both sector header (D5 AA 96) and data prologue (D5 AA AD) markers are being found correctly at consistent positions (1066, 7157, 13484, etc.).

**Motor Command Mismatches**:
Early in boot (frame 71), there are WOZ_CMP MOTOR_CMD MISMATCHes between `motor_on` and `sony_motor_on`, but these appear to be startup timing differences between C++ and Verilog paths.

**Next Investigation**:
1. Check if sector data bytes are correct after the D5 AA AD prologue
2. Verify GCR checksum handling
3. Compare first 20-30 data bytes of a specific sector between MAME and vsim
4. Check if the boot loader is failing to parse catalog/directory blocks

**Next Steps**:
1. Compare sector-by-sector read patterns between MAME and vsim
2. Check if vsim is re-reading sectors that fail CRC checks
3. Investigate why progress bar stalls at 65% - what specific file/data is being read at that point
4. Compare C++ emulator behavior (does it also read 2x bytes?)

### Update (2026-01-26): Track Stepping Never Happens - ROM Not Issuing WriteBit for Steps

**Critical Finding**: The disk drive never steps off track 0. The ROM issues ReadBit (sense status reads) but never issues WriteBit (step commands).

**Evidence from woz_step_test.log (300 frames)**:
- Only 10 LSTRB pulses ($C0E7/$C0E6 sequence) total
- None have phases=0001 (CA0=1, CA1=0, CA2=0) required for step command
- All LSTRB pulses have sony_ctl=0,1,3,8 (direction, eject_reset, motor) - never 4 (step)
- `head_phase` stays at 0 forever - drive never steps
- `bit_count=75215` (track 0) throughout the entire log

**Comparison with MAME (ark_three_mame.log)**:
- MAME shows many `cmd step on` commands by frame 297
- MAME reaches track 23 by frame 1568
- vsim stays on track 0 forever

**What the ROM does vs what it should do**:

The IIgs ROM's `WriteBit` routine (FF:4985) should:
1. Call `SDCLINES` to set up CA0/CA1/CA2
2. Pulse LSTRB with `BIT $C0E7` then `BIT $C0E6`

For step command (sony_cmd=4 = 0100):
- CA0=1, CA1=0, CA2=0 → phases should be 0001

**What we observe**:
- ROM calls `SDCLINES` (we see CA0/CA1/CA2 phase changes)
- ROM then accesses $C0ED (Q6 status read) instead of pulsing LSTRB
- This is the `ReadBit` code path, NOT `WriteBit`

**Log trace showing the issue** (around line 898492):
```
FF:49B3: bit $c0e1          ; Set CA0=1 (for step command setup)
IWM_WOZ: phases 0110 -> 0111
FF:49B9: bit $c0e2          ; Clear CA1
IWM_WOZ: phases 0111 -> 0101
FF:49BC: rts                ; SDCLINES returns
FF:497E: bit $c0ed          ; ← ReadBit path! Should be $C0E7 for WriteBit
```

**Root Cause Hypothesis**:
The GS/OS boot loader is NOT requesting seeks to other tracks. Possible reasons:

1. **Wrong status/sense values**: Some status bit may be incorrect, causing the driver to skip stepping
2. **CONFIGURE sequence incomplete**: The 3.5" drive initialization may not be completing correctly
3. **Data confusion**: Sector reads may be returning wrong data, confusing the boot loader about what it's reading

**Why progress bar fills but boot hangs**:
- Track 0 contains enough boot code to start GS/OS and show progress bar
- GS/OS needs data from other tracks to complete boot
- Without stepping, it re-reads track 0 forever, eventually hanging

**Next Steps**:
1. Compare STAT35 sense values between MAME and vsim for each status query
2. Trace the CONFIGURE/DISKSWITCH handling to verify 3.5" drive is properly initialized
3. Check if any error condition causes the driver to skip the seek code path
4. Compare early boot sequence (before first step) to identify divergence point

**Key Files**:
- `rtl/flux_drive.v` - sony_cmd_strobe handling, STEP command (case 4'h4)
- `rtl/iwm_woz.v` - phase register updates, LSTRB routing
- IIgsRomSource/Bank FF/ad35driver_subroutines.asm - WriteBit, SDCLINES, SendSteps

### Update (2026-01-24): Consolidated Status + Recent Experiments

**What improved things**
- **BRAM latency** fix (Port B combinational read) restored correct byte stream and allowed the GS/OS progress bar to fill.
- **Bitstream edge alignment**: `FLUX_TRANSITION` is now combinational for BITSTREAM mode (no 1-cycle lag), and `IWM_EDGE0_HIT` aligns with `FLUX_DRIVE_FLUX` (cycle delta = 0) around bad prologs.
- **Boundary handling**: Late EDGE_0 edges are carried into the next window to avoid window-boundary misses.

**What did NOT fix the hang**
- **Flux pulse offset tweaks** for 3.5" (`offset=2`, `1`, `0`) did not resolve the missing first data byte after `D5 AA AD`.
- **Clock divider slow gating**: slot-5 and slot-6 motor slow are now gated by `disk35_sel`, and logs show `slow_req=0` during IWM reads. Hang persists.
- **Same-cycle byte completion + ack gating** reduced some false clears but still leaves the first data byte missing on early track-0 sectors.

**Key observations**
- `IWM_9A_COMPLETE` confirms `0x9A` is decoded at `pos~7165`, but CPU reads still see `D5 AA AD` followed by `0x96`, skipping the `0x9A`.
- `iwm_compare.py --data-fields-by-sector` continues to show early track-0 sector shifts (best alignment shift -1 / -2), while later tracks match MAME.
- `IWM_READ_ACK_PROLOG` shows many **status reads** (`q6=1 q7=0`) in the prolog window; these can schedule async clears and potentially drop the first data byte.

**Recent changes under test**
- **Async clear scheduling now gated to DATA-register reads only** (Q7=0, Q6=0). Status reads no longer schedule async clears.
- **Flux transition latency removed** (bitstream path is combinational).
- **Slot 5 slow gating added** for 3.5" (`disk35_sel`), to avoid slow-mode during 3.5" boot.

**Possible next steps**
1) Verify whether the new async-clear gating fixes the missing `0x9A` in the CPU READ DATA stream.
2) Add focused logs around `pos=7135..7185` to capture `rd_data_latched`, `rd_latched_valid`, `rd_ack_take`, and `m_data_read` over a full PHI2 cycle.
3) If the gap remains, consider **holding `m_data` longer** (longer latch-hold window) or preventing any clear while a new byte completes in the same cycle.
4) Investigate **DISK35 toggling without $C031 writes** (ROM reads are flipping DISK35 in logs). Confirm slot select / disk35 wiring and whether this affects drive side or speed gating.
5) Cross-check MAME: when does it clear `m_data` relative to status reads vs data reads, and what exact read/ack ordering does it use.

### Change Log (Recent)

- 2026-01-30: **FLUX timing fix** - Disabled scaling, use fixed 125ns tick rate.
  - `rtl/flux_drive.v`: `flux_use_scaling = 1'b0`, `flux_phase_inc = 32'd1000`, `flux_phase_mod = 32'd1790`
  - Root cause: Phase accumulator was stretching FLUX data to fill 200ms rotation, causing timing mismatch with IWM's 28-cycle window.
- 2026-01-30: **TRKS skip optimization** - Fast FLUX chunk parsing by jumping over track data.
  - `rtl/woz_floppy_controller.sv`: Added `scan_skip_target`, `scan_skip_active`, `scan_skip_discard` registers.
  - After parsing first 1280 bytes of TRKS metadata, skip directly to FLUX chunk location.
- 2026-01-30: **BRAM_LATENCY=0** for simulation (FLUX motor issues with latency=1).
  - `vsim/sim.v`: `WOZ_BRAM_LATENCY 0` for working FLUX tracks.
- 2026-01-24: Gate async clear scheduling to **data-register reads only** (Q7=0, Q6=0), to avoid status reads clearing `m_data`.
  - `rtl/iwm_flux.v`: async clear scheduling check now requires `!access_q7_latched && !access_q6_latched`.
- 2026-01-24: Gate slot-5 motor slow by `disk35_sel` (3.5" selected => no slow mode).
  - `rtl/clock_divider.v`: added `slot5_motor_slow` and use in `slow_request`.
- 2026-01-23: Remove 1-cycle latency in bitstream flux transitions.
  - `rtl/flux_drive.v`: `FLUX_TRANSITION` is combinational in BITSTREAM mode.
- 2026-01-23: Carry late EDGE_0 edges into the next window to avoid boundary misses.
  - `rtl/iwm_flux.v`: `late_edge0` / `flux_now` handling.
- 2026-01-23: Same-cycle byte completion + read-ack gating to avoid clearing newly completed bytes.
  - `rtl/iwm_flux.v`: `byte_complete_data`, `rd_ack_take` matching logic.
- 2026-01-23: 3.5" flux pulse offset experiments (0/1/2 cycles). No improvement.
  - `rtl/flux_drive.v`: `flux_pulse_offset` toggled; current value `0`.
- 2026-01-24: Disabled scaled bit-cell timing (fixed rotation period) due to regression (OS hang).
  - `rtl/flux_drive.v`: keep constant 2us-ish cells (28/29 cycles) for 3.5" bitstream.
- 2026-01-24: IWM timing test: forced IWM I/O (`C0E0`-`C0EF`) fast; no improvement, reverted.
  - `rtl/clock_divider.v`: temporary slowMem exception added then removed.
- 2026-01-24: Latch-mode hold test (drop new byte if unread) reduced data marks and regressed boot; reverted.
  - `rtl/iwm_flux.v`: restored unconditional overwrite on byte completion.
- 2026-01-22: Async clear scheduling rework aligned to MAME-style timing (last sync + 28 @ 14MHz).
  - `rtl/iwm_flux.v`: `async_update_deadline` based on `last_sync_14m`.
- 2026-01-22: Added scripts to compare vsim vs MAME data streams and flux window alignment.
  - `vsim/iwm_compare.py`: updated regex for `cycle=...` format.
  - `vsim/flux_window_analyze.py`: summarize edge timing around bad prologs.

### Update (2026-01-23): Flux Pulse Timing Shift for 3.5"

- New `vsim/ark_hang.log` shows a repeatable mismatch at `pos=70221`: vsim decodes `0x97` where MAME expects `0x9A` (data prologue byte sequence becomes `D5 AA AD 97` instead of `D5 AA AD 9A`).
- Targeted logs around `pos=70214..70221` show flux pulses arriving at mid-cell (`timer=14` with `cell=28`) and landing just after the IWM window shift, so the pulse is attributed to the *next* bit.
- **Change applied**: shift 3.5" bitstream flux pulses earlier by 6 cycles to avoid the window-edge miss.
  - `rtl/flux_drive.v`: `flux_pulse_offset = IS_35_INCH ? 6'd6 : 6'd1`
  - Flux transition now triggers at `bit_timer == bit_half_timer + flux_pulse_offset`.
- **Next**: rebuild and re-run with the same logging window to verify the byte changes to `0x9A` and the prologue becomes `D5 AA AD 9A`.

### Latest Findings (2026-01-22)

- Logs: `vsim/ark_fix11.log` (verilog) and `vsim/ark_mame_two.log` (MAME).
- Track decode: Track 0 byte stream matches the raw WOZ track 0 bitstream for a full rotation. Side 1 reads also match expected byte sequences at the logged bit positions.
- CPU read stream: Using `python3 vsim/iwm_compare.py vsim/ark_mame_two.log vsim/ark_fix11.log --cpu-data`, the CPU-visible data stream is phase-shifted by ~53.5 degrees (MAME bit positions ~19k vs vsim ~7.9k for the earliest valid reads).
- Header count mismatch: MAME shows 76 `D5 AA 96` headers in the initial window; vsim shows 108. Header signatures from MAME do exist in vsim, but at different indices (stream alignment mismatch, not missing flux data).
- Tooling update: `vsim/iwm_compare.py` parsing now recognizes MAME lines with `frame=... pos=...` so position comparisons are valid.

### Update (2026-01-22, late): Data Field Byte Loss After D5 AA AD

- New debug window around `pos=13330` (sector 8 header) shows the CPU read stream **skipping two bytes** immediately after a data prologue (`D5 AA AD`).
  - Example (CPU READ DATA stream): `D5 AA AD` at `pos=7141/7149/7159`, then first data byte seen at `pos=7181` (0x96).
  - The expected `0x9A` and following `0x96` bytes at `pos=7165/7173` are missing.
- `iwm_compare.py --data-fields-by-sector` confirms consistent 1–2 byte shifts on early track 0 sectors (mismatches remain on sectors 0–6, 11).
- Hypothesis: **same-cycle read bypass is missing**.
  - `data_out_mux` uses `byte_completing` derived from `m_rsh` (old value), so a byte that completes at the end of the window is not visible until the next cycle.
  - If the CPU reads during the completion cycle, it latches the old value and the new byte is lost.
- Fix in progress: predict byte completion combinationally and use the *new* byte for same-cycle reads.
  - Added `shift_edge0_now/shift_edge1_now` and `byte_complete_data` to drive `byte_completing` and `effective_data_raw`.
  - This should make `D5/AA/AD/9A` sequences visible to CPU reads in the correct cycle.

**Next**: Re-run ArkanoidIIgs.woz (`--dump-vcd-after 2201 --stop-at-frame 2205`) and verify:
1) `D5 AA AD 9A` sequence is present in the CPU READ DATA stream.
2) `iwm_compare.py --data-fields-by-sector` shows no early-sector shifts.

### Update (2026-01-22, later): Same-Cycle Read Bypass Still Missing 0x9A

- Re-run with the predicted same-cycle byte completion still shows a gap after the data prologue in the CPU READ DATA stream.
  - Example (CPU READ DATA): `D5 AA AD` at `pos=7141/7149/7159`, then `0x96` at `pos=7181` (missing `0x9A` and one `0x96`).
- `WOZ_RAW DATA` lines in `vsim/ark_hang.log` show the on-disk sequence is correct (`D5 AA AD 9A 96 96 ...`), so flux decode is fine.
- `iwm_compare.py --data-fields-by-sector` still reports the same early track 0 sector mismatches (sectors 0–6, 11).

**Hypothesis**: CPU read timing still misses the first data byte when it completes near the end of the read cycle.

**Next**:
1) Move the focused read/byte-complete debug window to `pos=7100..7200` (data prologue area) and log `rd_latched_valid`, `data_ready`, `m_data_read`, and `effective_data`.
2) Re-run ArkanoidIIgs.woz and verify whether the CPU ever latches `0x9A` at `pos=7165` immediately after `D5 AA AD`.

### Update (2026-01-22, ark_hang.log + vsim.vcd): Read Ack Likely Overwrites New Byte

- New capture: `vsim/ark_hang.log` with VCD window `vsim.vcd` (`--dump-vcd-after 2201 --stop-at-frame 2205`).
- `IWM_9A_COMPLETE` confirms `0x9A` completes at `pos=7165`, so the byte stream is correct.
- CPU READ DATA window still shows `D5 AA AD` at `pos=7141/7149/7159`, then next valid read at `pos=7181` (`0x96`), skipping `0x9A` and the first `0x96`.
- At `pos=7165`, `IWM_9A_COMPLETE` logs `m_data=AD` and `m_data_read=0`, meaning the previous byte is still unacknowledged when the new byte completes.
- Likely race: the PHI2 falling-edge read ack for the previous byte happens after the new byte completes and sets `m_data_read=1`, effectively clearing the new byte before the CPU ever sees it.

**Proposed Fix**: Only set `m_data_read` on the read ack if the latched read byte matches the current `m_data` (or if `byte_completing` is false). This prevents a late ack for the old byte from clearing a newly completed byte that the CPU never observed.

**Next Logging**: Add a PHI2-fall `IWM_READ_ACK` debug line with `rd_data_latched`, `m_data`, `byte_completing`, `byte_complete_data`, `rd_latched_valid`, and `m_data_read` to confirm the mismatch.

### Update (2026-01-22, ack gating + compare): Missing First Data Byte Persists

- `IWM_READ_ACK` confirms the CPU *can* read `0x9A` at `pos=7165` in some cases (ack gating works as intended).
- `iwm_compare.py --data-fields-by-sector --num-sectors 40 vsim/ark_mame_two.log vsim/ark_hang.log` still shows early-track mismatches:
  - Track 0 sectors 0–6 and 11 have the **first byte shifted** (`0x9A` becomes `0x96`, best alignment shift -1 or -2).
  - Later tracks match MAME perfectly.
- This suggests a **timing overrun** only during early track 0 reads (ROM still in slow mode).

**Hypothesis**: 3.5" bit cell timing is still too fast. We disabled fractional windows, so the bit cell is 28 cycles (1.955us) instead of 28.636 cycles (2.000us). The ~2.2% speedup can cause the ROM’s initial read loop to miss the first one or two bytes after a data prologue.

**Next Change**: Re-enable fractional windows for 3.5" (`use_fractional_window = IS_35_INCH`) so the average cell time is 2us and the CPU has enough time to catch the first data bytes.

### Update (2026-01-22, fractional bit cell in flux_drive)

- The IWM window fractional timing alone did not change the early track-0 mismatches.
- Likely root cause shifts to the **bitstream generator**: `flux_drive.v` still used a fixed 28-cycle bit cell for 3.5" (1.955us), ~2.2% too fast.
- Fix applied: enable fractional 3.5" bit cells in `rtl/flux_drive.v` (28.636 cycles average) and track the per-cell length in `bit_cell_cycles_reg` so flux checks align with the current cell length.

**Next**: Re-run ArkanoidIIgs.woz and verify `iwm_compare.py --data-fields-by-sector` shows the first byte after data prologues aligned on track 0.

### Update (2026-01-22, async clear scheduling aligned to MAME)

- Reworked async clear timing in `rtl/iwm_flux.v` to match MAME: schedule m_data clear at `last_sync + 14` (7MHz) → `last_sync_14m + 28` (14MHz).
- Scheduling now occurs on **any** IWM access in read mode (Q7=0) when a valid byte is present, not just DATA-register reads.
- New debug log: `IWM_ASYNC_SCHED` (gated to `pos=7100..7200`) logs `last_sync` and clear deadline; `IWM_ASYNC_CLEAR` now logs pending clears in the same window.
- Async clear still defers during PHI2-high to avoid mid-cycle value changes.

**Next**: Re-run ArkanoidIIgs.woz and check:
1) `IWM_ASYNC_SCHED` shows scheduling close to the missing `0x9A` byte.
2) CPU READ DATA stream includes `D5 AA AD 9A 96 96 ...` without the gap.
3) `iwm_compare.py --data-fields-by-sector` shows no early track 0 shifts.

### Suspected Areas to Check Next

- **IWM data read handshake**: CPU `READ DATA` timing vs `BYTE_COMPLETE`/`ASYNC_CLEAR` in `rtl/iwm_flux.v`. A premature clear or wrong gating on Q6/Q7 could shift the CPU-visible stream without corrupting the underlying bitstream.
- **Motor/ready gating and spinup**: Confirm `drive_ready`/`motor_active` gating aligns with when the ROM begins sampling `$C0EC`. A mismatch can shift the effective start angle and header index.
- **Side select stability**: Side changes are now debounced, but the ROM may toggle diskreg rapidly. Confirm we only switch sides when the hardware would (step/drive select changes), and that `DISK_READY` does not reset framing mid-read.
- **Sense/status read behavior**: Compare STATUS reads vs MAME (`--status` path) to ensure `STAT35` and sense latching match, especially during seeks and side flips.
- **Event alignment strategy**: Use header signature matching (not raw index) to compare byte streams between MAME and vsim; this avoids false diffs from start-angle drift.

**Update (SEL in Sony command decode)**: Added SEL-masked command decode for 3.5" Sony control lines in `rtl/flux_drive.v`.
The ROM can toggle SEL (diskreg bit7) while issuing commands. Action opcodes should be based on CA1/CA0/CA2 only.
This change preserves SEL for sense selection but ignores it for command execution (direction/step/motor), while still
honoring `ejct_reset`/`eject` when `sony_ctl` is 0x3/0x7.

**Update (STAT35 $04 stepping bit)**: `doc/disk.txt` shows status $04 is “disk is stepping” (0 while stepping, 1 when idle).
Replaced the short “handshake pulse” with a step-busy timer (~12ms at 14MHz) and mapped status $04 to `~step_busy` so
the ROM’s `STAT35`/`BPL` loops see the expected low-while-stepping behavior.

**Next**: Re-run ArkanoidIIgs.woz and confirm whether track stepping and ProDOS load improve with the SEL-masked commands.

**Update (top-level FPGA path)**: Integrated the Verilog WOZ controller directly into `IIgs.sv` so the top-level uses a single WOZ disk (slot S2 / index 2) instead of the legacy `floppy_track` modules. This wires the WOZ bit interface into `iigs`, routes SD index 2 to `woz_floppy_controller`, and drives `DISK_READY[2]` from `woz_ctrl_disk_mounted`. 5.25" drives are currently disabled at top-level. `WOZ_BRAM_LATENCY` is set to 1 for FPGA-style registered BRAM timing.

Verified reaching the "Welcome to the IIgs" screen with progress bar filling, but it does not transition to the next screen.

### Root Cause (SOLVED)

The Verilog path was failing due to **BRAM read latency mismatch**:

- **C++ path**: Provided immediate data response when address changed (no latency)
- **Verilog BRAM**: Had 1-cycle registered read latency

The `flux_drive.v` module expects immediate data when `BRAM_ADDR` changes. The 1-cycle delay caused stale data to be returned during address changes, corrupting the IWM byte decoder.

### The Fix

Changed `rtl/bram.sv` Port B from registered to combinational read:
```verilog
// Port B - Combinational read for simulation (no latency)
// NOTE: Real FPGAs need registered BRAM. This is only for debugging the WOZ path.
output  wire    [width_a-1:0]  q_b,  // Changed from reg to wire

// Combinational read - output changes immediately with address
assign q_b = wren_b ? data_b : mem[address_b];
```

Also fixed `DISK_READY[2]` in `vsim/sim.v` to use `woz_ctrl_disk_mounted` instead of `woz_ctrl_ready` to prevent motor/spinup reset during track loads.

## Key Files Involved

- `rtl/flux_drive.v` - Drive emulation with FLUX/BITSTREAM timing playback
- `rtl/iwm_flux.v` - IWM shift register and byte decoding
- `rtl/iwm_woz.v` - Top-level IWM controller
- `rtl/woz_floppy_controller.sv` - WOZ file parsing and track loading

## Problems Found and Fixed

### 1. Wrong WOZ File Version (FLUX images)
**Symptom**: `WOZ_SCAN: INFO v2 flux_block=0` - no FLUX data
**Root Cause**: The WOZ file in "AppleWorks v3.0 800K (woz-a-day collection)/" has `info_version=2` (no FLUX).
**Fix**: Use the correct file from `wozdisks/AppleWorks v3.0 800K.woz` which has `info_version=3` and FLUX chunk.

### 2. FLUX Mode bit_position Not Advancing
**Symptom**: `M_DATA_CHANGE #0: pos=0` - position always 0 during byte completion
**Root Cause**: In `flux_drive.v`, the bit_position advancement code was only in the BITSTREAM mode branch, not the FLUX mode branch.
**Fix**: Added bit_timer/bit_position advancement to FLUX playback mode (lines 849-865).

### 3. Debug Print Limits (FIXED)
**Symptom**: Appeared that flux transitions stopped at ~100, bytes stopped at ~100
**Root Cause**: Debug print statements had hardcoded limits (`< 100`).
**Fix**: Increased debug limits to see full playback.

### 4. bit_position Drift During Spinup (FIXED)
**Symptom**: Decoder started mid-track at position ~19571, missing D5 AA prologue markers
**Root Cause**: During 170000-bit spinup, `motor_spinning=1` but `drive_ready=0`.
The `bit_position` advanced during spinup, but the IWM flux decoder wasn't active yet.
When drive_ready finally went high, the decoder started at position 19571 instead of 0.
**Fix**: Added bit_position reset when drive_ready rises from 0 to 1 in `flux_drive.v`:
```verilog
// Reset bit_position when drive becomes ready (after spinup completes)
if (drive_ready && !prev_drive_ready && TRACK_BIT_COUNT > 0) begin
    bit_position <= 17'd0;
    bit_timer <= bit_cell_cycles;
    // Also reset flux playback state
    flux_phase_accum <= 32'd0;
    flux_byte_counter <= 8'd0;
    flux_byte_addr <= 16'd0;
    flux_byte_pending <= 1'b1;
    flux_waiting_bram <= 1'b0;
    flux_is_continuation <= 1'b0;
    next_byte_valid <= 1'b0;
end
prev_drive_ready <= drive_ready;
```
**Result**: Decoder now starts at position 0, D5 AA 96 sector headers are detected correctly.

### 5. STEP Command Not Generated (FIXED)

**Symptom**: Boot shows "UNABLE TO LOAD PRODOS" - boot blocks read OK but ProDOS load fails.

**Root Cause**: The 3.5" drive STEP command (sony_ctl=4) was never generated. The head stayed on track 0.

**Why STEP failed**: The `prev_strobe_slot` was tracked per-drive-slot using `prev_strobe_slot[DRIVE_SELECT]`. When
`DRIVE_SELECT` changed, the new slot's previous strobe value was stale (0), causing spurious strobe triggers.
This meant the strobe would fire BEFORE the phases were set up correctly for a STEP command.

**Fix**: Changed to global `prev_lstrb` tracking instead of per-slot:
```verilog
// OLD: Per-slot tracking (caused spurious strobes)
reg [1:0] prev_strobe_slot;
wire sony_cmd_strobe = ... && lstrb && !prev_strobe_slot[DRIVE_SELECT];
prev_strobe_slot[DRIVE_SELECT] <= lstrb;

// NEW: Global tracking (fixed)
reg prev_lstrb;
wire sony_cmd_strobe = ... && lstrb && !prev_lstrb;
prev_lstrb <= lstrb;
```

**Result**: STEP commands (sony_ctl=4) now generate correctly. Tracks advance properly.

### 6. stable_side Not Updating on Track Changes (FIXED)

**Symptom**: ProDOS shows "UNABLE TO LOAD PRODOS" even though tracks advance.

**Root Cause**: `stable_side_35` was only captured when motor started spinning - it never updated when track/side changed. This caused wrong BRAM data to be selected for different sides.

**Fix**: Changed `stable_side_35` from a register to a wire derived from `woz_track3_comb[0]` in `rtl/iwm_woz.v`:
```verilog
// OLD: Latched on motor start (broken)
reg stable_side_35;
always @(posedge CLK_14M or posedge RESET) begin
    if (drive35_motor_spinning && !prev_drive35_motor_spinning) begin
        stable_side_35 <= diskreg_sel;
    end
end

// NEW: Combinational from track_id LSB (fixed)
wire stable_side_35 = woz_track3_comb[0];
```

**Result**: ProDOS now boots successfully.

### 10. stable_side Gating Causes Side Mismatch (FIX APPLIED, NEEDS VERIFY)

**Symptom**: After the GS/OS progress bar completes, the system hangs in a tight loop polling `$C0EC` for disk data. CPU data stream shows long runs of `0xFF` where MAME reads real data. `WOZ_CMP` shows persistent bit_count mismatch:
```
WOZ_CMP MISMATCH: track=1 ... C++ bit_count=74992 Verilog bit_count=75215 stable_side=0
read_iwm ... diskreg_sel=1 ... bit_count=75215
```

**Root Cause**: `stable_side` was being updated only on data reads (Q6=0/Q7=0). During status accesses, `diskreg_sel` can be `1` while `stable_side` remains `0`, so the Verilog path keeps returning side 0 data/bit_count while C++/MAME are on side 1. This produces early stream divergence (long `0xFF` runs) and fails to decode sector data.

**Fix**: Make `stable_side` follow `diskreg_sel` directly so side selection always matches `track_id`. `sim.v` already registers this signal to align with BRAM latency.
```
// iwm_woz.v
assign WOZ_TRACK3_STABLE_SIDE = diskreg_sel;
```

**Next**: Re-run ArkanoidIIgs.woz with latency=1 and confirm the GS/OS boot completes.

### 7. Controller Missing Track Changes During Load (FIXED)

**Symptom**: C++ and Verilog paths returned different BRAM data. WOZ_CMP showed mismatches where Verilog returned data from wrong physical track.

**Root Cause**: The `woz_floppy_controller` only checked for track changes in `S_IDLE` state. While loading a track (in `S_SEEK_LOOKUP` or `S_READ_TRACK`), the drive head could step multiple times. When the load completed, the BRAM had data for the wrong track.

**Evidence from debug logs**:
```
drive35_track CHANGED: 1 -> 2
drive35_track CHANGED: 2 -> 3
...
drive35_track CHANGED: 44 -> 45
WOZ_CTRL: Physical track change: 1 -> 45 (loading both sides)  <-- Missed 43 intermediate tracks!
```

**Fix**: Modified `rtl/woz_floppy_controller.sv` to detect physical track changes at three key points:

1. **After first side load completes**: Check if `track_id[7:1] != target_physical_track` before loading second side
2. **After both sides load complete**: Check for track change before going to `S_IDLE`
3. **After empty track handling**: Check for track change before loading other side

```verilog
// Check if physical track changed during load
if (IS_35_INCH && (track_id[7:1] != target_physical_track)) begin
    // Physical track changed - start fresh load for new track
    target_physical_track <= track_id[7:1];
    pending_track_id <= track_id;
    load_side <= track_id[0];
    state <= S_SEEK_LOOKUP;
    blocks_processed <= 0;
    busy <= 1'b1;
    $display("WOZ_CTRL: Physical track moved during load: %0d -> %0d, reloading",
             target_physical_track, track_id[7:1]);
end
```

**Result**: C++ and Verilog paths now match perfectly: 770K+ BRAM reads with 0 mismatches.

### 8. DISK_READY Going Low During Track Loads (FIXED)

**Symptom**: ProDOS boots but GS/OS fails with Error=#0027 when using Verilog path.

**Root Cause**: `DISK_READY[2]` was using `woz_ctrl_ready` which goes low when the woz_floppy_controller leaves `S_IDLE` state during track loads. This caused motor/spinup state to reset during seeks.

**Fix**: Changed `vsim/sim.v` to use `woz_ctrl_disk_mounted` instead:
```verilog
// DISK_READY[2] indicates disk presence for motor control and flux_drive.
// Track data availability is checked separately via WOZ_TRACK3_BIT_COUNT > 0.
// Using woz_ctrl_disk_mounted (not woz_ctrl_ready) prevents motor/spinup reset
// when the track loader briefly goes non-IDLE during track changes.
assign DISK_READY[2] = woz_ctrl_disk_mounted | DISK_READY_internal[2];
```

**Result**: ProDOS boots successfully, but GS/OS still failed (needed BRAM fix too).

### 9. BRAM 1-Cycle Read Latency Mismatch (FIXED - ROOT CAUSE)

**Symptom**: Verilog WOZ path fails with GS/OS Error=#0027 while C++ path boots successfully.

**Root Cause**: The `bram.sv` module had registered reads with 1-cycle latency, but `flux_drive.v` expects immediate data response when `BRAM_ADDR` changes. The C++ path provided immediate data (no latency), causing a timing mismatch.

**Evidence**: Byte streams diverged at position ~50885 after 225K+ bytes decoded correctly. The 1-cycle stale data during address changes caused the IWM byte decoder to accumulate wrong bits.

**Fix**: Changed `rtl/bram.sv` Port B to combinational read:
```verilog
// OLD: Registered read (1-cycle latency)
output  reg     [width_a-1:0]  q_b,
always @(posedge clock_b) begin
    q_b <= mem[address_b];
end

// NEW: Combinational read (no latency)
output  wire    [width_a-1:0]  q_b,
assign q_b = wren_b ? data_b : mem[address_b];
```

**Note**: This is a simulation-only fix. Real FPGAs need registered BRAM, so `flux_drive.v` would need proper look-ahead logic for FPGA synthesis.

**Result**: Both C++ and Verilog WOZ paths now boot GS/OS successfully.

### Additional Fix (BRAM latency / wrap prefetch)

With `BRAM_LATENCY=1`, the bitstream path can read the wrong byte when `TRACK_BIT_COUNT` is not byte-aligned and the bit position wraps mid-byte. The original look-ahead only handled byte-boundary crossings; it did not prefetch the wrap-to-zero byte when the wrap happens at a non-byte boundary. This caused divergence between latency=0 and latency=1 paths.

**Fix**: Added a wrap-aware prefetch in `rtl/flux_drive.v` so `BRAM_ADDR` switches to byte 0 one cycle early when the next bit will wrap to the start of the track.

```verilog
wire wrap_next_bit = (TRACK_BIT_COUNT > 0) && (effective_bit_position + 1 >= track_bit_count_17);
wire need_wrap_prefetch = wrap_next_bit && about_to_advance && motor_spinning && TRACK_LOADED;
wire need_prefetch = need_lookahead || need_wrap_prefetch;
wire [13:0] prefetch_byte_index = wrap_next_bit ? 14'd0 : next_byte_index;
assign BRAM_ADDR = IS_FLUX_TRACK ? flux_byte_addr[13:0] :
                   (need_prefetch ? prefetch_byte_index : byte_index);
```

## Current Working State

### What Works
1. WOZ v2 BITSTREAM files detected and loaded correctly
2. WOZ v3 FLUX files detected (flux_block found)
3. Track data loads correctly (75215 bits for track 0)
4. Motor starts, drive becomes ready after spinup
5. Flux transitions processed continuously
6. Bytes decode with valid GCR values (D5 AA 96/AD markers visible)
7. bit_position starts at 0 after drive_ready
8. **ProDOS boots successfully**
9. Side selection works correctly with stable_side fix
10. STEP commands (sony_ctl=4) work correctly
11. Tracks advance properly during seeks
12. All Sony commands working: direction (0,1), eject (3), step (4), motor on/off (8,9)
13. **C++ and Verilog BRAM paths match: 770K+ reads, 0 mismatches**
14. Track changes detected during load operations
15. **GS/OS boots successfully** (both C++ and Verilog paths - "Welcome to the IIgs")
16. DISK_READY signal stable during track loads (fixed)
17. BRAM combinational read for simulation (no latency mismatch)
18. **WOZ v3 FLUX tracks decode correctly** - Fixed 125ns timing, TRKS skip optimization (2026-01-30)

### What Doesn't Work
1. Byte stream timing differs from MAME (expected - different decoder implementation)
2. **FPGA synthesis**: Real FPGAs need registered BRAM with 1-cycle latency. The current combinational BRAM is simulation-only. For FPGA, `flux_drive.v` needs proper look-ahead logic to pre-fetch the next BRAM byte.

## Architecture Notes

### Sony 3.5" Command Encoding (flux_drive.v)
```verilog
wire [3:0] sony_ctl = {ca1, ca0, DISKREG_SEL, ca2};
// ca0 = IMMEDIATE_PHASES[0]
// ca1 = IMMEDIATE_PHASES[1]
// ca2 = IMMEDIATE_PHASES[2]
// DISKREG_SEL = $C031 bit 7
```

Command values:
- `0x0`: Direction inward (toward higher tracks)
- `0x1`: Direction outward (toward track 0)
- `0x3`: Eject
- `0x4`: **STEP** (requires PHASES[2:0]=001, DISKREG_SEL=0)
- `0x8`: Motor on
- `0x9`: Motor off
- `0xC`: Disk-change clear

### FLUX Timing Playback (flux_drive.v)
- Each FLUX byte = number of 125ns ticks until next transition
- Phase accumulator: 125ns / 71.43ns = 1.75 clocks per tick at 14MHz
- Code uses 1790/1000 ratio = 1.79 (slight discrepancy)
- `flux_byte_counter` counts down; when 1, emit transition and load next byte
- 0xFF bytes = continuation (no transition, timing extension only)

### IWM Byte Decoding (iwm_flux.v)
- State machine runs at 14MHz
- Window timing for 3.5": base full=28, half=14 (14MHz cycles) with fractional
  +1 cycle applied via fixed-point accumulator (~28.636/14.318 average)
- Shift register accumulates bits based on flux timing within windows
- Byte complete when shift register MSB=1

### Key Signals
- `FLUX_TRANSITION`: From drive, indicates flux edge
- `m_data`: Completed byte in IWM
- `m_rsh`: Shift register accumulating bits
- `bit_position`: Current angular position on track
- `sony_ctl`: 4-bit command to Sony drive
- `sony_cmd_strobe`: Rising edge of PH3 (LSTRB) triggers command

## Debugging Commands

```bash
# Test with WOZ v2 BITSTREAM file
./obj_dir/Vemu --woz ArkanoidIIgs.woz --stop-at-frame 200

# Check C++ vs Verilog BRAM data match
./obj_dir/Vemu --woz ArkanoidIIgs.woz --stop-at-frame 400 2>&1 | grep "WOZ_CMP"

# Check for track changes during load
./obj_dir/Vemu --woz ArkanoidIIgs.woz --stop-at-frame 400 2>&1 | grep "Physical track moved"

# Check track changes (should see physical_track advancing)
./obj_dir/Vemu --woz ArkanoidIIgs.woz --stop-at-frame 400 2>&1 | grep "WOZ3 DATA: Track"

# Compare byte streams with MAME
python3 iwm_compare.py wozdisks/ark_mame.log /tmp/ark_vsim.log --cpu-bytes --limit 150
```

## Next Steps

1. **FPGA synthesis support** - IN PROGRESS
2. Test additional WOZ images
3. Compare byte timing with MAME (optional)

---

## FPGA Look-Ahead Implementation Plan

### Goal
Make `flux_drive.v` work with standard registered BRAM (1-cycle read latency) so it can be synthesized for real FPGAs.

### Approach: State Machine Look-Ahead (Pipeline)

Modify `flux_drive.v` to compute the *next* BRAM address one cycle early. When we need byte N, we already issued the read for it last cycle.

### Why This Approach
- Standard pipelining technique used in FPGA designs
- Works with any synchronous BRAM (no clock tricks)
- No additional clock domains needed
- Natural fit since flux_drive already tracks bit_position

### Implementation Steps

#### Phase 1: Add BRAM Latency Parameter ✓
- [x] Add `parameter BRAM_LATENCY = 0` to `bram.sv`
- [x] When `BRAM_LATENCY=0`: combinational read (current simulation behavior)
- [x] When `BRAM_LATENCY=1`: registered read (FPGA behavior)
- [x] Build and verify simulation still works with `BRAM_LATENCY=0`

#### Phase 2: Capture Regression Baseline ✓
- [x] Run `./obj_dir/Vemu --woz ArkanoidIIgs.woz --stop-at-frame 1500` and capture:
  - BYTE_COMPLETE_ASYNC stream (byte values and positions) - 1,470,066 entries
  - Track load sequence - 678 events
  - Screenshot at frame 800
- [x] Create regression test script (`woz_regression.sh`)

#### Phase 3: Implement Look-Ahead in flux_drive.v
- [ ] Add `next_bram_addr` register (computed one cycle ahead)
- [ ] Add `prefetch_data` register to hold the pre-fetched byte
- [ ] Modify address output: `BRAM_ADDR = next_bram_addr` (one cycle early)
- [ ] On bit_position advance: use `prefetch_data` instead of direct BRAM read
- [ ] Handle edge cases:
  - [ ] Track wrap (bit_position reaches TRACK_BIT_COUNT)
  - [ ] Track/side change (invalidate prefetch, re-sync)
  - [ ] Motor start (initial prefetch)
  - [ ] Drive not ready (don't prefetch)

#### Phase 4: Test with BRAM_LATENCY=1
- [ ] Change `bram.sv` to `BRAM_LATENCY=1` (registered)
- [ ] Run regression tests
- [ ] Compare BYTE_COMPLETE_ASYNC streams (must match exactly)
- [ ] Compare screenshots (must match)
- [ ] Verify boot milestones (frames 200, 400, 800, 1500)

#### Phase 5: Stress Testing
- [ ] Test rapid track seeking
- [ ] Test side switching on double-sided disks
- [ ] Test motor on/off cycles
- [ ] Test multiple WOZ images (3.5" and 5.25")

### Key Signals to Modify in flux_drive.v

```
Current flow:
  bit_position -> BRAM_ADDR = bit_position[16:3]
  BRAM returns data immediately
  flux_drive uses BRAM_DATA

New flow with look-ahead:
  bit_position -> compute next_bit_position (one cycle ahead)
  BRAM_ADDR = next_bit_position[16:3]
  BRAM returns data next cycle -> prefetch_data register
  When bit_position advances, prefetch_data is already valid
```

### Edge Cases to Handle

1. **Track wrap**: When `bit_position >= TRACK_BIT_COUNT`, wrap to 0
   - `next_bit_position` must also wrap correctly

2. **Track change**: When track_id changes
   - Invalidate prefetch_data
   - Wait one cycle for new data before resuming

3. **Motor start / drive_ready rising**:
   - Initialize prefetch pipeline
   - First byte needs special handling (no valid prefetch yet)

4. **Side change on 3.5" disks**:
   - Similar to track change - invalidate and re-sync

### Regression Test Script

```bash
#!/bin/bash
# woz_regression.sh - Run before and after changes

BASELINE_DIR="regression_baseline"
TEST_LOG="regression_test.log"

# Capture baseline (run once with known-good code)
capture_baseline() {
    mkdir -p $BASELINE_DIR
    ./obj_dir/Vemu --woz ArkanoidIIgs.woz --screenshot 800 --stop-at-frame 1500 2>&1 | tee $BASELINE_DIR/full.log
    grep "BYTE_COMPLETE_ASYNC" $BASELINE_DIR/full.log > $BASELINE_DIR/bytes.txt
    grep "WOZ3 DATA: Track" $BASELINE_DIR/full.log > $BASELINE_DIR/tracks.txt
    cp screenshot_frame_0800.png $BASELINE_DIR/
    echo "Baseline captured in $BASELINE_DIR/"
}

# Run regression test
run_test() {
    ./obj_dir/Vemu --woz ArkanoidIIgs.woz --screenshot 800 --stop-at-frame 1500 2>&1 | tee $TEST_LOG

    # Compare bytes
    grep "BYTE_COMPLETE_ASYNC" $TEST_LOG > test_bytes.txt
    if diff -q $BASELINE_DIR/bytes.txt test_bytes.txt > /dev/null; then
        echo "PASS: Byte stream matches"
    else
        echo "FAIL: Byte stream differs"
        diff $BASELINE_DIR/bytes.txt test_bytes.txt | head -20
        return 1
    fi

    # Compare screenshot (binary diff for now)
    if cmp -s $BASELINE_DIR/screenshot_frame_0800.png screenshot_frame_0800.png; then
        echo "PASS: Screenshot matches"
    else
        echo "WARN: Screenshot differs (may need visual inspection)"
    fi

    echo "Regression test complete"
}

case "$1" in
    baseline) capture_baseline ;;
    test) run_test ;;
    *) echo "Usage: $0 {baseline|test}" ;;
esac
```

### Progress Tracking

| Step | Status | Notes |
|------|--------|-------|
| Phase 1: BRAM_LATENCY param | **DONE** | Added to bram.sv, woz_floppy_controller.sv, iwm_woz.v, iigs.sv, sim.v |
| Phase 2: Regression baseline | **DONE** | 1.47M bytes, 678 track events, screenshot captured |
| Phase 3: Look-ahead impl | **DONE** | Implemented in flux_drive.v with byte boundary look-ahead |
| Phase 4: Test with latency | **BLOCKED** | 311-bit position drift issue discovered via VCD analysis |
| Phase 5: Stress testing | Not started | Waiting for Phase 4 resolution |

### BRAM_LATENCY=1 Position Drift Issue (2026-01-19)

**Symptom**: With BRAM_LATENCY=1, GS/OS fails with "Unable to load START.GS.OS file. Error=#0027" despite sector detection working correctly.

**VCD Analysis Results**:
Captured VCD waveforms at frames 460-463 for both BRAM_LATENCY=0 and BRAM_LATENCY=1:

```
At timestamp #110454741:
- BRAM_LATENCY=0: bit_position = 57159, BRAM_ADDR = 0x1BE8
- BRAM_LATENCY=1: bit_position = 56848, BRAM_ADDR = 0x1BC2
- Difference: 311 bits (38 bytes)
```

**Root Cause Analysis**:

The 311-bit drift accumulates because position resets pause the disk rotation:

1. When `TRACK_LOAD_COMPLETE` or `drive_ready_rising` fires:
   - `bit_position <= 0` (non-blocking, takes effect at end of cycle)
   - `BRAM_ADDR = 0` (combinational, immediate)
   - With BRAM_LATENCY=1, valid data for addr=0 arrives NEXT cycle

2. The `bram_first_read_pending` mechanism waits one cycle for valid BRAM data
   - During this wait, `bit_position` doesn't advance
   - The simulated disk "pauses" while real hardware would continue rotating

3. Over many position resets (motor restarts, track changes), the pauses accumulate
   - ~7 BRAM wait events in 400 frames
   - Each wait loses timing equivalent to ~44 bits
   - Total drift: 311 bits by frame 460

**Attempted Fixes**:
1. Let timer run during BRAM wait (position advances, skip flux check) - still drifts
2. Reset bit_timer in BRAM wait to trigger flux check next cycle - timer decrement overwrites
3. Add !bram_first_read_pending to timer conditions - pauses position, causes drift

**Core Problem**:
The BRAM address changes combinationally with bit_position. With 1-cycle BRAM latency, we need the address presented ONE CYCLE BEFORE the data is needed. For byte boundary crossings, the look-ahead logic handles this. For position resets, we can't predict when TRACK_LOAD_COMPLETE will fire.

**Potential Solutions** (not yet implemented):
1. **Pipeline the position reset**: Delay the actual position reset by one cycle so BRAM data is ready
2. **Accept small drift**: Skip flux check on first bit after reset but keep position advancing
3. **Dual-port BRAM timing**: Use port A for speculative reads, port B for actual data
4. **Prefetch on track load**: When TRACK_LOAD_COMPLETE fires, data at addr=0 is already in pipeline

---

## False Positives / Incorrect Hypotheses (DO NOT RE-INVESTIGATE)

This section documents investigated hypotheses that turned out to be WRONG or MISLEADING. These are documented to prevent wasting time re-investigating the same dead ends.

### 1. FALSE: "D5 AA AD at bit position 1066 is a real data prologue"

**What we thought**: The D5 AA AD sequence detected at bit position ~1066 was a real sector data prologue that was being corrupted or misread.

**Reality**: This is a FALSE POSITIVE. The bit pattern `F5 6A AB 69...` in the self-sync area happens to decode as `D5 AA AD A6` when byte boundaries align at that position. The fourth byte is `0xA6`, NOT `0x9A` as expected for real sector data.

**Evidence**:
- Python analysis of raw WOZ track 0 found only 3 real D5 AA AD prologues at bits 19528, 31664, 43800
- The byte after the "false" D5 AA AD is 0xA6 (not 0x9A)
- The system continues past this false positive and finds real prologues later

**Why it doesn't matter**: The ROM/GS/OS correctly rejects this false prologue (checksum fails) and continues searching for real sectors.

### 2. FALSE: "MAME async mode protection prevents byte overwrite"

**What we thought**: MAME prevents new bytes from overwriting unread bytes in m_data. We implemented this: `if (!is_async || !m_data[7] || m_data_read || rd_consumes_byte) begin m_data <= shifted_rsh; end`

**Reality**: This fix was TOO AGGRESSIVE and broke sector framing by dropping D5, AA, and AD bytes:
```
IWM_9A_DROP(E1): byte=ad DROPPED pos=7157 async=1 m_data=fe m_data_read=0 (unread byte blocking)
```

**Why it failed**: When an old byte (like FE) was blocking, the D5/AA/AD prologue bytes were DROPPED. The CPU byte stream became `..., FE, 9A, 96, ...` instead of `..., FE, D5, AA, AD, 9A, 96, ...`.

**Status**: REVERTED. Bytes always overwrite m_data unconditionally.

### 3. FALSE: "vsim reads 2x more bytes than MAME"

**What we thought**: vsim was reading twice as many bytes as MAME, indicating inefficiency or retries.

**Reality**: When properly filtered (non-zero, non-ff, active=1), the difference is only 13%:
- MAME: 730,997 data bytes
- vsim: 824,941 data bytes
- Ratio: 1.13x (NOT 2x)

**Why the confusion**: Earlier comparisons included inactive/placeholder bytes and unfiltered reads, inflating the apparent difference.

### 4. FALSE: "229µs async timeout causes byte loss after DE AA"

**What we thought**: The 229µs gap between reading the header epilogue (DE AA) and the next data read caused async timeout, clearing m_data and losing bytes.

**Reality**: The data IS being read correctly:
- pos=7109: f9 byte read (sync)
- pos=7161: ad byte read (data prologue)
- pos=7167: 9a byte read (first data byte after D5 AA AD)

**Why it appeared wrong**: The comparison scripts filtered out `active=0` reads. The bytes were there, but motor command (iwm_active) being off made them appear "missing" in comparisons.

### 5. FALSE: "Latch-mode hold should extend byte availability"

**What we thought**: Setting latch mode to prevent new bytes from overwriting unread bytes would fix the "missing 0x9A" issue.

**Reality**: This caused regression - fewer data markers were detected and boot failed.

**Status**: REVERTED. Restored unconditional overwrite on byte completion.

### 6. FALSE: "3.5" flux pulse offset of 6 cycles fixes timing"

**What we thought**: Shifting 3.5" bitstream flux pulses earlier by 6 cycles would avoid window-edge misses.

**Reality**: Tried offsets 0, 1, 2, 6 - none fixed the actual issue. The missing first data byte problem persists regardless of offset.

**Current value**: flux_pulse_offset = 0

### 7. FALSE: "Fractional bit cell timing fixes early track 0 mismatches"

**What we thought**: Using 28.636 cycles (2.000µs) instead of 28 cycles (1.955µs) would give the CPU more time to catch the first data bytes.

**Reality**: Neither IWM window fractional timing nor flux_drive bit cell fractional timing resolved the early track-0 mismatches.

### 8. FALSE: "Forced IWM I/O fast mode improves timing"

**What we thought**: Forcing IWM I/O ($C0E0-$C0EF) to run in fast mode would improve read timing.

**Reality**: No improvement. REVERTED.

### 9. FALSE: "scaled bit-cell timing improves rotation"

**What we thought**: Using scaled bit-cell timing for more accurate rotation period would help.

**Reality**: Caused OS hang regression. REVERTED - keeping constant 2µs-ish cells (28/29 cycles) for 3.5" bitstream.

### 10. MISLEADING: "Byte stream divergence at position ~50885 is the root cause"

**What we thought**: C++ and Verilog paths diverging at position 50885 indicated a specific bug at that location.

**Reality**: The divergence was caused by accumulated BRAM latency mismatch, not a bug at that specific position. Fixing BRAM to use combinational reads eliminated all 770K+ mismatches.

---

## Test Results History

| Date | Test | Result |
|------|------|--------|
| 2026-01-30 | WOZ v3 FLUX tracks | **WORKING** - addr_ok=53, data_complete=53, all regression tests pass |
| 2026-01-26 | ArkanoidIIgs.woz track stepping | **BLOCKED** - ROM never issues WriteBit for STEP (sony_cmd=4), disk stays on track 0 |
| 2026-01-26 | ArkanoidIIgs.woz 300 frames | Progress bar fills but hangs - confirmed never steps off track 0 |
| 2026-01-19 | ArkanoidIIgs.woz Verilog path frame 800 | **GS/OS boots successfully** ("Welcome to IIgs") |
| 2026-01-19 | ArkanoidIIgs.woz Verilog path frame 1500 | **GS/OS boots successfully** (progress bar advancing) |
| 2026-01-19 | BRAM mismatch check | **0 mismatches** |
| Previous | ArkanoidIIgs.woz C++ path | GS/OS boots successfully (Welcome to IIgs progress bar) |
| Previous | ArkanoidIIgs.woz Verilog path (before BRAM fix) | ProDOS boots, GS/OS Error=#0027 - diverges at pos 50885 |
| Previous | ArkanoidIIgs.woz frame 315 | C++ and Verilog BRAM mismatch - Verilog had wrong track data |
| Previous | ArkanoidIIgs.woz frame 600 | "UNABLE TO LOAD PRODOS" - stable_side not updating |
| Previous | ArkanoidIIgs.woz frame 400 | "UNABLE TO LOAD PRODOS" - STEP commands now work (fixed) |
| Earlier | AppleWorks FLUX | Decoded only sectors 5/8/11 on track 0 |
