# VGC Investigation Findings - Task Force Game

## Issue Summary

When running Task Force, the following issues are observed compared to Clemens/KEGS reference emulators:

1. **Black background instead of gray** - The background appears black in our simulator but gray in reference emulators
2. **Colored glitch bars** - Horizontal yellow/green/red stripes appear near the bottom of the screen where clean text should be

## Hardware Architecture (from Apple IIgs documentation)

### VGC Video Memory

- The VGC **always** reads from slow RAM (banks $E0/$E1)
- SHR graphics buffer: $E1:2000-$E1:9CFF (pixel data)
- SCB (Scan Control Bytes): $E1:9D00-$E1:9DC7 (200 bytes, one per scanline)
- Color palettes: $E1:9E00-$E1:9FFF (16 palettes × 16 colors × 2 bytes = 512 bytes)

### Shadow Register ($C035)

Controls whether CPU writes to banks $00/$01 are mirrored to banks $E0/$E1:

| Bit | Function |
|-----|----------|
| 3 | SHR shadow inhibit: 0=enabled (writes mirrored), 1=disabled (no mirroring) |

**Default on reset**: All bits cleared = all shadowing enabled

### Memory Write Flow

```
CPU writes to $01:9E00 (palette)
        │
        ▼
   Shadow bit 3 = 0?
        │
    ┌───┴───┐
   YES      NO
    │        │
    ▼        ▼
Write to   Write to
$01:9E00   $01:9E00
   AND        ONLY
$E1:9E00
    │        │
    ▼        ▼
VGC sees   VGC reads
new data   old/uninit data
```

## Task Force Specific Behavior

### Clemens Trace Analysis

1. **Shadow register value**: 0x08 (bit 3 = 1) → SHR shadow **DISABLED**
2. **Palette writes**: Game writes to bank $00:9E00 with value 0x00 (black)
3. **Result**: Writes do NOT reach $E1:9E00 where VGC reads from

### Raster Effects

The game performs per-scanline color changes:
```
Loop:
  LDA $E1C02E    ; Read VERTCNT (vertical counter)
  AND #$7F
  TAX
  LDA $2D29,X    ; Load color from table
  STA $E1C022    ; Write to TEXTCOL register
  CPX #$60
  BNE Loop
```

This writes to TEXTCOL ($C022) which controls text foreground/background colors in Apple II modes, but should NOT affect SHR graphics mode.

## Issue #1: Black vs Gray Background

### Root Cause

- Shadow bit 3 = 1 (disabled) means palette writes to bank $00 don't reach bank $E1
- VGC reads from $E1:9E00 which contains uninitialized data
- Our slow RAM initializes to 0x00 = black
- Other emulators may initialize differently or ROM may pre-initialize palette

### Possible Solutions

1. **Initialize slow RAM palette with default colors** - Match what real hardware/ROM might do
2. **Accept black as valid** - Uninitialized DRAM is undefined; black is as valid as any other color
3. **Investigate ROM initialization** - Check if ROM code initializes palette before game loads

## Issue #2: Colored Glitch Bars

### Symptoms

- Horizontal colored stripes (yellow, green, red) near bottom of screen
- Appears where text "DreamWorld Society, 1990" should be displayed
- Stripes span full width of active display area

### Investigation: Palette Byte Order (NOT the cause)

Initially suspected the palette byte order was wrong. However, testing showed the existing code is correct.

**Key insight:** At H=0x390, the address is pre-incremented before the palette read loop. This means:
- Palette address starts at $9E00 (set at H=0x38e)
- Pre-increment at H=0x390 makes it $9E01
- First read in H<32 loop is at ODD address ($9E01)

So the read sequence is: $9E01, $9E02, $9E03, $9E04, ...

The current code correctly handles this:
```verilog
if (video_addr_shrg[0]) begin  // ODD (first read of each color)
    b_shrg[pal_counter]<=video_data[3:0];
    g_shrg[pal_counter]<=video_data[7:4];
end else begin                  // EVEN (second read of each color)
    r_shrg[pal_counter]<=video_data[3:0];
    pal_counter<=pal_counter+1;
end
```

**Verified:** Regression tests (GS/OS, Total Replay, Pitch Dark) all pass with this code.

### Actual Cause: Uninitialized Slow RAM

The colored glitch bars in Task Force are caused by **uninitialized slow RAM** in the palette area:

