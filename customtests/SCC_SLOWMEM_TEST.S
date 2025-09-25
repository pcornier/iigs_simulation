;****************************************************************
;* SCC_SLOWMEM_TEST.S
;*
;* Test to reproduce SCC slowMem logic bug
;*
;* The bug: SCC registers (C038-C03B) should trigger slowMem=1
;* but are incorrectly getting slowMem=0
;*
;* Test Strategy:
;* 1. Write known values to SCC registers
;* 2. Read them back immediately
;* 3. Display results to detect if slowMem routing is wrong
;*
;****************************************************************

            ORG     $2000
            DSK     SCC.SYSTEM
            TYP     'SYS'
            MX      %11

HOME        EQU     $FC58
COUT        EQU     $FDED

START
            JSR     HOME

            ; Print test message
            LDX     #0
PRINT_MSG   LDA     MSG,X
            BEQ     DO_TEST
            JSR     COUT
            INX
            BNE     PRINT_MSG

DO_TEST
            ; Test SCC register access (should use slowMem=1)
            ; This matches the failing pattern from the trace

            ; Write test values to SCC registers
            LDA     #$0B                ; Test value from trace
            STA     $C039               ; SCC register

            LDA     #$D2                ; Second test value from trace
            STA     $C039

            ; Test other SCC registers
            LDA     #$AA
            STA     $C038

            LDA     #$55
            STA     $C03A

            LDA     #$CC
            STA     $C03B

            ; Read back values and check
            LDA     $C038
            CMP     #$AA
            BNE     SCC_FAIL

            LDA     $C039
            CMP     #$D2
            BNE     SCC_FAIL

            LDA     $C03A
            CMP     #$55
            BNE     SCC_FAIL

            LDA     $C03B
            CMP     #$CC
            BNE     SCC_FAIL

            ; If we get here, SCC registers work
            LDX     #0
PRINT_OK    LDA     OK_MSG,X
            BEQ     HANG
            JSR     COUT
            INX
            BNE     PRINT_OK
            JMP     HANG

SCC_FAIL
            ; SCC register test failed
            LDX     #0
PRINT_FAIL  LDA     FAIL_MSG,X
            BEQ     HANG
            JSR     COUT
            INX
            BNE     PRINT_FAIL

HANG
            JMP     HANG

MSG         ASC     'SCC SLOWMEM TEST: ',00
OK_MSG      ASC     'SCC REGISTERS OK',00
FAIL_MSG    ASC     'SCC REGISTERS FAIL!',00