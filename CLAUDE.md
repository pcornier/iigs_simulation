# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an Apple IIgs hardware simulation written in Verilog using the Verilator simulator. The project implements a cycle-accurate emulation of the Apple IIgs computer system, including the 65C816 CPU, video graphics controller (VGC), sound system (ES5503), and various peripherals.

## Essential Build Commands

**Always run from the `vsim/` directory due to relative file paths:**

```bash
cd vsim/
make                    # Build the simulation with ROM3 (default)
make ROM=rom1          # Build with ROM1 instead
make SOUND=stub        # Build with stubbed sound system
make clean             # Clean build artifacts
```

**Running the simulation:**
```bash
# Basic windowed simulation
./obj_dir/Vemu

# Show help and available options
./obj_dir/Vemu -h
./obj_dir/Vemu --help

# Take screenshot at frame 245
./obj_dir/Vemu --screenshot 245
./obj_dir/Vemu -screenshot 245   # Legacy format (deprecated)

# Take screenshots at multiple frames
./obj_dir/Vemu --screenshot 100,200,300

# Stop simulation after frame 1000
./obj_dir/Vemu --stop-at-frame 1000

# Take screenshot and stop at same frame
./obj_dir/Vemu --screenshot 245 --stop-at-frame 245

# Run with selftest mode
./obj_dir/Vemu --selftest

# With debug output to file
./obj_dir/Vemu > debug.log 2>&1

# VCD waveform capture (for signal-level debugging)
# IMPORTANT: VCD files grow very fast. Only capture 2-3 frames maximum.
# Use --stop-at-frame no more than 3 frames after the dump start frame.
./obj_dir/Vemu --dump-vcd-after 400 --stop-at-frame 403  # Capture frames 400-403 to vsim.vcd

# use a disk image (HDD slot 7)
./Vemu --disk totalreplay.hdv
./Vemu --disk pd.hdv --screenshot 50 --stop-at-frame 100

# use floppy disk images
./Vemu --floppy game.nib                # 5.25" floppy (NIB format, 140K)
./Vemu --floppy35 Pirates.po            # 3.5" floppy (PO/2MG format, 800K)
./Vemu --floppy35 "Bards Tale.2mg"      # 3.5" floppy with 2MG header
./Vemu --woz ArkanoidIIgs.woz           # WOZ format flux-level disk image
```

### Disk Image Options

| Option | Description | Formats |
|--------|-------------|---------|
| `--disk <file>` | HDD slot 7 unit 0 | HDV, PO, 2MG |
| `--disk2 <file>` | HDD slot 7 unit 1 | HDV, PO, 2MG |
| `--floppy <file>` | 5.25" floppy drive 1 | NIB (140K) |
| `--floppy35 <file>` | 3.5" floppy drive 1 | PO, 2MG (800K) |
| `--woz <file>` | WOZ flux-level disk image | WOZ 1.x/2.x (3.5"/5.25") |

**Note:** 3.5" floppy images (PO/2MG) are automatically converted to nibblized format at load time.
**Note:** WOZ format provides flux-level accuracy but boot support is work-in-progress (see `doc/woz_floppy_debugging.md`).

### Keyboard Input (--send-keys)
Send keyboard input at specific frames for automated testing:
```bash
# Basic key injection at frame 100
./obj_dir/Vemu --send-keys 100:hello

# Special escape sequences:
#   \n  = Enter/Return
#   \t  = Tab
#   \e  = Escape (ESC key)
#   \\  = Literal backslash
#   \xNN = Hex code (e.g., \x1b for ESC, \x08 for backspace)

# Examples:
./obj_dir/Vemu --send-keys 100:b\n          # Type 'b' then press Enter
./obj_dir/Vemu --send-keys 100:\e           # Press Escape key
./obj_dir/Vemu --send-keys 100:test\nyes\n  # Type 'test', Enter, 'yes', Enter

# Multiple key sequences at different frames
./obj_dir/Vemu --send-keys 100:a --send-keys 200:b\n
```

