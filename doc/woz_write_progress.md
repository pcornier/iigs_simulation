# WOZ Write Support - Progress & Session Notes

## Current Status: Bug #6 fixed (two sub-fixes), Bug #7 fix pending test

**Branch:** `woz-write-support` (pushed to GitHub)

### Test Results
- **5.25" WOZ floppy R/W test: 06/06 ALL TESTS PASSED**
- **3.5" ProDOS test: FAILS** (SmartPort protocol not supported for WOZ drives — see below)
- **3.5" GS/OS format: Bug #5 FIXED, Bug #6 FIXED (two sub-fixes), Bug #7 pending test**
  - Bug #5: write_data_gen premature advancement → 3661 underruns → fixed
  - Bug #6a: m_whd bit 6 not re-set during active write → DONETRK check fails
  - Bug #6b: underrun timer clears bit 6 even during active shifting → DONETRK still fails
  - After Bug #6b fix: needs re-test
- **All 7 HDD regression tests: PASS**

---

## Architecture Overview

WOZ floppy write support is implemented across 5 RTL files:

| File | Role |
|------|------|
| `rtl/iwm_flux.v` | IWM write shift register state machine (SW_WINDOW_MIDDLE/END/UNDERRUN) |
| `rtl/flux_drive.v` | Physical write path: read-modify-write individual bits in track BRAM |
| `rtl/iwm_woz.v` | Signal routing between iwm_flux, flux_drive instances, and module ports |
| `rtl/iigs.sv` | Pass-through ports for write signals to top level |
| `vsim/sim.v` | Wire write signals to woz_floppy_controller BRAM port B inputs |

Supporting changes:
| File | Change |
|------|--------|
| `rtl/bram.sv` | No changes (debug output was added then removed) |
| `rtl/woz_floppy_controller.sv` | **No changes needed** — port B write inputs and dirty-flag/save-on-seek already existed |
| `vsim/sim/sim_blkdevice.cpp` | Mount flag clearing fixed for all drive types |
| `rtl/prtc.v` + `pram_init.hex` | PRAM boot scan mode for test compatibility |
| `customtests/Makefile` | Added `floppy_rw_test` build target |
| `customtests/FLOPPY_RW_TEST.S` | 6502 assembly test: writes 6 blocks with distinct patterns, reads back and compares |

---

## Bugs Found & Fixed

### Bug #1: Non-Blocking Assignment Priority Bug (5.25" — FIXED)

**Root cause:** In `iwm_flux.v`, the mode transition logic (lines ~543-567) and the state machine `case` statement (lines ~695-1411) both assign to `rw_state` using non-blocking assignments (`<=`) in the same `always @(posedge CLK_14M)` block. In Verilog, when multiple non-blocking assignments to the same register occur in the same always block, **the last one wins**.

**Effect in both directions:**

1. **Write→Read transition** (Q7 cleared): Line 548 sets `rw_state <= S_IDLE`, but the write state machine case (e.g., line 1338 `rw_state <= SW_WINDOW_END`) executes later in the same block and overrides it. The read state machine never starts. The RWTS can't find the next sector's address field, times out, and returns an error.

2. **Read→Write transition** (Q7 set): Line 559 sets `rw_state <= S_IDLE`, but the read state machine case (e.g., `rw_state <= SR_WINDOW_EDGE_1`) overrides it. The `S_IDLE` write-start check (`m_data_gen != write_data_gen`) never runs, so `START_WRITE` never fires.

**Fix:** Added `m_rw_mode` guards at the top of each state machine state:
- Read states (`SR_WINDOW_EDGE_0`, `SR_WINDOW_EDGE_1`): if `m_rw_mode` is true, force `rw_state <= S_IDLE`
- Write states (`SW_WINDOW_MIDDLE`, `SW_WINDOW_END`, `SW_UNDERRUN`): if `!m_rw_mode`, force `rw_state <= S_IDLE`

**How we found it:** The `STATE_RESET` debug message showed `state=5` (SW_WINDOW_END, a write state) when the motor stopped, even though "Switching to READ mode" had fired earlier.

