# SHRG Pipeline Timing Analysis

## Overview

This document describes the Super Hi-Res Graphics (SHRG) pixel pipeline timing in the VGC (Video Graphics Controller) implementation and the issues with the first pixels of each scanline being hidden by the left border.

## Problem Statement

The nhf.po disk image (and potentially other software) shows a loading bar with its left edge cropped off. The left vertical line of the progress bar box is not visible because the first few pixels of each scanline are being hidden by the extended left border.

Clemens emulator shows the complete box outline, while our simulation crops the leftmost pixels.

## SHRG Memory Layout

The Super Hi-Res display buffer in bank $E1:
- **$2000-$9CFF**: Pixel data (160 bytes per scanline × 200 scanlines = 32,000 bytes)
- **$9D00-$9DC7**: Scan-line Control Bytes (SCBs) - 200 bytes, one per scanline
- **$9E00-$9FFF**: Color palettes (16 palettes × 32 bytes = 512 bytes)

### SCB Format (1 byte per scanline)
```
Bit 7: 0=320 mode (4bpp), 1=640 mode (2bpp)
Bit 6: Interrupt enable for this scanline
Bit 5: Color Fill mode enable (320 mode only)
Bit 4: Reserved
Bits 3-0: Palette number (0-15)
```

### Palette Format (32 bytes per palette, 16 colors)
```
Even addresses ($9E00, $9E02, ...): 0GGG BBBB (Green bits 6-4, Blue bits 3-0)
Odd addresses ($9E01, $9E03, ...):  0000 RRRR (Red bits 3-0)
```

### Pixel Data Format
- **320 mode**: 4 bits per pixel, 2 pixels per byte (160 bytes = 320 pixels)
- **640 mode**: 2 bits per pixel, 4 pixels per byte (160 bytes = 640 pixels)

## Horizontal Timing (H counter)

The VGC uses a horizontal counter H that runs from 0 to ~912 (one scanline).

### Current SHRG Horizontal Phases

| H Range | Phase | Description |
|---------|-------|-------------|
| 0x38C (908) | SCB Fetch | Set address to $9D00 + (V-15) to pre-fetch next line's SCB |
| 0x38E (910) | SCB Read | Read SCB, setup palette address based on SCB[3:0] |
| 0x390 (912) | Palette Start | Reset pal_counter, start palette address increment |
| 0-31 | Palette Read | Read 32 bytes of palette data (16 colors × 2 bytes) |
| 31 | Pixel Addr Setup | Set video_addr_shrg to $12000 + (V-16) × 160 |
| 32-671 | Active Display | Process and output 640 pixel clocks |
| 672+ | Right Border | Border color output |

### Pipeline Latency Detail

The pixel pipeline has the following stages:

```
Cycle N-1 (H=31):  video_addr_shrg <= pixel_address    [Address Setup]
                   h_counter <= 0
                   shrg_r_pix <= 0 (clearing active)

Cycle N (H=32):    video_data = MEM[video_addr_shrg]   [Data Valid]
                   h_counter <= 1
                   case(h_counter=0):                   [Pixel Compute]
                     shrg_r_pix <= r_shrg[video_data[7:4]]

Cycle N+1 (H=33):  R <= shrg_r_pix                     [Output Available]
```

**Key insight**: Due to non-blocking assignments (<=), the value computed for `shrg_r_pix` at H=32 is not available for output until H=33.

## Current Border Timing

```verilog
// Border condition (line 827 in vgc.v)
(NEWVIDEO[7] && ((H < 'd36 || H >= 'd672 || V < 'd16 || V >= 'd216)))
```

- **Left border**: H < 36 (36 pixels)
- **Active display**: H = 36 to 671 (636 pixels, NOT 640!)
- **Right border**: H >= 672 (32 pixels)

The left border was extended from H < 32 to H < 36 to account for pipeline latency. This hides the first 4 pixel clock cycles of computed data.

## The Problem