### Mouse Input (--send-mouse)
Send mouse movements and clicks at specific frames:
```bash
# Format: --send-mouse <frame>:<dx>,<dy>[,<btn>[,<dur>]]
#   dx, dy  = Movement deltas (-127 to 127)
#   btn     = Button state: 0=none, 1=left click (optional, default 0)
#   dur     = Duration in frames to hold (optional, default 1)

# Move mouse right 50 pixels at frame 100
./obj_dir/Vemu --send-mouse 100:50,0

# Move mouse down 30 pixels with left button held
./obj_dir/Vemu --send-mouse 100:0,30,1

# Click and hold for 5 frames
./obj_dir/Vemu --send-mouse 100:0,0,1,5

# Multiple mouse actions
./obj_dir/Vemu --send-mouse 100:100,0 --send-mouse 150:0,0,1,5
```

## Core Architecture

### System Integration (rtl/iigs.sv)
- **Top-level module** integrating all subsystems
- **Memory controller** handling fast RAM (banks 00-3F) and slow RAM (banks E0-E1)
- **I/O space mapping** ($C000-$CFFF) including video mode switches
- **Clock domains**: 14MHz master clock, pixel clock for video
- **Key signals**: AN3 (graphics mode control), NEWVIDEO[7:0], video mode switches

### Video Graphics Controller (rtl/vgc.v)
- **Dual-mode architecture**: SHRG (Super Hi-Res Graphics) vs Apple II compatibility modes
- **Apple II video modes**: Text 40/80, Lores 40/80, Hires 40/80, mixed modes
- **Memory addressing**: Uses Sather algorithm (lineaddr function) for authentic Apple II memory layout
- **Pixel buffer system**: Decouples memory fetch timing from pixel output timing
- **Key functions**:
  - `lineaddr(y)`: Calculates Apple II video memory addresses
  - `expandHires40()`: Converts hires bytes to pixel streams with color artifacting
  - `expandLores40()`: Handles lores pixel expansion
- **Line type detection**: Based on GR, HIRES_MODE, EIGHTYCOL, AN3 signals

### CPU (rtl/65C816/)
- **65C816 processor** with full 16-bit capabilities
- **Memory management**: 24-bit addressing with bank switching
- **Microcode-based execution** (mcode.sv)
- **ALU operations** including BCD arithmetic support

### Memory Architecture
- **Banked memory system** matching real Apple IIgs:
  - Banks 00-01: Fast RAM on motherboard (128K)
  - Banks 02-3F: Extended fast RAM (up to 4MB)
  - Banks E0-E1: Slow RAM for video and system (128K)
  - Banks FE-FF: ROM
- **Shadow registers** controlling memory mapping
- **Auxiliary memory** support for 80-column text modes

### Audio System (rtl/es5503.v, rtl/sound.v)
- **Ensoniq ES5503** digital oscillator chip emulation
- **32 oscillators** with various synthesis modes
- **Sound GLU** for interrupt and timing management

## Key Development Concepts

### Video Mode Detection
```verilog
wire GR = ~(TEXTG | (window_y_w[5] & window_y_w[7] & MIXG));
// Line type determines rendering method:
// 0=TEXT40, 1=TEXT80, 4=LORES40, 5=LORES80, 6=HIRES40, 7=HIRES80
```

### Apple II Address Generation
The `lineaddr()` function implements the authentic Apple II memory layout where screen lines are not stored consecutively but follow the Apple II's unique addressing pattern.

### Pixel Pipeline
1. **Memory fetch**: Video address calculation and data retrieval
2. **Pixel expansion**: Convert memory data to pixel streams
3. **Color processing**: Apply Apple II color artifacting rules
4. **Output timing**: Coordinate with horizontal/vertical timing

### AN3 Signal Usage
- **Standard Apple II modes** (40-column): AN3 not required
- **Double-resolution modes** (80-column): Requires AN3=0 for IIgs modes
- **Control registers**: $C05E (CLRAN3), $C05F (SETAN3)