### Bug #2: force_q7_data_read During Write Mode (3.5" GS/OS — FIXED)

**Symptom:** GS/OS hangs at `FF:503D: bit $c0ec` / `FF:5040: bpl ff503d` when trying to write to a 3.5" WOZ floppy. The IWM returns $00 with bit 7=0, CPU loops forever. 9000+ WRITE_UNDERRUN events in the log.

**Root cause:** In `iwm_woz.v`, `force_q7_data_read` (line 993) forces `SW_Q7` low whenever the CPU reads `$C0EC`. This hack was designed for read-mode compatibility: after the ROM writes the mode register via `$C0EF` (which sets Q7=1), it immediately reads `$C0EC` for disk data. Forcing Q7=0 makes `$C0EC` return the data register instead of the handshake register.

However, during **write mode**, the CPU reads `$C0EC` to poll the **handshake register** (Q7=1, Q6=0). Bit 7 of the handshake register is "write data register ready". The hack forces Q7=0, turning the read into a data register access (returns $00, bit 7 always 0), causing an infinite polling loop.

**Fix:** Added `!flux_write_mode` to the `force_q7_data_read` condition in `iwm_woz.v`:
```verilog
assign force_q7_data_read = bus_rd && (bus_addr == 4'hC) &&
                            selected_disk_present &&
                            selected_track_cached &&
                            drive_on &&
                            !smartport_mode &&
                            !flux_write_mode;   // <-- NEW: don't force during writes
```

**How we found it:** The GS/OS log showed `q7=0` in READ DATA events even though Q7 was set to 1 and never cleared. `SW_Q7` was forced low by `force_q7_data_read`, but `SW_Q7_MODE` (the latched Q7 used for mode transitions) stayed at 1. The write state machine was stuck in SW_UNDERRUN because `!m_rw_mode` never became true (since `SW_Q7_MODE=1` prevented the write→read transition).

### Bug #3: Write-Protect SENSE for 3.5" Drives (FIXED)

**Symptom:** 3.5" drive SENSE register `4'h6` (WRPROT status) defaulted to `1'b1` (write-protected).

**Fix:** Changed `flux_drive.v` line 508 from `sense_35 = 1'b1` to `sense_35 = DISK_WP` so the write-protect SENSE reflects the actual `DISK_WP` input.

### Bug #4: Handshake Register Bit 7 Never Set (3.5" GS/OS — FIXED)

**Symptom:** After fixing Bug #2, GS/OS still hangs at `FF:503D: bit $c0ec` / `FF:5040: bpl ff503d`. Now the CPU correctly reads the handshake register (not the data register), but gets `$3F` — bit 7=0 means "write register not ready". The CPU never writes data, START_WRITE never fires, and the write state machine is stuck.

**Root cause:** Two related issues in `iwm_flux.v`:

1. **Write mode entry only sets bit 6**, not bit 7: `m_whd <= m_whd | 8'h40`. If bit 7 was previously cleared by a data register write (`m_whd &= 0x7F` at line 1485), it stays 0. The CPU's first handshake poll fails.

2. **Byte consumption never signals "ready"**: In MAME's `SW_WINDOW_LOAD` state, consuming a byte sets `m_whd |= 0x80` to tell the CPU it can write the next byte. Our code had no equivalent — after the CPU writes data (clearing bit 7), nothing ever set it back to 1.

This created a chicken-and-egg deadlock: the CPU waits for bit 7=1 before writing, but bit 7 never gets set because no data is ever consumed.

**MAME reference** (`mame/src/devices/machine/iwm.cpp` lines 588-602):
```cpp
case SW_WINDOW_LOAD:
    if(m_whd & 0x80) {              // Bit 7 set = no new CPU data = underrun
        m_whd &= ~0x40;             // Clear bit 6 (underrun flag)
        m_rw_state = SW_UNDERRUN;
    } else {                         // Bit 7 clear = CPU wrote data
        m_wsh = m_data;              // Load shift register
        m_whd |= 0x80;              // Set bit 7 ("ready for next byte")
        m_rw_state = SW_WINDOW_MIDDLE;
    }
```

