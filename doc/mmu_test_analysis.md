# MMU Test Analysis

This document analyzes the failing MMU tests from the gsquared test suite and identifies potential issues in the `iigs.sv` implementation.

## Emulator Comparison

Results from running the MMU test suite on different emulators:

| Test | Description | Clemens | GSplus | Our Sim |
|------|-------------|---------|--------|---------|
| 01 | Normal text page shadowing | **P** | **P** | **P** |
| 02 | Text page 1 shadow inhibit | **P** | **P** | **P** |
| 03 | Shadow all banks (CYAREG[4]) | F | F | **P** |
| 04 | Shadow only video pages | **P** | **P** | **P** |
| 05 | RAMWRT shadowed to E1 | **P** | **P** | **P** |
| 06 | Aux write non-video not shadowed | **P** | **P** | **P** |
| 07 | Bank 02 + RAMWRT + all-bank shadow | F | F | F |
| 08 | Direct write bank 01 text page | **P** | **P** | **P** |
| 09 | Bank 03 text + all-bank shadow | F | F | F |
| 0A | IOLC inhibit (shadow[6]) | **P** | **P** | **P** |
| 0B | No IOLC in bank 02 normally | **P** | **P** | **P** |
| 0C | IOLC in bank 02 with all-bank shadow | F | F | F |
| 0D | Bank latch disabled (NEWVIDEO[0]) | F | F | **P** |
| 0E | Bank latch + RAMWRT | **P** | **P** | **P** |
| 0F | Bank latch + all-bank shadow | **P** | **P** | **P** |
| 10 | IOLC inhibit + aux write | F | F | F |
| 11 | RAMWRT no effect banks 02/03 | **P** | **P** | **P** |
| 12 | Language Card bank 2 ($00) | **P** | **P** | **P** |
| 13 | Language Card bank 2 ($E0) | **P** | **P** | **P** |
| 14 | LC $00 doesn't shadow to $E0 | **P** | **P** | **P** |
| 15 | LC Bank 1 + IOLC inhibit | **P** | **P** | **P** |
| 16 | ROM in bank FF | **P** | **P** | **P** |
| 17 | ROM in bank 00 shadowed | **P** | **P** | **P** |
| 18 | C071-C07F present | **P** | **P** | **P** |

### Summary

| Emulator | Pass | Fail |
|----------|------|------|
| **Clemens** | 17 | 7 |
| **GSplus** | 17 | 7 |
| **Our Sim** | 16 | 3 |

### Key Observations

1. **Tests that fail on our simulator**: 07, 0C (+ 1 more in row 01-08)

2. **Tests that fail on Clemens/GSplus** (from original testing):
   - 03, 07, 09, 0C: All-bank shadow (CYAREG[4])
   - 0D: Bank latch disabled (NEWVIDEO[0])
   - 10: IOLC inhibit + aux write combination

3. **Our simulator passes test 03** (Shadow all banks) which other emulators fail

4. **Our simulator passes test 0D** (Bank latch) which other emulators fail

---

## Failing Test Analysis

### TEST 07 - Bank 02 + RAMWRT + All-Bank Shadow (FAIL)

**What it tests:** With all-bank shadow enabled, RAMWRT should redirect bank 02 writes to bank 03.

**Pseudocode:**
```
1. Enable all-bank shadow (CYAREG = $94)
2. Enable RAMWRT
3. Write to 02:6000 - should go to bank 03 (RAMWRT affects even banks with all-bank shadow)
4. EXPECT: 03:6000 has data, 02:6000 is unchanged
```

**Issue:** CYAREG[4] is never checked. RAMWRT affecting banks other than 00/01 when all-bank shadow is enabled is not implemented.

---

### TEST 0C (12) - IOLC in Bank 02 with All-Bank Shadow (FAIL)

**What it tests:** With all-bank shadow enabled, I/O space should appear in bank 02.

**Pseudocode:**
```
1. Enable all-bank shadow (CYAREG = $94)
2. Write to 02:C010  // should go to I/O (not RAM) with all-bank shadow
3. EXPECT: 02:C010 reads as $00 (I/O ate the write)
```

**Issue:** All-bank shadow not implemented.

---

## Summary of Issues in iigs.sv

### 1. CYAREG[4] (All-Bank Shadow) - NOT IMPLEMENTED

**Affected tests:** 07, 0C

The Speed Register ($C036) bit 4 controls whether shadowing applies to all RAM banks ($00-$7F) or just banks $00/$01. This feature is completely missing from the memory controller.

**Required changes:**
- Check `CYAREG[4]` in the memory controller
- When set, enable shadow writes for banks $02-$7F (even banks -> E0, odd banks -> E1)
- When set, enable I/O space in banks $02-$7F

### 2. NEWVIDEO[0] (Bank Latch) - FIXED

**Affected tests:** 0D (now passing)

When NEWVIDEO bit 0 = 0, the bank latch is disabled and bank E1 accesses redirect to E0.

**Fix implemented:** Added logic in aux calculation and address translation to redirect E1 to E0 when NEWVIDEO[0]=0.

---

## Documentation References

### Shadow Register ($C035) - From IIGS_core2.md

| Bit | Value=1 | Value=0 |
|-----|---------|---------|
| 7 | Reserved | Reserved |
| 6 | Inhibit I/O and language card in banks $00/$01 | Enable I/O and language card |
| 5 | Inhibit Text Page 2 shadowing | Enable Text Page 2 shadowing |
| 4 | Inhibit auxiliary Hi-Res shadowing | Enable auxiliary Hi-Res shadowing |
| 3 | Inhibit Super Hi-Res shadowing | Enable Super Hi-Res shadowing |
| 2 | Inhibit Hi-Res Page 2 shadowing | Enable Hi-Res Page 2 shadowing |
| 1 | Inhibit Hi-Res Page 1 shadowing | Enable Hi-Res Page 1 shadowing |
| 0 | Inhibit Text Page 1 shadowing | Enable Text Page 1 shadowing |

### Speed Register ($C036) - From IIGS_core2.md

| Bit | Function |
|-----|----------|
| 7 | System speed: 1=2.8MHz, 0=1.024MHz |
| 6 | Power-on status |
| 5 | Reserved |
| 4 | **All-bank shadow: 1=shadow all banks $00-$7F, 0=shadow $00/$01 only** |
| 3-0 | Disk motor-on detectors |

### NEWVIDEO Register ($C029)

| Bit | Function |
|-----|----------|
| 7 | Super Hi-Res enable |
| 6 | Linearize Super Hi-Res |
| 5 | Monochrome Super Hi-Res |
| 4-1 | Reserved |
| 0 | **Bank latch: 1=normal, 0=disable (E1->E0 redirect)** |
