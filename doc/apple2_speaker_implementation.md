# Apple IIgs Sound Implementation - Research Report

## Executive Summary

**Current Status:**

1. **DOC Sound Too Quiet:** The current es5503.v implementation has a major bug - it outputs only ONE oscillator at a time instead of accumulating all enabled oscillators. Additionally, the master volume from Sound GLU is stored but never applied.

2. **Apple II Speaker Implemented but Clicky:** The speaker toggle at $C030 is now functional and mixed with DOC output, but produces audible clicks/pops. This is due to missing sustain/timeout logic that reference implementations use.

### Speaker Implementation Comparison

| Aspect | Our Implementation | a2fpga (Reference) |
|--------|-------------------|-------------------|
| Toggle mechanism | ✅ Same - flip on $C030 | `speaker_bit <= !speaker_bit` |
| Audio amplitude | ✅ Same - +/-8192 | 1-bit extended to audio range |
| Countdown timer | ❌ **Missing** | 20-bit (~75ms at 14MHz) |
| Idle behavior | Always +/-8192 (DC offset) | Returns to 0 after timeout |
| Result | Clicky audio | Clean audio |

**Root cause of clicking:** Without the countdown timer, our speaker output has a constant DC offset. When the speaker starts/stops, this creates an abrupt level change that produces audible clicks.

---

## Part 1: DOC/ES5503 Volume Analysis

### Current Implementation Problems

**Problem 1: No Oscillator Accumulation (CRITICAL BUG)**

In `rtl/es5503.v` lines 198-202:
```verilog
if (r_control[current_osc][2:1] == 2'd2 && current_osc[0] == 1'd1)
  sound_out <= 16'h0000; // AM mode; no sample playback
else // All other modes
  sound_out <= $signed(r_sample_data[current_osc] ^ 8'h80) *
               $signed({8'b0, r_volume[current_osc]});
```

This **overwrites** `sound_out` every oscillator cycle instead of accumulating. When multiple oscillators are playing, only the last one is heard!

**Problem 2: Master Volume Not Applied**

In `rtl/soundglu.v` line 26, 70:
```verilog
reg [3:0] volume;
// ...
volume <= host_data_in[3:0];  // Stored but NEVER USED
```

The master volume from $C03C bits 0-3 is stored but never applied to audio output.

**Problem 3: No Output Scaling**

In `rtl/sound.v` line 38:
```verilog
sound_out <= doc_sound_out;  // Direct passthrough, no scaling
```

---

### How Reference Emulators Handle Volume

#### KEGS/GSPlus Formula

```c
// Per-oscillator volume * master volume
imul = (rptr->vol * g_doc_vol);        // 0-255 * 0-15 = 0-3825
off = imul * 128;                       // DC offset

// Sample scaling with right-shift by 4 (divide by 16)
val2 = (val * imul - off) >> 4;

// Multiple oscillators ACCUMULATED
val2 = outptr[0] + val2;  // Add to existing mix
```

**Key constants:**
- Per-oscillator volume: 8-bit (0-255)
- Master volume: 4-bit (0-15) from $C03C
- Combined multiplier: up to 3825
- Final scaling: `>> 4` (divide by 16)
- Output clipped to 16-bit signed (-32768 to +32767)

#### Clemens Formula

```c
// Normalize sample to [-1.0, +1.0]
level = (2.0f * data / 255.0f) - 1.0f;

// Apply per-oscillator volume
doc->voice[channel] += level * (volume / 255.0f);

// Sum all channels, clamp to [-1.0, +1.0]
// Apply master volume (0-7 from bits 0-2)
samples[0] = 0.75f * ((doc_out + speaker_level) * glu->volume / 15.0f);
```

**Key differences:**
- Master volume range: 0-7 (only 3 bits used)
- Amplitude scalar: 0.75 (reduces overall level)
- Float-based mixing with clamping

#### a2fpga_core doc5503.sv

