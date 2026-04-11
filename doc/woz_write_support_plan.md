# WOZ Disk Write Support - Implementation Plan

## Difficulty Assessment

**Medium-Hard.** Roughly 60% of the infrastructure already exists and is tested.
The main new work is the IWM write shift register state machine in `iwm_flux.v`.
Estimate: 3-4 focused sessions of work.

**Key simplification vs MAME:** MAME records flux transition *timestamps* into a
64K-entry buffer, then batch-flushes them to the floppy device which merges them
into a position-indexed track buffer. Our design is simpler: since we store raw
WOZ bitstream bits in BRAM, writes just set/clear individual bits at the current
`bit_position` — no time-to-position conversion, no buffering, no flushing.

### What Already Exists (working)

| Component | File | Status |
|-----------|------|--------|
| CPU write byte capture | `iwm_flux.v:1344` | `m_data` loaded on `$C0ED` writes |
| Write shift register | `iwm_flux.v:105` | `m_wsh` register declared, unused |
| Write handshake register | `iwm_flux.v:106` | `m_whd` with underrun handling |
| Write mode tracking | `iwm_flux.v:116` | `m_rw_mode` tracks Q7 state |
| Write underrun counter | `iwm_flux.v:124` | `write_underrun_cnt` clears WHD bit6 |
| Window timing infrastructure | `iwm_flux.v:217-253` | `base_half_window`, fractional accum, `load_half_window` task |
| BRAM write ports | `woz_floppy_ctrl.sv:115-116,132-133` | Dual-port, `bit_we` exists but hardwired 0 |
| Dirty flag + save-on-seek | `woz_floppy_ctrl.sv:208,507,652-687` | Sets dirty on `bit_we`, triggers `S_SAVE_TRACK` |
| S_SAVE_TRACK state machine | `woz_floppy_ctrl.sv:1050-1070` | DMA from BRAM back to SD blocks |
| RAM-to-SD DMA path | `woz_floppy_ctrl.sv:1241-1249` | Reads BRAM, feeds `sd_buff_din` |
| SD block write handling | `sim_blkdevice.cpp:84-98,151` | Detects `sd_wr`, writes bytes to file |
| File opened read/write | `sim_blkdevice.cpp:39` | `ios::out | ios::in | ios::binary` |
| Write protect signal | `flux_drive.v:42,398` | `DISK_WP` input → `WRITE_PROTECT` output |
| Bit position tracking | `flux_drive.v:327-330` | `byte_index`, `bit_shift` (MSB-first) |
| m_data_gen tracking | `iwm_flux.v:118,1346` | Generation counter for detecting new CPU writes |

### What's Missing

| Component | File | Work |
|-----------|------|------|
| Write shift register state machine | `iwm_flux.v` | 4-state FSM mirroring MAME's SW_* states |
| FLUX_WRITE output + WRITE_STROBE | `iwm_flux.v:1611` | Currently hardwired to `1'b0` |
| flux_drive write input ports | `flux_drive.v` | WRITE_DATA, WRITE_STROBE, WRITE_MODE |
| BRAM bit-level write in flux_drive | `flux_drive.v` | Read-modify-write at current bit position |
| iwm_woz.v signal routing | `iwm_woz.v:520-521,605-606` | `bit_data_in`/`bit_we` hardwired to 0 |
| WOZ v1 save-back address math | `woz_floppy_ctrl.sv` | S_SAVE_TRACK for v1's 6656-byte entries |
| Write protect gating in IWM | `iwm_flux.v` | Suppress writes when WRITE_PROTECT asserted |

---

## MAME Reference: IWM Write Algorithm

Source: `mame/src/devices/machine/iwm.cpp` lines 566-640, `mame/src/devices/machine/iwm.h`

### State Machine (sync mode, which is what Apple II/IIgs uses)

MAME's write uses 4 active states in the `sync()` function:

```
S_IDLE → SW_WINDOW_MIDDLE → SW_WINDOW_END → SW_WINDOW_MIDDLE (loop)
                                    ↓ (every 8 bits)
                              SW_WINDOW_LOAD → SW_WINDOW_MIDDLE
                                    ↓ (if no new data)
                              SW_UNDERRUN (stop)
```

**S_IDLE** (iwm.cpp:575-586): Entry point when write mode activates.
```cpp
// Sync mode (normal):
m_wsh = m_data;                                    // Load first byte
m_rw_state = SW_WINDOW_MIDDLE;
m_next_state_change = m_last_sync + half_window_size();
```

