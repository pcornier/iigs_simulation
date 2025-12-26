# MMU Test Analysis

This document analyzes the failing MMU tests from the gsquared test suite and identifies potential issues in the `iigs.sv` implementation.

## Test Results Summary

Based on running `customtests/mmu_test.2mg`, the following tests are **passing**:
- 01, 04, 06, 0B (11), 0E (14)

The following tests are **failing**:
- 02, 03, 05, 07, 08, 09, 0A (10), 0C (12), 0D (13), 0F (15), 10 (16), and others

---

## Failing Test Analysis

### TEST 02 - Text Page 1 Shadowing Inhibited (FAIL)

**What it tests:** When shadow register bit 0 = 1, text page 1 shadowing should be disabled.

**Pseudocode:**
```
1. Clear E0:0400-0401 to $00
2. Set SHADOW register ($C035) = $09  // bit 0 = 1 inhibits text page 1 shadow
3. Write $12, $34 to 00:0400-0401
4. Read E0:0400-0401
5. EXPECT: E0:0400 = $00 (NOT shadowed because bit 0 = 1)
```

**Documentation Reference (IIGS_core2.md):**
> "Text Page 1 inhibit: When this bit is 1, shadowing is disabled for text Page 1 and auxiliary text Page 1."

**Current Implementation (iigs.sv:427):**
```verilog
wire txt1_shadow = ~shadow[0] && (page == 4'h0 && addr_bef[11:8] >= 4'h4 && addr_bef[11:8] <= 4'h7);
```

**Analysis:** The logic appears correct - `~shadow[0]` means shadow is active when bit 0 is 0. The test failing suggests that writes to bank 00 may be ALWAYS being shadowed to E0, regardless of the shadow register setting. Need to verify the shadow bit is being respected in all write code paths.

---

### TEST 03 - Shadow All Banks (FAIL)

**What it tests:** When CYAREG bit 4 = 1, writes to ANY RAM bank should shadow to E0/E1.

**Pseudocode:**
```
1. Set CYAREG ($C036) = $94  // bit 4 = 1 enables shadowing for ALL RAM banks
2. Write $56, $78 to 02:0402-0403
3. Set CYAREG = $84  // disable all-bank shadow
4. Read E0:0402-0403
5. EXPECT: E0:0402 = $56 (bank 02 write was shadowed to E0)
```

**Documentation Reference (IIGS_core2.md):**
> "Bank shadowing bit: This bit determines memory shadowing in the RAM banks... To enable shadowing in all RAM banks, $00 through $7F, set this bit to 1."

**Issue:** **CYAREG[4] is NEVER CHECKED** in the memory controller logic! The all-bank shadowing feature is completely unimplemented. Looking at iigs.sv lines 446-490, only banks 00 and 01 are handled for shadowing - there's no code path that enables shadow writes from banks 02-7F.

---

### TEST 05 - RAMWRT Shadowing to E1 (FAIL)

**What it tests:** When RAMWRT is enabled, writes to bank 00 text page should go to bank 01 AND shadow to E1.

**Pseudocode:**
```
1. Clear E0:0400 and E1:0400 to $00
2. Set $C005 (enable RAMWRT - writes go to aux memory)
3. Write $56, $78 to 00:0400-0401  // should go to bank 01, and shadow to E1
4. Clear RAMWRT
5. EXPECT: E1:0400 = $56, E0:0400 = $00
```

**Analysis:** When RAMWRT is enabled and a write to bank 00 text page occurs, the write should go to bank 01 AND shadow to bank E1. The aux calculation (iigs.sv:1695) handles aux memory selection, but the shadow write path may not be routing to E1 when accessed via RAMWRT.

---

### TEST 07 - Bank 02 + RAMWRT + All-Bank Shadow (FAIL)

**What it tests:** With all-bank shadow enabled, RAMWRT should redirect bank 02 writes to bank 03.

**Pseudocode:**
```
1. Enable all-bank shadow (CYAREG = $94)
2. Enable RAMWRT
3. Write to 02:6000 - should go to bank 03 (RAMWRT affects even banks with all-bank shadow)
4. EXPECT: 03:6000 has data, 02:6000 is unchanged
```

**Issue:** Same as TEST 03 - CYAREG[4] is never checked. Additionally, RAMWRT affecting banks other than 00/01 when all-bank shadow is enabled is not implemented.

---

### TEST 08 - Direct Write to Bank 01 Text Page (FAIL)

**What it tests:** Direct writes to bank 01 text page should shadow to E1.

**Pseudocode:**
```
1. Clear E1:0400-0401
2. Write $56, $78 directly to 01:0400-0401
3. EXPECT: E1:0400 = $56 (shadowed)
```

**Current Implementation (iigs.sv:464-485):** Bank 01 shadow logic exists, but needs verification that direct writes are triggering the shadow path.

---

### TEST 09 - Bank 03 Text Page with All-Bank Shadow (FAIL)

**What it tests:** With all-bank shadow, writes to odd banks should shadow to E1.

**Pseudocode:**
```
1. Enable all-bank shadow (CYAREG = $94)
2. Write to 03:0400 (odd bank, text page)
3. EXPECT: E1:0400 = data (shadowed to E1 for odd banks)
```