```verilog
// Accumulate all oscillators into mix registers
next_mono_mix_r <= next_mono_mix_r + curr_output_r;

// Extract 16-bit window from 24-bit accumulator
mono_mix_r <= {
    next_mono_mix_r[MIXER_SUM_RESOLUTION-1],  // Sign bit
    next_mono_mix_r[MIXER_SUM_RESOLUTION-1-TOP_BIT_OFFSET -: WINDOW_SIZE]
};
```

**Key features:**
- 24-bit internal accumulator for headroom
- Extracts 15-bit magnitude + sign for output
- Proper stereo routing (odd channels right, even channels left)
- Master volume: Commented out in current code (TODO)

---

### Volume Comparison Table

| Aspect | Current (es5503.v) | KEGS/GSPlus | Clemens | a2fpga doc5503 |
|--------|-------------------|-------------|---------|----------------|
| Per-osc volume | 8-bit multiply | 8-bit multiply | 8-bit multiply | 8-bit multiply |
| Master volume | **NOT APPLIED** | Applied (0-15) | Applied (0-7) | Commented out |
| Oscillator mixing | **NONE** (overwrites) | Accumulates all | Accumulates all | Accumulates all |
| Output scaling | None | `>> 4` | `* 0.75` | Window extraction |
| Output range | 16-bit raw | 16-bit clipped | Float [-1,1] | 16-bit signed |

---

### Why DOC Sound is Too Quiet

1. **Only one oscillator audible:** Even with 8+ oscillators playing, only the last processed oscillator's sample is output
2. **No master volume:** The volume knob in software has no effect
3. **No proper scaling:** Raw multiplication output without normalization

---

## Part 2: Apple II Speaker ($C030)

### Current Implementation Status

The Apple II speaker is now implemented and produces audio:

**Toggle Logic (iigs.sv lines 941, 1304):**
```verilog
// Both read and write to $C030 toggle the speaker state
12'h030: begin SPKR <= cpu_dout; speaker_state <= ~speaker_state; end  // write
12'h030: begin io_dout <= SPKR; speaker_state <= ~speaker_state; end   // read
```

**Audio Mixing (sound.v lines 39-47):**
```verilog
// Speaker audio: +/- 8192 centered around 0
wire signed [15:0] speaker_audio = speaker_state ? 16'sh2000 : -16'sh2000;

// Boost DOC output by 4x (<<2) and mix with speaker
wire signed [15:0] doc_boosted = doc_sound_out <<< 2;
sound_out <= doc_boosted + speaker_audio;
```

### Known Issue: Clicky/Popping Audio

The current implementation produces audible clicks and pops. This is caused by:

1. **No sustain/timeout mechanism:** The output instantly jumps between +8192 and -8192 on every toggle, with no smoothing
2. **Constant DC offset when idle:** When the speaker isn't being toggled, the output is stuck at either +8192 or -8192 rather than returning to 0
3. **Abrupt transitions:** Real speakers and the a2fpga implementation have a decay/timeout that smooths transitions

### How Apple II Speaker Works

**Basic Mechanism:**
- Any access (read or write) to `$C030` toggles the speaker state
- The speaker is a 1-bit output that alternates between high and low
- Software creates sound by toggling at precise intervals (timing-dependent)
- Typical Apple II programs toggle at rates from ~20Hz to ~20kHz

**Key Insight:** The speaker doesn't just "click" - rapid toggling creates square waves.

### Reference Implementation Comparison

| Aspect | Apple-II-Verilog_MiSTer | Clemens | GSPlus | a2fpga_core |
|--------|------------------------|---------|--------|-------------|
| Toggle mechanism | `speaker_sig <= ~speaker_sig` | `glu->a2_speaker = !glu->a2_speaker` | Records timestamp | `speaker_bit <= !speaker_bit` |
| Timing reference | CLK_14M + CPU_EN_POST | `dt_clocks` accumulator | `dcycs * g_dsamps_per_dcyc` | phi1_posedge |
| Audio output | 1-bit in audio[7] | Float ±0.50 | 16-bit ±16384 | 1-bit extended to 13-bit |
| Speed handling | Natural toggle rate | Clock normalization | Cycle-to-sample conversion | Natural toggle rate |