**Fix:** Three changes in `iwm_flux.v`:
1. Write mode entry: `m_whd <= m_whd | 8'hC0` (set bits 7 AND 6)
2. S_IDLE START_WRITE: add `m_whd <= m_whd | 8'h80` when consuming first byte
3. SW_WINDOW_END non-underrun path: add `m_whd <= m_whd | 8'h80` when consuming byte at boundary

### Bug #5: SW_WINDOW_END Updates write_data_gen at Every Bit (3.5" GS/OS Format — FIXED)

**Symptom:** GS/OS 3.5" format operation fails with error $027. Log shows 1 START_WRITE but 3661 WRITE_UNDERRUN events. The CPU IS writing data (data_gen increments between underruns), but the write state machine keeps detecting underruns at every byte boundary.

**Root cause:** In `iwm_flux.v` SW_WINDOW_END state, the `else` branch (line 1390) was a catch-all that handled both mid-byte bit transitions (`write_bit_count != 0`) and actual byte boundaries (`write_bit_count == 0` with new data). The branch unconditionally executed:
```verilog
write_data_gen <= m_data_gen;   // "consume" the CPU byte
m_whd <= m_whd | 8'h80;         // signal "ready for next"
if (is_async) m_wsh <= m_data;  // reload shift register
```

This ran 7 times per byte (at every mid-byte SW_WINDOW_END), prematurely advancing `write_data_gen` to match `m_data_gen`. When the actual byte boundary arrived (`write_bit_count == 0`), `m_data_gen == write_data_gen` was always true → spurious underrun.

The mid-byte `m_wsh <= m_data` also corrupted the shift register partway through shifting out a byte, and the repeated `m_whd |= 0x80` signals misleadingly told the CPU it was ready for more data.

**Fix:** Split the `else` into two cases in `iwm_flux.v`:
1. `write_bit_count == 0` (byte boundary with new data): update `write_data_gen`, `m_whd`, `m_wsh`
2. `write_bit_count != 0` (mid-byte): just advance to next bit-cell without touching any state

**How we found it:** The log showed `data_gen` incrementing between underruns (CPU was writing), yet every byte boundary check found matching gen values. Tracing the code revealed the `else` branch consumed the gen counter at every bit-cell, not just byte boundaries.

### Bug #6: Write Handshake Bit 6 Not Maintained During Active Write (3.5" GS/OS Format — FIXED, two sub-fixes)

**Symptom:** After Bug #5 fix, GS/OS format writes a full track (10,537 DATA_WRITEs, 84,355 BRAM writes, 0 underruns) but still fails with error $27. The ROM's DONETRK routine checks write handshake bit 6 and finds it cleared.

**Root cause:** Two related issues with the write handshake register (`m_whd`) bit 6 ("no underrun has occurred"):

#### Sub-fix A: Byte consume only sets bit 7, not bit 6

At `S_IDLE` START_WRITE (line 702) and `SW_WINDOW_END` byte consume (line 1395), the code did `m_whd <= m_whd | 8'h80` — setting only bit 7. Bit 6 was set once on write mode entry (`8'hC0`) but never re-asserted during active writing.

**Fix:** Changed `8'h80` to `8'hC0` at both locations, and added `write_underrun_cnt <= WRITE_UNDERRUN_DELAY_7M` to reload the underrun timer.

#### Sub-fix B: Underrun timer fires during active write shifting

The write underrun timer (`write_underrun_cnt`, 64 7MHz cycles ≈ 9µs) runs whenever `m_rw_mode && m_whd[6]`. It was designed as a fallback for "write mode entered but no data written" (the original comment says "we don't implement writes yet"). But it runs continuously — even while the write shift register is actively shifting bits. Since a single byte takes ~16µs (8 bits × 28 14MHz cycles ÷ 2) and the timer fires at 9µs, bit 6 gets cleared mid-byte.

