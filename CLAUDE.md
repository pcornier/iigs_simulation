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

# use a disk image
./Vemu --disk totalreplay.hdv  
./Vemu --disk pd.hdv --screenshot 50 --stop-at-frame 100


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

### Debug Output Analysis
The simulation produces extensive debug output including:
- CPU instruction traces with addresses and opcodes
- Video timing and pixel buffer operations
- Memory access patterns and bank switching
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