**SW_WINDOW_MIDDLE** (iwm.cpp:605-611): Shift out one bit per call.
```cpp
if(m_wsh & 0x80)                                   // Check MSB
    m_flux_write[m_flux_write_count++] = m_last_sync; // Record flux transition
m_wsh <<= 1;                                       // Shift left
m_rw_state = SW_WINDOW_END;
m_next_state_change = m_last_sync + half_window_size();
```
- A **1-bit** records a flux transition timestamp; a **0-bit** does not.
- Each state transition takes `half_window_size()` cycles.
- A full bit-cell = MIDDLE + END = 2 x half_window = one `window_size()`.

**SW_WINDOW_END** (iwm.cpp:613-630): Second half of bit cell.
```cpp
// Sync mode: immediately go back to shift next bit
m_next_state_change = m_last_sync + half_window_size();
m_rw_state = SW_WINDOW_MIDDLE;
// (Async mode: count bits, go to SW_WINDOW_LOAD after 8)
```
In sync mode, there is no explicit byte boundary — bits shift continuously.
The byte reload happens implicitly: `data_w()` writes directly to `m_wsh`
when in sync+write mode (see below).

**SW_WINDOW_LOAD** (iwm.cpp:588-603): Byte boundary (async mode only).
```cpp
if(m_whd & 0x80) {                // Underrun: CPU didn't write in time
    flush_write(next_sync);
    write_clock_stop();
    m_whd &= ~0x40;               // Clear write-enable bit
    m_rw_state = SW_UNDERRUN;
} else {
    m_wsh = m_data;                // Load next byte
    m_rw_state = SW_WINDOW_MIDDLE;
    m_whd |= 0x80;                // Set underrun flag (CPU must clear)
    m_next_state_change = m_last_sync + half_window_size() - 7;
}
```

### CPU Data Write (iwm.cpp:374-381)

```cpp
void iwm_device::data_w(u8 data) {
    m_data = data;
    if(is_sync() && m_rw == MODE_WRITE)
        m_wsh = data;              // SYNC MODE: immediately load shift register
    if(m_mode & 0x01)
        m_whd &= 0x7f;            // LATCHED MODE: clear underrun flag
}
```

**Critical insight for sync mode:** The CPU write goes *directly* into `m_wsh`,
not through the SW_WINDOW_LOAD state. This means in sync mode, the state machine
just runs SW_WINDOW_MIDDLE ↔ SW_WINDOW_END continuously shifting out whatever is
in `m_wsh`. The CPU is responsible for timing its writes to land between the 8th
bit shifting out and the 1st bit of the next byte.

### Window Timing (iwm.cpp:398-424)

```cpp
u64 half_window_size() const {
    if(m_q3_clock_active)              // Q3 clock (7MHz) used during writes
        return m_mode & 0x08 ? 2 : 4; // fast=2, slow=4
    switch(m_mode & 0x18) {
        case 0x00: return 14;          // 7MHz, slow mode (5.25" drives)
        case 0x08: return  7;          // 7MHz, fast mode
        case 0x10: return 16;          // 8MHz, slow mode
        case 0x18: return  8;          // 8MHz, fast mode
    }
}
```

Our Verilog equivalents (already exist in `iwm_flux.v:217-227`):
- `base_half_window`: 5.25" slow=28 (at 14MHz), 5.25" fast=14, 3.5"=14
- `base_full_window`: 5.25" slow=56, 5.25" fast=28, 3.5"=28
- These are 2x MAME values because we run at 14MHz vs MAME's 7MHz

### Write Mode Activation (iwm.cpp:237-247)

```cpp
// Q7=1 (control bit 7 set):
m_rw = MODE_WRITE;
m_rw_state = S_IDLE;
m_whd |= 0x40;                        // Set write-enable in WHD
write_clock_start();                   // Switch to Q3 clock if sync
m_floppy->set_write_splice(...)        // Mark splice point on disk
```

Our Verilog equivalent (already exists in `iwm_flux.v:543-544`):
```verilog
m_rw_mode <= 1'b1;
m_whd <= m_whd | 8'h40;
```

### Write Handshake (m_whd register)

| Bit | Meaning | Set when | Cleared when |
|-----|---------|----------|--------------|
| 7 | Underrun pending | Byte loaded into m_wsh (SW_WINDOW_LOAD) | CPU writes data (data_w, latched mode) |
| 6 | Write enabled | Write mode entered | Underrun occurs, or motor off |
| 5-0 | Status | Various | Various |