Even with sub-fix A reloading the timer at byte boundaries, the timer fires between the last sector's final byte and the DONETRK check — a gap much larger than 9µs due to checksum computation, sync bytes, etc.

**Fix:** Added `rw_state == S_IDLE` condition to the timer:
```verilog
if (m_rw_mode && m_whd[6] && rw_state == S_IDLE) begin
```
This way the timer only runs before the first byte is written (handling the "write mode entered but no data" case). Once the state machine is actively shifting (`rw_state != S_IDLE`), bit 6 is managed exclusively by the state machine's underrun detection at `SW_WINDOW_END` (line 1368-1377), which correctly clears bit 6 only on actual byte-level underrun.

Also changed `else` to `else if (!m_rw_mode)` for the timer reset, so the counter isn't spuriously reset to 0 while writing.

**ROM DONETRK logic** (from `ad35driver_subroutines.asm`):
```
DONETRK:
  FF:4272  BIT $C0EC    ; Read handshake: V = bit 6 ("no underrun")
  FF:4275  PHP          ; Save V
  @100:
  FF:4276  BIT $C0EC    ; Wait for underrun (V=0)
  FF:4279  BVS @100     ; Loop while V=1 (still writing)
  FF:427B  LDA $C0EE    ; Switch to read mode
  FF:427E  LDA $C0EC    ; Read data register
  FF:4281  PLP          ; Restore V from first BIT
  FF:4282  SEC          ; Assume error
  FF:4283  LDA #$34     ; "write underrun error for debug"
  FF:4285  BVC WTRKERR  ; If V was 0 at FF:4272 → error (premature underrun)
  FF:4287  LDA #$00     ; V was 1 → success
  FF:4289  CLC
```

The ROM expects:
1. First `BIT $C0EC`: bit 6=1 (V=1, write still active, no underrun)
2. Poll loop: waits until bit 6=0 (V=0, underrun = last byte drained)
3. If first check had V=0: premature underrun → error $34 → escalates to error $27

**How we found it:** The DONETRK `BIT $C0EC` at FF:4272 returned `$3F` (bit 6=0, V=0) in both the pre-fix and post-sub-fix-A logs. Tracing the underrun timer at lines 669-682 showed it fires at 64 7MHz cycles regardless of active shifting.

---

## 3.5" ProDOS Write Failure (NOT a write path bug)

The ProDOS test (`FLOPPY_RW_TEST.S`) fails for 3.5" drives with error $27 (I/O error) because ProDOS 8 uses the **SmartPort protocol** for 3.5" disk I/O:

1. ROM sends 6-byte SmartPort command packet through IWM write mode (mode=$07)
2. ROM switches to read mode and searches for response byte `$C3`
3. Our simulated drive has no SmartPort microcontroller — it never sends `$C3`
4. The ROM times out (256 iterations) and returns error $27

**Why 5.25" works:** The Disk II (5.25") driver programs the IWM directly for sector read/write — no SmartPort.

**Why GS/OS works:** The GS/OS AD3.5 driver programs the IWM directly (mode=$0F) for sector read/write — no SmartPort.

**Why 3.5" boot works:** Boot code at $C500 programs the IWM directly.

**To support 3.5" ProDOS writes:** Would need to implement SmartPort device emulation layer for WOZ drives. This is a significant feature addition, not a bug fix.

---

## Debugging Approach & Timeline

### Phase 1: Confirming write data flows through IWM (5.25")
- Added `FLUX_WR` debug in `flux_drive.v` to trace each bit written to BRAM
- Confirmed BRAM writes happen: gap bytes ($FF), data prologue ($D5 $AA $AD), encoded data ($96 etc.)
- Added `BRAM_WR_B` debug in `bram.sv` to confirm writes reach BRAM memory
- **Key finding:** Only 2847 BRAM writes (~356 bytes = ~1 sector), when 12 sectors needed

