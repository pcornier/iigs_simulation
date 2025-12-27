# Selftest 04 (RAM Address Test) Analysis

This document describes the ROM selftest 04 (RAM Address Test) and the simulation fix required to make it pass.

## Test Overview

Selftest 04 tests the unique addressing capability of Apple IIgs RAM. It writes patterns to RAM at various addresses and verifies the data can be read back correctly. This test is **destructive** - it overwrites:
- `$0400-$BFFF` in all banks
- `$D000-$FFFF` (Language Card area)

Error code: `AA=04`, `BB=F` Failed Bank No, `CC=Failed bit`

## Why The Test Was Failing

The ROM RAM address test sets `shadow=$7F` during execution. This enables **IOLC inhibit** (shadow bit 6), which normally causes I/O space accesses in banks 00/01 to read/write RAM instead of triggering soft switch side effects.

The problem: The test needs to access Language Card soft switches (`$C080-$C08F`) to enable LC RAM for verification. With IOLC inhibit active, these soft switch accesses were being treated as RAM accesses, so the LC state machine never changed.

### The Core Issue

```
shadow[6] = 1  (IOLC inhibit enabled)
     |
     v
CPU reads $C08B (should enable LC RAM bank 1 for read/write)
     |
     v
IO signal = 0 (blocked by IOLC inhibit)
     |
     v
LC state machine NOT triggered (RDROM, LC_WE unchanged)
     |
     v
Test tries to verify LC RAM but ROM is still mapped
     |
     v
FAIL
```

## The Fix: LC_IO Signal

Real Apple IIgs hardware allows LC soft switches to work even when IOLC inhibit is active. The fix adds an `LC_IO` signal that detects LC switch accesses regardless of shadow[6]:

```verilog
// LC_IO: Language Card soft switches ($C080-$C08F) should ALWAYS trigger
// their side effects, even when IOLC is inhibited (shadow[6]=1).
wire LC_IO = ~EXTERNAL_IO & cpu_addr[15:8] == 8'hC0 & (cpu_addr[7:4] == 4'h8) &
             (bank_bef == 8'h00 | bank_bef == 8'h01 | bank_bef == 8'he0 | bank_bef == 8'he1);
```

When `LC_IO && ~IO`, the LC state machine is still triggered even though normal I/O is blocked.

## Simple Test Case

Here's a minimal test demonstrating the LC behavior with IOLC inhibit:

```assembly
; Test LC switches work with IOLC inhibit
        ORG   $2000

        CLC
        XCE             ; Native mode
        SEP   #$30      ; 8-bit A/X/Y

        ; Enable IOLC inhibit
        LDA   #$7F
        STA   $C035     ; shadow = $7F (bit 6 = IOLC inhibit)

        ; Access LC switch - should still work!
        LDA   $C08B     ; Enable LC RAM bank 1, read/write (RR)
        LDA   $C08B     ; Second read enables write

        ; Write to LC area
        LDA   #$A5
        STA   $D000     ; Write to LC RAM

        ; Verify
        LDA   $D000     ; Read back
        CMP   #$A5
        BNE   FAIL

        ; PASS - LC switches worked despite IOLC inhibit
PASS    LDA   #'P'
        STA   $0400
        BRA   HANG

FAIL    LDA   #'F'
        STA   $0400

HANG    BRA   HANG
```

**Without the fix**: The `LDA $C08B` reads RAM at $C08B instead of triggering the LC state change. The subsequent write to `$D000` goes to ROM (which ignores writes), and the read back gets ROM data, causing the test to fail.

**With the fix**: The LC state machine responds to `$C08B` access even with IOLC inhibit, properly enabling LC RAM for the write/read verification.

## Test Harness Notes

The `customtests/SELFTEST04.S` test harness required additional fixes:

1. **Safe area for return handler**: The RAM test destroys `$0400-$BFFF`, so the return handler must be copied to `$0300` (below the test range) before calling the ROM test.

2. **TST.STATUS overlap**: The handler code spans `$0300-$038E`, which overlaps with TST.STATUS registers at `$0315-$0319`. The status registers must be cleared BEFORE copying the handler.

3. **Position-independent branching**: Use `BRA` instead of `JMP` for the infinite loop, since relative branches work correctly when code is copied to a different address.

## MMU_TEST Test 26

The `customtests/MMU_TEST.S` includes Test 26 which specifically verifies LC switches work with IOLC inhibit. The test strategy uses bank 00:D000 for verification since E0:D000 is always slow RAM (video bank) and not affected by RDROM:

1. Enable LC RAM via E0 (always has I/O) and write marker to 00:D000
2. Switch to ROM via E0, verify 00:D000 returns ROM data
3. Set IOLC inhibit (shadow=$7F) - blocks 00/01 I/O
4. Try to enable LC RAM via bank 00 $C08B (needs LC_IO fix!)
5. Disable IOLC inhibit, read 00:D000 - if LC enabled, get marker

**Important note**: With IOLC inhibit active (shadow[6]=1), bank 00/01 D000-FFFF accesses also go to fast RAM instead of LC RAM/ROM. Verification must be done after disabling IOLC inhibit.

## Related Files

- `rtl/iigs.sv`: LC_IO signal and handler (lines 327-331, 1639-1721)
- `customtests/SELFTEST04.S`: Test harness for running selftest 04
- `customtests/MMU_TEST.S`: Test 26 verifies LC+IOLC inhibit behavior
- `doc/selftest.md`: Official Vegas ROM Diagnostics documentation