With the border at H < 36:
- Pixels are computed starting at H=32
- But display only starts at H=36
- The first 4 cycles of pixel data (H=32-35) are computed but covered by border
- In 320 mode: First 2 pixels lost (4 cycles ÷ 2 cycles/pixel)
- In 640 mode: First 4 pixels lost (4 cycles ÷ 1 cycle/pixel)

Software that draws content in the leftmost pixels will have it cropped.

## Attempted Fixes

### Attempt 1: Move Border to H < 32
Simply changing the border to H < 32 causes the first displayed pixels to be invalid (showing the cleared value of 0, or garbage from previous line).

### Attempt 2: Move Address Setup Earlier (H=30)
Moving the address setup from H=31 to H=30 doesn't help because:
- The active display processing is in an `else if (H < 672)` block
- This only triggers when H >= 32 (after the `H < 32` palette block)
- Moving address setup doesn't change when pixel computation starts

Changes made:
```verilog
// Changed from H==31 to H==30
if (H==30) begin
    video_addr_shrg <= 'h12000 + ((V-16) * 'd160);
    h_counter <= 0;
end
```

Result: Caused extra line artifacts on left side of screen in GS/OS, Arkanoid, Pirates.

### Attempt 3 (Proposed): Pre-compute First Pixel During Palette Phase

The idea is to compute the first pixel's color values during H=31 (the last cycle of the palette reading phase) so they're ready for display at H=32.

Implementation approach:
1. At H=31, after setting pixel address, also trigger a "prefetch" read
2. The prefetch data arrives at H=32
3. At H=32, compute first pixel from prefetch data AND start normal pipeline
4. First pixel is ready for output at H=32

## Code Structure Reference

### SHRG Processing Block (vgc.v lines ~115-246)

```verilog
always @(posedge clk_vid) begin
if (ce_pix) begin
    if (NEWVIDEO[7]) begin  // SHRG mode enabled

        // SCB fetch at H=0x38C
        if (H=='h38c) begin
            video_addr_shrg <= 'h19D00+(V-'d15);
        end

        // SCB read and palette setup at H=0x38E
        else if (H=='h38e) begin
            scb <= video_data;
            // Setup palette address
            video_addr_shrg <= 'h19E00 + {video_data[3:0],5'b00000};
        end

        // Palette counter reset at H=0x390
        else if (H=='h390) begin
            pal_counter <= 0;
            video_addr_shrg <= video_addr_shrg + 1'b1;
        end

        // Palette reading at H < 32
        else if (H < 32) begin
            // Read palette bytes, store in r_shrg/g_shrg/b_shrg arrays
            if (video_addr_shrg[0]) begin
                b_shrg[pal_counter] <= video_data[3:0];
                g_shrg[pal_counter] <= video_data[7:4];
            end else begin
                r_shrg[pal_counter] <= video_data[3:0];
                pal_counter <= pal_counter + 1;
            end

            // At H=31, setup pixel address
            if (H==31) begin
                video_addr_shrg <= 'h12000 + ((V-16) * 'd160);
                h_counter <= 0;
            end
        end

        // Active display at H=32 to H=671
        else if (H < ('d32+640)) begin
            h_counter <= h_counter + 1'b1;

            // Address advance every 4 cycles (320 mode) or 2 cycles (640 mode)
            if (h_counter==2'd2 && H < 'd668) begin
                video_addr_shrg <= video_addr_shrg + 1'b1;
            end

            // Pixel color lookup based on mode
            if (scb[7]) begin
                // 640 mode: 4 pixels per byte
                case(h_counter)
                    'b00: shrg_r_pix <= r_shrg[{2'b10,video_data[7:6]}];
                    'b01: shrg_r_pix <= r_shrg[{2'b11,video_data[5:4]}];
                    'b10: shrg_r_pix <= r_shrg[{2'b00,video_data[3:2]}];
                    'b11: shrg_r_pix <= r_shrg[{2'b01,video_data[1:0]}];
                endcase
            end else begin
                // 320 mode: 2 pixels per byte
                case(h_counter)
                    'b00: shrg_r_pix <= r_shrg[video_data[7:4]];
                    'b10: shrg_r_pix <= r_shrg[video_data[3:0]];
                endcase
            end
        end

        // Clear pixel registers during border
        if (NEWVIDEO[7] && (H < 'd32 || H >= 'd672)) begin
            shrg_r_pix <= 4'b0;
            shrg_g_pix <= 4'b0;
            shrg_b_pix <= 4'b0;
        end
    end
end
end
```