### Phase 2: Counting write mode transitions (5.25")
- Grepped for `Entering WRITE mode` / `Switching to READ mode` / `START_WRITE`
- Found only 4 write mode entries, only 1 with `START_WRITE`
- After first fix (write→read): 6 START_WRITE events, 2/6 tests pass
- After second fix (read→write): 12 START_WRITE events, 6/6 tests pass

### Phase 3: Identifying the non-blocking priority bug (5.25")
- `STATE_RESET` showed `state=5` (write state) after read mode was entered
- Traced code flow: line 548 (`rw_state <= S_IDLE`) is overridden by state machine case assignments at lines 1338/1364/1378
- Applied fix to write states → 2/6 pass (some writes still missing)
- Realized same bug affects read→write direction → applied fix to read states → 6/6 pass

### Phase 4: GS/OS 3.5" write lockup — force_q7_data_read (Bug #2)
- User test: GS/OS with `--woz TEST.woz --disk gsos.hdv`, delete file from floppy → hangs
- Log showed: 9374 WRITE_UNDERRUN events, CPU stuck at `FF:503D: bit $c0ec / bpl` loop
- Traced `q7=0` in READ DATA (force_q7_data_read active) vs Q7=1 never cleared (latched q7)
- Identified `force_q7_data_read` preventing handshake register reads during write mode
- Also found SENSE register 4'h6 missing write-protect status for 3.5" drives
- ProDOS 3.5" test failure traced to SmartPort protocol: ROM looks for $C3 response byte, drive never responds

### Phase 5: GS/OS 3.5" write lockup — handshake bit 7 (Bug #4)
- After Bug #2 fix, user retested: "still broken". New log showed different behavior.
- Now reads handshake register correctly (`READ HANDSHAKE @c -> 3f`), but bit 7=0
- Traced m_whd value: $3F = bits 7 and 6 both 0. Write mode entry only sets bit 6 (`|= 0x40`)
- Found prior data register write cleared bit 7 (`m_whd &= 0x7F`), and nothing re-set it
- Compared against MAME's `SW_WINDOW_LOAD` state: sets `m_whd |= 0x80` when consuming byte
- Our code had no equivalent — m_whd bit 7 was never restored after being cleared
- Fix: set bit 7 at write mode entry (`|= 0xC0`), at START_WRITE, and at byte boundary consumption

### Phase 6: GS/OS 3.5" format — write_data_gen premature advancement (Bug #5)
- Format log: 10,537 DATA_WRITEs, 3,661 WRITE_UNDERRUNs, 84,355 BRAM writes
- CPU writing data (data_gen incrementing) but underruns at every byte boundary
- Traced: `else` catch-all in SW_WINDOW_END ran at every bit, not just byte boundaries
- Fix: split into `write_bit_count == 0` (byte boundary) vs else (mid-byte)
- After fix: 0 underruns, full track written

### Phase 7: GS/OS 3.5" format — DONETRK handshake bit 6 failure (Bug #6)
- After Bug #5 fix: 0 underruns, 10,537 data writes, but format still returns error $27
- ROM's DONETRK at FF:4272 reads handshake = $3F (bit 6=0, V=0) → write underrun error $34
- **Sub-fix A:** Byte consume used `m_whd |= 0x80` (bit 7 only), not `0xC0` (bits 7+6). Fixed.
- **Sub-fix B (after second failed test):** Underrun timer at lines 669-682 clears bit 6 after 64 7MHz cycles, even during active shifting. Timer fires mid-byte and between ROM instructions during the write loop. Fixed by adding `rw_state == S_IDLE` guard so timer only runs before first byte.
- After both sub-fixes: handshake returns $FF/$BF during write (bit 6 set). Pending test.

---

## Test Commands

### 5.25" WOZ floppy R/W test (PASSING)
```bash
cd vsim
./obj_dir/Vemu --disk ../customtests/floppy_rw_test.2mg --woz ../customtests/floppy_rw_525.woz --screenshot 3000 --stop-at-frame 3000 --no-cpu-log
```
Expected: Screenshot shows "06/06 ALL TESTS PASSED"