**Issue:** CYAREG[4] not implemented - all-bank shadowing doesn't exist.

---

### TEST 0A (10) - IOLC Inhibit (FAIL)

**What it tests:** When shadow bit 6 = 1, $C000-$CFFF in banks 00/01 should be RAM, not I/O.

**Pseudocode:**
```
1. Set SHADOW = $68  // bit 6 = 1 inhibits I/O in banks 00/01
2. Write $12 to 00:C010  // should go to RAM, not I/O
3. Read 00:C010
4. EXPECT: Returns $12 (RAM, not I/O device)
```

**Documentation Reference (IIGS_core2.md):**
> "When this bit is 1, the I/O space and language card are inhibited, and contiguous RAM is available from $0000 through $FFFF."

**Current Implementation (iigs.sv:310):**
```verilog
assign inhibit_cxxx = lcram2_sel | ((bank_bef == 8'h0 | bank_bef == 8'h1) & shadow[6]);
```

**Analysis:** The `inhibit_cxxx` signal checks `shadow[6]`, but the memory controller may not be routing $C000-$CFFF to RAM properly when IOLC is inhibited.

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

### TEST 0D (13) - Bank Latch Disabled (FAIL)

**What it tests:** When NEWVIDEO bit 0 = 0, bank E1 accesses should redirect to E0.

**Pseudocode:**
```
1. Set NEWVIDEO ($C029) = $00  // bit 0 = 0 disables bank latch
2. Write to E1:6000  // should actually go to E0 (bank latch disabled)
3. EXPECT: E0:6000 has data, E1:6000 is unchanged
```

**Documentation Reference:** When NEWVIDEO bit 0 = 0, the "bank latch" is disabled and accesses to bank E1 should be redirected to E0.

**Issue:** There is no logic in iigs.sv checking `NEWVIDEO[0]` for bank E1 -> E0 redirection.

---

### TEST 0F (15) - Bank Latch Disabled + All-Bank Shadow (FAIL)

**What it tests:** Combined bank latch disable with all-bank shadow.

**Issue:** Both features are unimplemented.

---

### TEST 10 (16) - IOLC Inhibit + Aux Write (FAIL)

**What it tests:** IOLC inhibit should not affect IIe-style memory management (RAMWRT).

**Pseudocode:**
```
1. Enable IOLC inhibit (SHADOW = $68)
2. Enable RAMWRT
3. Write to 00:6400 (should go to bank 01)
4. Write to E0:6401 (should go to E1 via RAMWRT)
5. EXPECT: 01:6400 has data, E1:6401 has data
```

**Analysis:** IIe memory management (RAMRD/RAMWRT) should work independently of IOLC inhibit.

---

## Summary of Issues in iigs.sv

### 1. CYAREG[4] (All-Bank Shadow) - NOT IMPLEMENTED

**Affected tests:** 03, 07, 09, 0C, 0F

The Speed Register ($C036) bit 4 controls whether shadowing applies to all RAM banks ($00-$7F) or just banks $00/$01. This feature is completely missing from the memory controller.

**Required changes:**
- Check `CYAREG[4]` in the memory controller
- When set, enable shadow writes for banks $02-$7F (even banks -> E0, odd banks -> E1)
- When set, enable I/O space in banks $02-$7F

### 2. NEWVIDEO[0] (Bank Latch) - NOT IMPLEMENTED

**Affected tests:** 0D, 0F

When NEWVIDEO bit 0 = 0, the bank latch is disabled and bank E1 accesses should redirect to E0.

**Required changes:**
- Add logic to redirect bank E1 accesses to E0 when `NEWVIDEO[0] == 0`

### 3. Shadow Register Inhibit Bits - POSSIBLY BUGGY

**Affected tests:** 02

The shadow[0] bit should disable text page 1 shadowing when set to 1. The current implementation looks correct but may have timing or path issues.

**Investigation needed:**
- Verify `txt1_shadow` signal is being checked in ALL write paths
- Verify shadow register value is stable when checked

### 4. RAMWRT + Shadowing Interaction - POSSIBLY BUGGY

**Affected tests:** 05, 07, 10

When RAMWRT redirects a write to aux memory (bank 01), the shadow to E1 may not be occurring correctly.

**Investigation needed:**
- Trace RAMWRT + text page write to verify shadow path
- Verify `slowram_ce_int` is set when writing to bank 01 text page via RAMWRT

### 5. Bank 01 Direct Write Shadowing - POSSIBLY BUGGY

**Affected tests:** 08

Direct writes to bank 01 text page should shadow to E1.

**Investigation needed:**
- Verify bank 01 text page writes trigger `slowram_ce_int`

### 6. IOLC Inhibit (shadow[6]) - POSSIBLY INCOMPLETE

**Affected tests:** 0A, 10

When shadow[6] = 1, $C000-$CFFF in banks 00/01 should be contiguous RAM.

**Investigation needed:**
- Verify memory controller routes $Cxxx to RAM when `shadow[6] == 1`
- Check that `inhibit_cxxx` signal properly gates I/O access

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