The CPU polls `m_whd` via Q6=0, Q7=1 read (`$C0EE`). The ROM write loop is:
1. Write byte to `$C0ED`
2. Read `$C0EE` and check bit 6 (write enabled) — if 0, underrun/error
3. Wait for bit 7 to assert (buffer accepted, ready for next byte)
4. Write next byte

### Flux Output → Our BRAM Mapping

MAME records flux transition timestamps, then `flush_write()` (iwm.cpp:164-193)
batch-converts them to floppy track positions via `floppy_device::write_flux()`.

**Our simplification:** We skip the intermediate flux buffer entirely.
The WOZ bitstream in BRAM *is* the bit-level disk data. When the IWM shifts
out a 1-bit, we write a 1 to BRAM at the current `bit_position`. When it
shifts out a 0-bit, we write a 0. This is done via read-modify-write on the
byte at `byte_index` using the `bit_shift` mask (both already computed in
`flux_drive.v:327-330`).

---

## Implementation Plan

### Phase 1: flux_drive Write Path (`flux_drive.v`)

Add write inputs to flux_drive and implement bit-level BRAM modification.
This is mechanical scaffolding that can be tested independently.

**New ports:**

```verilog
input wire       WRITE_BIT,     // Bit value from IWM shift register
input wire       WRITE_STROBE,  // Pulse once per bit-cell during write mode
input wire       WRITE_MODE     // 1 = suppress flux reads, accept writes
```

**BRAM write logic:** On `WRITE_STROBE` rising edge:

```verilog
// byte_index and bit_shift already computed (lines 327-330)
// BRAM_DATA is the current byte at byte_index (already being read)
reg [7:0] modified_byte;
if (WRITE_BIT)
    modified_byte = BRAM_DATA | (8'd1 << bit_shift);    // Set bit
else
    modified_byte = BRAM_DATA & ~(8'd1 << bit_shift);   // Clear bit

// Output to BRAM port B (already wired in woz_floppy_controller)
bit_data_out <= modified_byte;
bit_we_out   <= 1'b1;
bit_addr_out <= byte_index;
```

**Suppress reads during write mode:**
- When `WRITE_MODE=1`: force `FLUX_TRANSITION=0` (don't generate spurious
  read data from bits being overwritten)
- Bit position counter (`effective_bit_position`) still advances normally
  at the bit-cell rate — this keeps the write head at the correct rotational
  position

**New outputs:**

```verilog
output reg [7:0]  WRITE_BYTE_OUT,  // Modified byte data → BRAM port B
output reg        WRITE_WE_OUT,    // Write enable → BRAM port B
output reg [15:0] WRITE_ADDR_OUT   // Byte address → BRAM port B
```

### Phase 2: Signal Routing (`iwm_woz.v`)

Wire the new signals between iwm_flux, flux_drive, and woz_floppy_controller.

**iwm_flux → flux_drive:**
- `FLUX_WRITE` (bit value) → flux_drive `WRITE_BIT`
- `FLUX_WRITE_STROBE` (pulse) → flux_drive `WRITE_STROBE`
- `WRITE_MODE` (m_rw_mode) → flux_drive `WRITE_MODE`
- `WRITE_PROTECT` (from flux_drive) → iwm_flux (already connected)

**flux_drive → woz_floppy_controller:**
- Unhardwire `bit_data_in` (iwm_woz.v:520,605): connect to flux_drive `WRITE_BYTE_OUT`
- Unhardwire `bit_we` (iwm_woz.v:521,606): connect to flux_drive `WRITE_WE_OUT`
- Also route `WRITE_ADDR_OUT` for the byte address

**At this point, everything compiles and regression-passes with no behavior change**
because `FLUX_WRITE_STROBE` is still always 0 (iwm_flux.v:1611). The scaffolding
is in place for Phase 3 to activate writes.

### Phase 3: IWM Write Shift Register (`iwm_flux.v`)

This is the core new logic. Mirror MAME's sync-mode write state machine.

**New registers:**

```verilog
reg [2:0] write_bit_count;       // Bits shifted out (0-7)
reg [1:0] write_state;           // SW_IDLE, SW_MIDDLE, SW_END, SW_UNDERRUN
reg [5:0] write_window_counter;  // Countdown using same half_window timing
reg [31:0] write_data_gen;       // Snapshot of m_data_gen at last byte load
```

**State machine (runs on CLK_14M, gated by CLK_7M_EN or similar):**

Maps directly to MAME's 4 write states. Since we're in sync mode, the flow is:

```
SW_IDLE:
    // Entered when m_rw_mode transitions 0→1
    m_wsh <= m_data;
    write_state <= SW_MIDDLE;
    write_window_counter <= base_half_window;  // Wait half-window before first bit

SW_MIDDLE:
    // Shift out one bit
    FLUX_WRITE <= m_wsh[7];                    // Output MSB (1=transition, 0=none)
    FLUX_WRITE_STROBE <= 1'b1;                 // Pulse: write this bit to BRAM
    m_wsh <= {m_wsh[6:0], 1'b0};               // Shift left
    write_bit_count <= write_bit_count + 1;
    write_state <= SW_END;
    load_half_window();                         // Reuse existing timing task

SW_END:
    FLUX_WRITE_STROBE <= 1'b0;                 // Clear strobe
    // Sync mode: check if we need a byte reload
    // In MAME sync mode, data_w() writes directly to m_wsh.
    // Our equivalent: detect m_data_gen changed since last load
    if (write_bit_count == 3'd0) begin          // Just wrapped from 7→0
        // Check for underrun: did CPU write a new byte?
        if (m_data_gen == write_data_gen) begin
            // No new byte written — underrun
            m_whd <= m_whd & 8'hBF;            // Clear bit 6 (write enable)
            write_state <= SW_UNDERRUN;
        end else begin
            write_data_gen <= m_data_gen;
            // In sync mode, m_wsh was already loaded by data_w equivalent
            // (iwm_flux.v:1344-1346 already loads m_data, but we need
            //  sync-mode direct-to-wsh behavior)
        end
    end
    write_state <= SW_MIDDLE;
    load_half_window();

SW_UNDERRUN:
    // Sit idle until write mode is exited
    FLUX_WRITE_STROBE <= 1'b0;
```

**Sync-mode direct load:** The critical MAME behavior at iwm.cpp:377-378:
```cpp
if(is_sync() && m_rw == MODE_WRITE)
    m_wsh = data;
```
Our equivalent: in the existing CPU write capture block (iwm_flux.v:1344),
add sync-mode direct `m_wsh` load:
```verilog
if (WR && CEN && immediate_q7 && immediate_q6 && ADDR[0] && MOTOR_ACTIVE && !smartport_mode) begin
    m_data <= DATA_IN;
    m_data_gen <= m_data_gen + 32'd1;
    if (SW_MODE[0]) m_whd <= m_whd & 8'h7f;   // Existing: clear underrun
    if (!is_async && m_rw_mode)                 // NEW: sync-mode direct load
        m_wsh <= DATA_IN;
end
```

**Write protect gating:**
```verilog
// Gate all write outputs on !WRITE_PROTECT
assign FLUX_WRITE = (write_state == SW_MIDDLE) && m_wsh[7] && !WRITE_PROTECT;
assign FLUX_WRITE_STROBE = write_strobe_pulse && !WRITE_PROTECT;
```

**Interaction with existing underrun handling (iwm_flux.v:646-657):**
The current `write_underrun_cnt` logic clears `m_whd[6]` after ~9us when in
write mode with no data writes. This should be kept as a fallback, but
the new state machine's SW_UNDERRUN state will handle the normal case.
The existing code can remain as-is — it fires when no writes happen at all
(e.g. SmartPort probing), while SW_UNDERRUN fires when writes start but the
CPU can't keep up.

### Phase 4: Save-Back for WOZ v1 (`woz_floppy_controller.sv`)

The `S_SAVE_TRACK` state machine (lines 1050-1070) writes BRAM back to SD
using `trk_start_block` and `trk_block_count`. This works for v2 (block-aligned)
but needs adjustment for v1 (6656-byte entries at sub-block offsets).

**V1 track data layout** (from WOZ 1.0 spec):
```
Offset in TRKS: entry_index * 6656
Each entry: 6646 bytes bitstream | 2 bytes bytes_used | 2 bytes bit_count | 6 bytes splice info | 2 bytes padding
```

**Steps:**

1. **V1 save address calculation:**
   - `sd_lba` = trks_base_block + (trks_index * 13) for the starting block
   - Byte offset within first block = `trks_byte_offset` (same as read path)
   - Block count = 13 (or 14 if byte offset causes overflow into extra block)

2. **V1 DMA address adjustment** (mirror of read-side `v1_track_byte` logic):
   - During S_SAVE_TRACK DMA, when reading BRAM for output, use the inverse
     of the read-side mapping:
     ```verilog
     // Read-side (existing): v1_raw_addr → v1_track_byte (DMA offset → BRAM addr)
     // Write-side (new):     BRAM addr → DMA offset
     track_load_addr <= {blocks_processed[6:0], sd_buff_addr} - {7'd0, trks_byte_offset};
     ```
   - Only output valid data when the DMA position falls within the 6646-byte
     bitstream region (not the metadata footer)