### 3.5" WOZ floppy R/W test (FAILS — SmartPort issue, not write path bug)
```bash
cd vsim
./obj_dir/Vemu --disk ../customtests/floppy_rw_test.2mg --woz ../customtests/floppy_rw_35.woz --screenshot 3000 --stop-at-frame 3000 --no-cpu-log
```
Expected: 00/06 FAILURES (SmartPort $C3 response not implemented)

### 3.5" GS/OS format test (Bug #6 fixed, pending verification)
```bash
cd vsim
./obj_dir/Vemu --woz blank.woz --disk gsos.hdv
```
Steps: Boot GS/OS → it detects blank floppy → prompts to format → should succeed
Expected: Format completes, writes all 80 tracks (160 sides), no error $27

### 3.5" GS/OS write test (MANUAL — needs verification)
```bash
cd vsim
./obj_dir/Vemu --woz TEST.woz --disk gsos.hdv
```
Steps: Click OK → Open floppy → Drag file to trash → Empty trash
Expected: Should complete without hanging (previously locked up at FF:503D)

### Regression tests
```bash
cd vsim
./regression.sh
```
Expected: All 7 tests pass (Total Replay, Pitch Dark, GS/OS, Arkanoid, Total Replay II, BASIC boot, MMU test)

### Build
```bash
cd vsim
make clean && make
```

### Useful debug greps
```bash
# Count sector writes
grep -c "START_WRITE" output.log

# Trace write mode transitions
grep -E "(Entering WRITE|Switching to READ|START_WRITE|Motor off|STATE_RESET)" output.log

# Count BRAM writes
grep -c "BRAM_WR_B" output.log    # (requires adding debug back to bram.sv)

# Trace individual bit writes
grep "FLUX_WR" output.log          # (requires adding debug back to flux_drive.v)

# Count write underruns (should be 0 in normal operation, thousands = stuck)
grep -c "WRITE_UNDERRUN" output.log

# Check DONETRK handshake bit 6 (should be $FF or $7F for success)
grep "FF:4272" output.log          # DONETRK first BIT check

# Count write mode entries by type
grep -c "mode=0f" output.log       # Direct IWM (3.5" GS/OS format)
grep -c "mode=07" output.log       # SmartPort (boot/ProDOS)

# Trace drive ready state
grep -a "Drive ready\|motor_spinning\|Motor ON\|Motor OFF" output.log
```

---

## Remaining Work

### Must Do
- [ ] Test Bug #6 fix (format blank WOZ floppy in GS/OS)
- [ ] Manually verify 3.5" GS/OS write fix (delete file from WOZ floppy in GS/OS)
- [ ] Verify save persistence: after writes, seek to different track (triggers dirty-flag save-on-seek via `S_SAVE_TRACK`), then re-load WOZ file and confirm data persists

### 3.5" ProDOS Support (SmartPort)
- [ ] Implement SmartPort device emulation for WOZ 3.5" drives (responds to command packets with $C3 sync + result data)
- [ ] Or: create a direct-IWM test program that bypasses ProDOS for 3.5" write testing

### Nice to Have
- [ ] Restore `FIRST_BLK` in test program to 10 once seeking/multi-track writes verified
- [ ] Test with real copy-protected WOZ disks that have write operations (e.g., save games)

---

## Key Design Details

