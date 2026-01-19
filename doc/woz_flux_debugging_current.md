# WOZ FLUX Chunk Debugging Session

## Current Status

Testing WOZ disk images with the Apple IIgs simulator. WOZ v2 BITSTREAM format (ArkanoidIIgs.woz) now boots GS/OS successfully.

**Status: FIXED - BOTH C++ and Verilog paths boot GS/OS successfully!**

Verified working at frames 800 and 1500 with "Welcome to the IIgs" progress screen.

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
| Phase 1: BRAM_LATENCY param | **DONE** | Added to bram.sv, woz_floppy_controller.sv, sim.v |
| Phase 2: Regression baseline | **DONE** | 1.47M bytes, 678 track events, screenshot captured |
| Phase 3: Look-ahead impl | In Progress | |
| Phase 4: Test with latency | Not started | |
| Phase 5: Stress testing | Not started | |

## Test Results History

| Date | Test | Result |
|------|------|--------|
| 2026-01-19 | ArkanoidIIgs.woz Verilog path frame 800 | **GS/OS boots successfully** ("Welcome to IIgs") |
| 2026-01-19 | ArkanoidIIgs.woz Verilog path frame 1500 | **GS/OS boots successfully** (progress bar advancing) |
| 2026-01-19 | BRAM mismatch check | **0 mismatches** |
| Previous | ArkanoidIIgs.woz C++ path | GS/OS boots successfully (Welcome to IIgs progress bar) |
| Previous | ArkanoidIIgs.woz Verilog path (before BRAM fix) | ProDOS boots, GS/OS Error=#0027 - diverges at pos 50885 |
| Previous | ArkanoidIIgs.woz frame 315 | C++ and Verilog BRAM mismatch - Verilog had wrong track data |
| Previous | ArkanoidIIgs.woz frame 600 | "UNABLE TO LOAD PRODOS" - stable_side not updating |
| Previous | ArkanoidIIgs.woz frame 400 | "UNABLE TO LOAD PRODOS" - STEP commands now work (fixed) |
| Earlier | AppleWorks FLUX | Decoded only sectors 5/8/11 on track 0 |