### a2fpga Speaker Implementation (Recommended Approach)

The a2fpga implementation uses a **countdown timer** to prevent DC offset and reduce clicks:

```verilog
module apple_speaker (
    a2bus_if.slave a2bus_if,
    input enable,
    output reg speaker_o
);
    reg speaker_bit;

    // Toggle on $C030 access
    always @(posedge a2bus_if.clk_logic or negedge a2bus_if.system_reset_n) begin
        if (!a2bus_if.system_reset_n)
            speaker_bit <= 1'b0;
        else if (a2bus_if.phi1_posedge && (a2bus_if.addr[15:0] == 16'hC030) && !a2bus_if.m2sel_n)
            speaker_bit <= !speaker_bit;
    end

    // 20-bit countdown timer (~75ms at 14MHz)
    localparam COUNTDOWN_WIDTH = 20;
    reg [COUNTDOWN_WIDTH - 1:0] countdown;
    reg prev_speaker_bit;

    always_ff @(posedge a2bus_if.clk_logic) begin
        // Reset countdown on any speaker toggle
        if (speaker_bit != prev_speaker_bit) begin
            countdown <= '1;  // Set to max (2^20-1 = ~1M cycles = ~75ms)
        end else begin
            countdown <= countdown != 0 ? countdown - 1 : 0;
        end
        prev_speaker_bit <= speaker_bit;

        // Output follows speaker_bit while countdown active, else silence
        if ((countdown != 0) && enable)
            speaker_o <= speaker_bit;
        else
            speaker_o <= 0;  // Return to center (silence) after timeout
    end
endmodule
```

**Key features that reduce clicking:**

1. **Countdown timer (20-bit):** At 14MHz, 2^20 cycles = ~75ms timeout
2. **Auto-silence:** When speaker hasn't toggled for 75ms, output returns to 0 (center)
3. **No DC offset when idle:** Unlike our implementation which is always +/-8192
4. **Edge detection:** Uses `prev_speaker_bit` to detect transitions

**Why this helps with clicks:**
- When audio stops, the output gracefully returns to center (0) after timeout
- No abrupt DC offset jumps when mixing with DOC audio
- The 75ms window is long enough to cover any audio waveform but short enough to return to center between sounds

### Phi2 Speed Considerations

**The IIgs runs at two speeds:**
- **Slow mode (1.023 MHz):** Apple II compatible timing
- **Fast mode (2.864 MHz):** Native IIgs speed

**How emulators handle this:**
- **a2fpga/MiSTer:** Let the toggle happen at natural CPU rate (simpler)
- **KEGS/GSPlus:** Convert CPU cycles to sample positions using speed-aware factor
- **Clemens:** Normalize clock ticks to audio sample rate

**Recommendation:** For Verilog implementation, let the toggle happen naturally. Speaker toggles at whatever rate the CPU accesses $C030 - this is correct behavior since real hardware works the same way.

---

## Part 3: Recommended Implementation Plan

### Phase 1: Fix DOC Volume (Priority)

1. **Add oscillator accumulation in es5503.v:**
   ```verilog
   reg signed [23:0] mix_accumulator;  // 24-bit for headroom

   // In oscillator processing loop:
   if (!r_control[current_osc][0])  // If running
     mix_accumulator <= mix_accumulator + scaled_sample;

   // At end of oscillator scan:
   if (current_osc == oscs_enabled)
     sound_out <= mix_accumulator[23:8];  // Extract 16-bit window
     mix_accumulator <= 0;  // Reset for next cycle
   ```

2. **Apply master volume:**
   ```verilog
   // In sound.v or es5503.v
   wire [15:0] scaled_output = (doc_sound_out * {12'b0, master_volume}) >> 4;
   ```

3. **Pass master volume from soundglu to es5503:**
   - Add volume output port to soundglu
   - Wire to es5503 or sound.v for scaling

### Phase 2: Fix Clicky Speaker Sound