### Write Shift Register (iwm_flux.v)
- **Sync mode** (mode=$00, 5.25" Disk II): CPU writes go directly to `m_wsh` via `if (!is_async && m_rw_mode) m_wsh <= DATA_IN;`
- **Async mode** (mode=$0F, 3.5" drives): CPU writes go to `m_data`, loaded to `m_wsh` at byte boundaries
- **Underrun behavior**: MAME-compatible — clear WHD bit 6 but CONTINUE writing (don't stop). The CPU timing budget is tight (~32µs per byte) and underruns are normal during self-sync gaps.
- **Bit cell timing**: `base_half_window` = 28 (5.25") or 14 (3.5"), full window = 56 or 28 14MHz cycles

### Write Handshake Register (m_whd) Bit Semantics
- **Bit 7**: "ready for next byte" — set when write state machine consumes a byte, cleared when CPU writes new data
- **Bit 6**: "no underrun" — set when entering write mode and at each byte consume, cleared ONLY on actual underrun (shift register empties at byte boundary with no new CPU data)
- **Underrun timer**: Only active in S_IDLE state (before first byte written). Clears bit 6 after 64 7MHz cycles (~9µs) if no data arrives. Disabled during active shifting — state machine manages bit 6 exclusively.
- **DONETRK check**: ROM reads bit 6 via `BIT $C0EC` (sets V from bit 6). V=1 means write was active (success). V=0 means premature underrun (error $34).

### BRAM Write Path (flux_drive.v)
- 1-cycle delayed read-modify-write: `WRITE_STROBE` sets address, next cycle reads BRAM data and writes modified byte
- `bit_shift = 7 - effective_bit_position[2:0]` (MSB-first within each byte)
- Look-ahead prefetch disabled during write mode (`BRAM_ADDR = byte_index` directly)
- `FLUX_TRANSITION` suppressed during `WRITE_MODE` to prevent read interference

### Save-Back Path (woz_floppy_controller.sv — NO CHANGES NEEDED)
- `dirty` flag set whenever `bit_we` pulses (line 507)
- On track seek, if `dirty`, enters `S_SAVE_TRACK` which DMAs BRAM back to SD image
- `trk_start_block` and `trk_block_count` computed during track load for both v1 and v2 formats
- SD write protocol already implemented in `sim_blkdevice.cpp`

### Q7 Force Hack (iwm_woz.v — force_q7_data_read)
- **Purpose:** After ROM writes mode register via $C0EF (Q7→1), immediately reads $C0EC for data. Without hack, Q7=1 makes $C0EC a handshake read. Hack forces Q7=0 for data reads.
- **Guards:** `!smartport_mode` (SmartPort uses Q7=1 for handshake polling), `!flux_write_mode` (write mode uses Q7=1 for "buffer ready" polling)
- **Scope:** Only applies to `SW_Q7` (immediate Q7 for iwm_flux), NOT `SW_Q7_MODE` (latched Q7 for mode transitions). This prevents forced data reads from resetting the read state machine.

### 3.5" vs 5.25" Write Mode Differences
- **5.25" (mode=$00, sync):** CPU writes directly load `m_wsh`. `smartport_mode=0`. Data writes always bump `m_data_gen`.
- **3.5" GS/OS (mode=$0F, async):** CPU writes go to `m_data`, loaded to `m_wsh` at byte boundaries. `smartport_mode=0` (bit 3=1). Direct IWM programming.
- **3.5" SmartPort (mode=$07, async):** SmartPort command protocol. `smartport_mode=1` initially (bit 3=0, bit 1=1), but mode changes to $0F during data transfer. SmartPort device response ($C3) not implemented for WOZ drives.

### ROM Format Flow (ad35driver_subroutines.asm)
Key routines in `Bank FF/ad35driver_subroutines.asm`:
- **FORMAT** (FF:4110): Main entry — calls WRITETRK for each track/side
- **WRITETRK** (FF:4193): Calls initwtrk, WaitRdyTO, then the write loop
- **WTNOWAIT** (FF:41C0): Sets up IWM write mode, writes sectors
- **DONETRK** (FF:4272): Post-write handshake check (bit 6 = V flag)
- **FMTERR** (FF:4189): Error handler — loads error $27, calls eject
- **EJECT** (FF:48AE): Seeks to track 79, turns motor off, waits
- **WaitRdyTO** (FF:4925): Polls /READY sense ($0B) for up to 1500ms
- **ReadBit/WriteBit** (FF:497B/4985): Sony drive sense/command via LSTRB
- **SDCLINES** (FF:498F): Sets CA0/CA1/CA2/SEL control lines for Sony commands
