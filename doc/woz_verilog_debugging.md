# WOZ Verilog Controller Debugging Status

## Overview

This document captures the current state of debugging the Verilog WOZ floppy controller for Apple IIgs simulation. The goal is to make the Verilog path produce identical results to the working C++ path so it can be synthesized for FPGA.

## Current Status

| Path | BRAM Type | Boot Result |
|------|-----------|-------------|
| C++ (BeforeEval DPI) | Registered | **WORKS** - "Welcome to the IIgs" |
| Verilog (woz_floppy_controller) | Registered | **FAILS** - "Error loading GS.OS file. Error=#0027" |
| Verilog (woz_floppy_controller) | Combinational | **STILL FAILS** - same error |

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