1. Task Force has SHR shadow DISABLED (shadow bit 3 = 1)
2. Game writes palette to bank $00:9E00 (fast RAM only)
3. VGC reads from bank $E1:9E00 (slow RAM) which is never written
4. Slow RAM contains random/uninitialized values
5. These garbage values appear as colored stripes

### Why Other Games Work

Games like GS/OS properly initialize the palette with shadow ENABLED, so writes to bank $00/$01 are mirrored to E0/E1 where the VGC reads from.

### Potential Fixes

1. **Initialize slow RAM palette area** with default colors at boot/reset
2. **ROM emulation** - ensure ROM initialization code runs before games
3. **Accept as correct** - uninitialized DRAM has undefined values; garbage is valid

## Issue #3: Task Force Multipalette Screen (Black) - FIXED

### Symptoms

After pressing a key to advance past the title screen, the multipalette (3200-color) image should display but shows all black.

### Root Cause Found

The shadow register implementation in `rtl/iigs.sv` had a bug:

**Bug**: `shgr_shadow` was defined as covering `$2000-$9FFF` (pages 2-9)
```verilog
wire shgr_shadow = ~shadow[3] && (page >= 4'h2 && page <= 4'h9);  // WRONG
```

**Fix**: Shadow bit 3 should only control `$6000-$9FFF` (pages 6-9). Pages `$2000-$5FFF` are controlled by HGR bits 1-2.
```verilog
wire shgr_shadow = ~shadow[3] && (page >= 4'h6 && page <= 4'h9);  // CORRECT
```

Additionally, Bank 00 shadow check was missing `shgr_shadow`:
```verilog
// Before: txt1_shadow || txt2_shadow || hgr1_shadow || hgr2_shadow
// After:  txt1_shadow || txt2_shadow || hgr1_shadow || hgr2_shadow || shgr_shadow
```

### Why This Caused Black Screen

With shadow = 0x28:
- Bit 1 = 0: HGR Page 1 ($2000-$3FFF) shadow ENABLED
- Bit 2 = 0: HGR Page 2 ($4000-$5FFF) shadow ENABLED
- Bit 3 = 1: SHR-only ($6000-$9FFF) shadow DISABLED

The old code incorrectly treated bit 3 as controlling the entire $2000-$9FFF range, so when bit 3=1, NO shadowing occurred for any of those addresses. The game's pixel data written to $2000-$5FFF never reached bank E1 where the VGC reads from.

### Result After Fix

The multipalette image now displays correctly showing:
- Gradient sky (multiple blues)
- City skyline with buildings
- Moon in upper left
- Soldier character with weapon
- Burning helicopter in upper right

### Reference

KEGS Task Force screenshot (kegs_taskforce_2.png) shows correct multipalette display for comparison.

## SCB Format Reference

```
Bit 7: Mode (0=320px, 1=640px)
Bit 6: Interrupt enable
Bit 5: Color Fill mode enable
Bit 4: Reserved
Bits 3-0: Palette select (0-15)
```

With SCB = 0x00:
- 320-pixel mode
- No interrupt
- No fill mode
- Palette 0 selected

## Next Steps

1. Add debug output to VGC to trace palette reads per scanline
2. Compare palette values being used vs what's in memory
3. Check if the glitch bars appear at consistent scanline numbers
4. Verify the raster effect writes to TEXTCOL aren't somehow affecting SHR output

## Files Involved

- `rtl/vgc.v` - Video Graphics Controller implementation
- `rtl/iigs.sv` - Memory mapping and shadow logic
- `rtl/slowram.v` - Slow RAM module (no initialization)
- `rtl/video_timing.v` - Timing generation

## Reference Screenshots

### Title Screen (Issue #1 & #2 - Still Present)
| Source | Background | Glitch Bars |
|--------|------------|-------------|
| Our simulator | Black | Yes (colored stripes) |
| Clemens | Gray | No |
| KEGS | Gray | No |

### Multipalette Screen (Issue #3 - FIXED)
| Source | Status |
|--------|--------|
| Our simulator | Now displays correctly |
| KEGS | Reference image matches |

## Summary of Fixes

1. **rtl/iigs.sv line 420**: Changed `shgr_shadow` range from `$2000-$9FFF` to `$6000-$9FFF`
2. **rtl/iigs.sv line 440**: Added `shgr_shadow` to Bank 00 shadow condition