3. **Update bit_count in footer** (optional but recommended):
   - Track byte offset 6648-6649 holds bit_count (little-endian uint16)
   - During save DMA, when the DMA position corresponds to these bytes,
     substitute the current `bit_count_side0` value
   - For typical writes (overwriting existing sectors), bit_count doesn't
     change, but this ensures correctness if a format operation occurs

### Phase 5: Testing & Edge Cases

1. **Basic write test:**
   - Boot a DOS 3.3 WOZ disk image (make a copy first!)
   - SAVE a BASIC program, verify the WOZ file is modified on host
   - Re-load the saved WOZ file, verify the program is present

2. **Write protect test:**
   - Use a WOZ file with `write_protected = 1` in INFO chunk
   - Verify write attempts return I/O error (drive senses write-protect)

3. **Save-on-seek verification:**
   - Write data, seek to a different track
   - Verify `S_SAVE_TRACK` fires (debug output)
   - Verify the dirty BRAM data is written back before the new track loads

4. **Read-after-write consistency:**
   - Write a sector, then immediately read it back
   - Verify the read data matches what was written
   - This validates that BRAM modifications read back correctly through
     the existing flux_drive read path

5. **Multi-block save alignment:**
   - Ensure save DMA handles tracks spanning many 512-byte blocks
   - Test both v1 (13 blocks/track) and v2 (variable block count) formats

6. **Regression (must pass):**
   - Run `vsim/regression.sh` — Arkanoid, Karateka, Joust, Rampage
   - All existing read-only WOZ images must still boot with the new code

---

## Risk Areas

1. **Sync-mode byte loading timing:** In MAME, `data_w()` writes directly to
   `m_wsh` during sync mode. The CPU must write the next byte between bit 7
   shifting out and bit 0 of the next byte. If our Verilog state machine
   shifts too fast relative to CPU access timing, bytes may be partially
   overwritten mid-shift. The window timing (28 14MHz cycles per half-window
   for 5.25" slow mode = 56 cycles per bit-cell, × 8 bits = 448 cycles per
   byte) gives the CPU ~32 1MHz cycles to write the next byte, which is
   plenty for the ROM's write loop.

2. **BRAM port conflicts:** Port A is used by the DMA engine (S_READ_TRACK /
   S_SAVE_TRACK). Port B is used by flux_drive for live read and now live
   write. These should never conflict because S_SAVE_TRACK only runs during
   seek (when the head is not reading/writing), and the DMA engine sets
   `busy=1` which prevents new read/write operations. But this assumption
   should be verified.

3. **WOZ v1 track size is fixed at 6656 bytes.** Writes cannot extend a track
   beyond this. This is fine for normal use (overwrites existing sectors) but
   would fail for hypothetical operations that need more track data. WOZ v2
   has variable track sizes but the same principle applies — you can't exceed
   the allocated `BlockCount * 512` bytes without restructuring the file.

4. **bit_position wrapping:** When `effective_bit_position` wraps around
   `TRACK_BIT_COUNT`, writes at the wrap point must correctly update the
   BRAM byte at position 0 (not at a stale high address). The existing
   wrap logic in flux_drive.v (line 328: `max_byte_index` clamping) should
   handle this, but should be tested.

5. **Clock domain:** The write state machine must run on the same clock
   enable as the read state machine to maintain bit-cell alignment. Both
   should use `CLK_14M` gated by appropriate enables, matching the existing
   `window_counter` decrement logic.

---

## Suggested Implementation Order

1. **Phase 1** (flux_drive write port) — mechanical scaffolding, low risk, no behavior change
2. **Phase 2** (iwm_woz.v wire-up) — also mechanical, still no behavior change
3. **Phase 3** (IWM write shift register) — this activates writes, the real work
4. **Phase 4** (v1 save-back) — needed for 5.25" WOZ write persistence
5. **Phase 5** (testing) — throughout, especially after Phase 3

Phases 1-2 can be merged into a single commit as pure scaffolding. Phase 3
should be its own commit since it's the functional change. Phase 4 can be
a separate commit since 5.25" WOZ save-back is independent of the write
mechanics.

**Minimum viable write support** (no persistence): Phases 1-3 only. Writes
modify BRAM in-memory and reads return the modified data, but nothing is
saved to the WOZ file. This is useful for games that write temporary data
(save games, high scores) during a session but don't need cross-session
persistence.