### Output Block (vgc.v lines ~825-851)

```verilog
// Border vs Active display selection
if (NEWVIDEO[7] && (H < 'd36 || H >= 'd672 || V < 'd16 || V >= 'd216)) begin
    // Border - output border color
    R <= {BORGB[11:8],BORGB[11:8]};
    G <= {BORGB[7:4],BORGB[7:4]};
    B <= {BORGB[3:0],BORGB[3:0]};
end else begin
    // Active - output pixel color
    R <= {shrg_r_pix,shrg_r_pix};
    G <= {shrg_g_pix,shrg_g_pix};
    B <= {shrg_b_pix,shrg_b_pix};
end
```

## Option 3 Implementation Plan

To pre-compute the first pixel during H=31:

1. **At H=31** (end of palette reading):
   - Set pixel address (already done)
   - Also set a "prefetch_pending" flag

2. **At H=32** (first cycle of active area):
   - video_data now contains first pixel byte
   - Compute first pixel color immediately
   - Use combinational logic to output this value directly
   - OR use a separate "first_pixel" register that bypasses the normal pipeline

3. **Alternative approach** - use registered output with 1-cycle lookahead:
   - At H=31, compute what the first pixel WOULD be if we had the data
   - Use a mux to select between "prefetched first pixel" and "normal pipeline"

### Proposed Code Changes

```verilog
// New registers for first pixel prefetch
reg [3:0] first_pixel_r, first_pixel_g, first_pixel_b;
reg first_pixel_valid;

// At H=31, prepare for first pixel
if (H==31) begin
    video_addr_shrg <= 'h12000 + ((V-16) * 'd160);
    h_counter <= 0;
    first_pixel_valid <= 1;  // Flag that next pixel needs special handling
end

// At H=32, handle first pixel specially
if (H==32 && first_pixel_valid) begin
    // Compute first pixel immediately from video_data
    if (scb[7]) begin  // 640 mode
        first_pixel_r <= r_shrg[{2'b10,video_data[7:6]}];
        // ... g and b
    end else begin  // 320 mode
        first_pixel_r <= r_shrg[video_data[7:4]];
        // ... g and b
    end
    first_pixel_valid <= 0;
end

// Output mux - use first_pixel values at H=32, normal pipeline after
if (H==32) begin
    R <= {first_pixel_r, first_pixel_r};
    // ...
end else begin
    R <= {shrg_r_pix, shrg_r_pix};
    // ...
end
```

## Option 1 Implementation Plan (Full Pipeline Restructure)

If Option 3 doesn't work, a full restructure would involve:

1. **Move pixel processing to start at H=31**:
   - Change the else-if structure so pixel processing starts earlier
   - This requires separating pixel address setup from pixel computation

2. **Use a multi-stage pipeline**:
   ```
   Stage 1 (H=30): Set pixel address
   Stage 2 (H=31): Read pixel data, compute color
   Stage 3 (H=32): Output pixel (border ends here)
   ```

3. **Adjust all timing constants**:
   - Address advance timing
   - Right border start
   - End of active area detection

This is more invasive but would properly align the pipeline.

## Testing

Key test cases:
- **nhf.po**: Should show complete loading bar box with left edge visible
- **Arkanoid**: Should not have extra line on left
- **GS/OS**: Should not have extra line on left
- **Pirates**: Should not have extra line on left
- **All regression tests**: Must pass

## References

- vgc.v: Main VGC implementation
- IIGS_video.md: Apple IIgs Hardware Reference video documentation
- KEGS source (video.c, superhires.h): Reference emulator implementation