The speaker is implemented but produces clicks. Add countdown timer logic (adapted from a2fpga):

1. **Add countdown timer in iigs.sv:**
   ```verilog
   // Speaker countdown for auto-silence (20-bit = ~75ms at 14MHz)
   reg [19:0] speaker_countdown;
   reg        speaker_state_prev;

   always @(posedge CLK_14M) begin
     if (reset) begin
       speaker_countdown <= 0;
       speaker_state_prev <= 0;
     end else begin
       // Reset countdown on any speaker toggle
       if (speaker_state != speaker_state_prev)
         speaker_countdown <= 20'hFFFFF;  // ~75ms
       else if (speaker_countdown != 0)
         speaker_countdown <= speaker_countdown - 1;

       speaker_state_prev <= speaker_state;
     end
   end

   // Speaker output: follow toggle while active, else center (0)
   wire speaker_active = (speaker_countdown != 0);
   ```

2. **Update sound.v mixing:**
   ```verilog
   // Speaker audio: +/- 8192 when active, 0 when silent
   wire signed [15:0] speaker_audio = speaker_active ?
                                      (speaker_state ? 16'sh2000 : -16'sh2000) :
                                      16'sh0000;
   ```

**Why this fixes clicking:**
- Removes constant DC offset when speaker is idle
- Audio returns to center (0) smoothly after ~75ms of inactivity
- Eliminates abrupt transitions when mixing starts/stops

### Phase 3: Volume Balance

Based on reference emulators:
- **DOC with master vol=2:** Output range roughly ±4000
- **Speaker:** Output range ±8192 to ±16384 (louder than DOC for compatibility)

### Implementation Progress

| Component | Status | Notes |
|-----------|--------|-------|
| Speaker toggle ($C030) | ✅ Done | Both read/write toggle `speaker_state` |
| Speaker mixing | ✅ Done | Mixed with DOC in sound.v |
| DOC boost (4x) | ✅ Done | `doc_sound_out <<< 2` |
| Speaker countdown timer | ❌ TODO | Causes clicking without it |
| DOC oscillator accumulation | ❌ TODO | Only one oscillator audible |
| Master volume | ❌ TODO | Stored but not applied |

---

## Files That Need Modification

### Already Modified (Speaker Basic Support)

1. **rtl/iigs.sv:**
   - ✅ Added `speaker_state` register
   - ✅ Toggle on $C030 read/write
   - ✅ Pass `speaker_state` to sound module
   - ❌ TODO: Add countdown timer logic

2. **rtl/sound.v:**
   - ✅ Added `speaker_state` input port
   - ✅ Mix speaker with DOC output (+/- 8192)
   - ✅ Boost DOC output 4x
   - ❌ TODO: Add `speaker_active` input for countdown

### Still Need Modification (DOC Volume)

3. **rtl/es5503.v:**
   - Add mix accumulator register
   - Accumulate oscillator outputs instead of overwriting
   - Reset accumulator at end of scan cycle

4. **rtl/soundglu.v:**
   - Export volume register to output port

---

## Source References

### DOC Volume
- **KEGS:** `sound.c` lines 889-949 (volume multiplication and mixing)
- **GSPlus:** `sound.c` lines 745-949 (identical to KEGS)
- **Clemens:** `clem_audio.c` lines 293-343, 518-575 (float-based mixing)
- **a2fpga:** `doc5503.sv` lines 309-322, 911-921 (accumulator mixing)

### Speaker
- **Apple-II-Verilog_MiSTer:** `rtl/apple2.v` lines 154-164, 279-282, 347-354
- **Clemens:** `clem_audio.c` lines 518-599, 601-651
- **GSPlus:** `sound.c` lines 742-825, 1596-1612
- **a2fpga:** `apple_speaker.sv` (complete file, 39 lines)

### Documentation
- **IIGS_ioandclock.md:** line 405 (SPKR at $C030)
- **$C03C:** Sound Control Register (bits 0-3 = master volume, bit 5 = auto-inc, bit 6 = RAM/DOC select)