## Testing and Debugging

### Regression testing

- After each change run the regression.sh script in the vsim directory. If there are any changes stop and notify the user. Changes will be reported by diff of a binary png. You can optionaly analyze the images and see what the differences are.

### Debug Output Control

Debug output is controlled via compile-time macros and runtime flags to balance verbosity vs performance.

**Compile-time debug macros** (edit source files to enable by uncommenting the `define):

| File | Macro | Description |
|------|-------|-------------|
| rtl/adb.v | DEBUG_ADB | ADB keyboard/mouse state tracking |
| rtl/iigs.sv | DEBUG_BANK | Bank/memory access debugging |
| rtl/iigs.sv | DEBUG_RESET | Reset sequence and register init |
| rtl/iigs.sv | DEBUG_IO | Soft switch accesses (C000-C0FF) |
| rtl/iigs.sv | DEBUG_IRQ | Interrupt handling and VBL |
| rtl/scc8530.v | DEBUG_SCC | Serial Communications Controller |
| rtl/clock_divider.v | DEBUG_CLKDIV | Clock speed transitions |
| vsim/sim.v | DEBUG_SIM | Top-level simulation events |

```verilog
// Example: In rtl/iigs.sv, uncomment line 5 to enable reset debugging:
`define DEBUG_RESET
```

**Runtime debug options:**
```bash
# Enable CSV memory trace logging (creates vsim_trace.csv)
# WARNING: This is ~51% slower and creates large files (~210MB per 100 frames)
./obj_dir/Vemu --enable-csv-trace

# Start CSV tracing only after a specific frame (reduces file size)
./obj_dir/Vemu --dump-csv-after 500

# Disable CPU instruction logging to save memory (stdout still works)
./obj_dir/Vemu --no-cpu-log
```

**Performance impact of debug options:**

| Configuration | Relative Speed | Notes |
|--------------|----------------|-------|
| Default (no macros) | 100% | ~350 lines/5 frames, ~10s/100 frames |
| With CSV trace | ~49% | Large vsim_trace.csv created |
| DEBUG_CLKDIV enabled | ~85% | Clock speed transition logging |
| DEBUG_ADB enabled | ~20% | Very verbose ADB state output |
| DEBUG_BANK enabled | ~25% | Verbose memory/bank tracing |
| All debug macros | ~10% | Full debug output (~292K lines/5 frames) |

### Debug Output Analysis
The simulation produces debug output including:
- CPU instruction traces with addresses and opcodes (always enabled to stdout)
- Video timing and pixel buffer operations
- Memory access patterns and bank switching (requires DEBUG_BANK)
- ADB keyboard/mouse state changes (requires DEBUG_ADB)
- Graphics mode transitions and pixel data

### Common Debug Patterns
```bash
# Look for video mode detection issues
grep "line_type" debug.log

# Check pixel buffer operations
grep -E "(HIRES RELOAD|PIXEL SHIFT)" debug.log

# Monitor graphics mode switches
grep "**CLRAN3\|**SETAN3" debug.log
```

### Screenshots and Frame Analysis
Use `--screenshot N` to capture specific frame states for visual debugging of graphics issues. The simulator supports:
- Single frame screenshots: `--screenshot 245`
- Multiple frame screenshots: `--screenshot 100,200,300`
- Stopping at specific frames: `--stop-at-frame 1000`
- Combined screenshot and stop: `--screenshot 245 --stop-at-frame 245`

## Reference Materials

- **IIgsRomSource/**: Original source code with comments of the IIgs ROM
- **doc/**: Official Apple IIgs documentation and technical references
- **ref/**: Reference implementation for comparison
- **software_emulators/**: C-based emulators for algorithm reference
- **notes.txt**: Memory layout and addressing documentation

## Video Mode Priority Order
When fixing video modes, work in this priority order:
1. Text40/80 (basic text display)
2. Lores40/80 (low-resolution graphics)
3. Hires40/80 (high-resolution graphics)
4. Mixed modes (text + graphics)
