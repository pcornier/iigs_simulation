# WOZ Verilog Controller Debugging Status

## Overview

This document captures the current state of debugging the Verilog WOZ floppy controller for Apple IIgs simulation. The goal is to make the Verilog path produce identical results to the working C++ path so it can be synthesized for FPGA.

## Current Status (2026-01-16)

| Path | BRAM Type | Boot Result |
|------|-----------|-------------|
| C++ (BeforeEval DPI) | Registered | **WORKS** - "Welcome to the IIgs" by frame ~600 |
| Verilog (woz_floppy_controller) | Registered | **WORKS** - "Welcome to the IIgs" by frame ~600 |

**SUCCESS! The Verilog path now boots identically to the C++ path!**

## Root Cause Identified

**The single-track-per-side BRAM cache in woz_floppy_controller causes `bit_count` mismatch.**

### The Problem

1. woz_floppy_controller has ONE 16KB BRAM per side (side0 and side1)
2. When seeking, only the last loaded track's data is in BRAM
3. `bit_count_side0` and `bit_count_side1` reflect the LAST loaded track, not the requested track
4. When ROM seeks from track 45 back to track 7:
   - BRAM still has track 45's data (75215 bits)
   - ROM requests track 7 (75688 bits)
   - Old code returned bit_count=75215 (track 45's value) for track 7
   - flux_drive used wrong bit_count for position wrapping → read wrong data
   - ROM got different bytes than C++ path → different execution → boot failure

### Evidence

Track change comparison showed both paths start identical for first 97 track changes, then diverge:
- **C++ (change 98)**: track 7 → 8 (continuing upward)
- **Verilog (change 98)**: track 7 → 6 (going back down)

This happened because at track 7, the Verilog path read wrong data due to bit_count mismatch.

### Fix Attempt #1 (Failed - caused ROM timeout)

Changed `woz_floppy_controller.sv` to return `bit_count=0` when cached track doesn't match requested track. This caused ROM timeout during seeks because `bit_count=0` means no flux transitions.

### Fix Attempt #2 (SUCCESS!)

Return a reasonable bit_count during track loading instead of 0:

```verilog
wire track_side0_match = (current_track_id_side0 == track_id);
wire track_side1_match = (current_track_id_side1 == track_id);
wire selected_track_match = (IS_35_INCH && track_id[0]) ? track_side1_match : track_side0_match;
wire [31:0] selected_bit_count = (IS_35_INCH && track_id[0]) ? bit_count_side1 : bit_count_side0;
wire is_loading = (state == S_SEEK_LOOKUP) || (state == S_READ_TRACK);
wire [31:0] loading_bit_count = (trk_bit_count > 0) ? trk_bit_count : selected_bit_count;
assign bit_count = woz_valid ? (selected_track_match ? selected_bit_count :
                                (is_loading ? loading_bit_count : selected_bit_count)) : 32'd0;
```

This approach:
1. Returns correct `bit_count` when track IS cached and matches
2. Returns the pending track's `bit_count` (trk_bit_count) during loading
3. Falls back to cached side's `bit_count` for rapid SEL toggles (status reads)

The key insight: the ROM needs to see SOME flux transitions during seeks to avoid timeout. Even garbage data with a reasonable bit_count is better than no flux at all.

## Test Configuration

- **Disk Image**: `ArkanoidIIgs.woz` (3.5" double-sided WOZ 2.0 format)
- **Test Command**: `./obj_dir/Vemu --woz ArkanoidIIgs.woz --screenshot 500 --stop-at-frame 500`
- **Note**: Do NOT use `System3.2.woz` - it is broken

## Key Files

### Verilog Path
- `rtl/woz_floppy_controller.sv` - Loads WOZ image into BRAM, provides bit data
- `rtl/flux_drive.v` - Reads bit stream from BRAM, generates flux transitions
- `rtl/bram.sv` - Dual-port BRAM with 1-cycle read latency

### C++ Path
- `vsim/sim/sim_blkdevice.cpp` - C++ WOZ parser, provides bit data via DPI
- `vsim/sim.v` - Contains `USE_CPP_WOZ` define to switch between paths

### Path Selection
In `vsim/sim.v` around line 190:
```verilog
`define USE_CPP_WOZ  // Enable C++ path (comment out for Verilog path)
```

## What We've Learned

### 1. BRAM Latency is NOT the Root Cause
- Initially suspected BRAM's 1-cycle read latency caused mismatch
- Made BRAM Port B combinational for simulation - Verilog path still failed
- C++ path works fine with registered BRAM
- **Conclusion**: The issue is elsewhere in the Verilog data path

### 2. C++ BeforeEval Timing
- `BeforeEval()` runs BEFORE `top->eval()` in Verilator
- This means C++ reads address from PREVIOUS tick, providing inherent 1-cycle latency
- This naturally matches BRAM behavior - no extra delay needed in C++

### 3. bit_count Timing
- Changed `bit_count` output from registered to combinational in woz_floppy_controller
- This ensures track length is available immediately when track changes
- Located in `rtl/woz_floppy_controller.sv`

### 4. Data Comparison Debug Code
In `vsim/sim.v` there's debug code that logs first 100 address changes:
```verilog
// Debug: log data flow when address changes and data is loaded
reg [31:0] flux_data_log_count = 0;
reg [13:0] flux_data_last_addr = 0;
always @(posedge CLK_14M) begin
    if (flux_data_log_count < 100 && woz3_bit_count > 0 && WOZ_TRACK3_BIT_ADDR != flux_data_last_addr) begin
        flux_data_last_addr <= WOZ_TRACK3_BIT_ADDR;
        $display("FLUX_DATA: addr=%04X cpp=%02X verilog=%02X MATCH=%0d",
                 WOZ_TRACK3_BIT_ADDR, woz3_bit_data, woz_ctrl_bit_data,
                 (woz3_bit_data == woz_ctrl_bit_data) ? 1 : 0);
        flux_data_log_count <= flux_data_log_count + 1;
    end
end
```

Previous runs showed Verilog data was 1 byte behind C++ data, but fixing BRAM latency alone didn't resolve the boot failure.

## Next Steps to Investigate

1. **Compare actual byte sequences**: Enable debug logging and compare what bytes each path produces over time

2. **Check flux_drive look-ahead timing**: The look-ahead logic in `flux_drive.v` pre-fetches the next byte when `timer=2,1`. Verify this aligns correctly with BRAM latency.

3. **Verify track loading**: Ensure woz_floppy_controller loads both sides correctly (track_id[0] selects side for 3.5" disks)

4. **Check bit position wraparound**: When bit_position reaches bit_count, it should wrap to 0

## Architecture Notes

### WOZ 2.0 Format (3.5" disk)
- 160 quarter-tracks (80 tracks × 2 sides)
- TMAP chunk maps quarter-track to TRKS index
- Each track has variable bit count (~75000 bits for 3.5")
- Bit timing: 2000ns for 3.5" disks

### flux_drive Look-Ahead
```
timer=7: Normal bit output
timer=2: Set next_byte_addr = current_byte_addr + 1
timer=1: BRAM fetches next byte (registered read)
timer=0: byte_reg loaded from bram_data, byte crossing occurs
```

### Signal Flow
```
WOZ_TRACK3 (track number) → woz_floppy_controller → BRAM address
WOZ_TRACK3_BIT_ADDR (bit position) → woz_floppy_controller → BRAM address
BRAM q_b → woz_ctrl_bit_data → flux_drive → IWM shift register
```

## Commits

The current working state has:
- C++ path boots successfully with ArkanoidIIgs.woz
- Standard registered BRAM behavior restored
- Debug logging code in place for comparison
- `bit_count` made combinational in woz_floppy_controller

## How to Resume

1. Build: `cd vsim && make`
2. Test C++ path: `./obj_dir/Vemu --woz ArkanoidIIgs.woz --screenshot 500 --stop-at-frame 500`
3. To test Verilog path: Comment out `USE_CPP_WOZ` in `vsim/sim.v` line 190, rebuild
4. Compare outputs using FLUX_DATA debug messages
